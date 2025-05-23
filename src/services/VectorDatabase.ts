import { QdrantClient } from '@qdrant/qdrant-js';
import axios from 'axios';
import { ConfigManager } from '../config/ConfigManager';
import { Logger } from '../utils/Logger';

interface DocumentInfo {
    id: string;
    filename: string;
    filepath: string;
    size: number;
    modifiedTime: Date;
    hash: string;
    type: 'pdf' | 'doc' | 'docx';
    content?: string;
}

interface DocumentChunk {
    id: string;
    documentId: string;
    chunkIndex: number;
    content: string;
    embedding: number[];
    createdAt: Date;
}

interface SearchResult {
    documentId: string;
    filename: string;
    content: string;
    similarity: number;
    chunkIndex: number;
}

export class VectorDatabase {
    private config: ConfigManager;
    private logger: Logger;
    private client: QdrantClient | null = null;
    private embeddingService: string;
    private embeddingDimension: number;
    private documentsCollectionName: string = 'documents';
    private chunksCollectionName: string = 'document_chunks';

    constructor(config: ConfigManager, logger: Logger) {
        this.config = config;
        this.logger = logger;
        this.embeddingService = config.get('embedding.service', 'http://localhost:11434/api/embeddings');
        this.embeddingDimension = config.get('embedding.dimension', 384);
    }

    public async initialize(): Promise<void> {
        try {
            // Підключення до Qdrant
            const dbConfig = this.config.get('database');
            this.client = new QdrantClient({
                url: dbConfig.url || 'http://localhost:6333',
                apiKey: dbConfig.apiKey,
            });

            this.logger.info('Підключено до Qdrant');

            // Створення колекцій якщо їх немає
            await this.createCollections();
            
        } catch (error) {
            this.logger.error('Помилка при ініціалізації бази даних:', error);
            throw error;
        }
    }

    private async createCollections(): Promise<void> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            // Перевіряємо чи існує колекція документів
            const collectionsResponse = await this.client.getCollections();
            const collections = collectionsResponse.collections.map(col => col.name);

            // Створюємо колекцію документів якщо її немає
            if (!collections.includes(this.documentsCollectionName)) {
                this.logger.info(`Створення колекції ${this.documentsCollectionName}`);
                await this.client.createCollection(this.documentsCollectionName, {
                    vectors: {
                        size: this.embeddingDimension,
                        distance: 'Cosine'
                    }
                });

                // Створюємо індекси для колекції документів
                await this.client.createPayloadIndex(this.documentsCollectionName, {
                    field_name: 'hash',
                    field_schema: 'keyword'
                });

                await this.client.createPayloadIndex(this.documentsCollectionName, {
                    field_name: 'filename',
                    field_schema: 'keyword'
                });
            }

            // Створюємо колекцію чанків якщо її немає
            if (!collections.includes(this.chunksCollectionName)) {
                this.logger.info(`Створення колекції ${this.chunksCollectionName}`);
                await this.client.createCollection(this.chunksCollectionName, {
                    vectors: {
                        size: this.embeddingDimension,
                        distance: 'Cosine'
                    }
                });

                // Створюємо індекси для колекції чанків
                await this.client.createPayloadIndex(this.chunksCollectionName, {
                    field_name: 'documentId',
                    field_schema: 'keyword'
                });

                await this.client.createPayloadIndex(this.chunksCollectionName, {
                    field_name: 'chunkIndex',
                    field_schema: 'integer'
                });
            }

            this.logger.info('Колекції бази даних створено/перевірено');
        } catch (error) {
            this.logger.error('Помилка при створенні колекцій:', error);
            throw error;
        }
    }

    public async addDocument(document: DocumentInfo, chunks: string[]): Promise<void> {
        if (!this.client) throw new Error('База даних не ініціалізована');
        
        try {
            // Генеруємо ембединг для документа
            const documentEmbedding = await this.generateEmbedding(document.content || document.filename);
            
            // Додаємо документ
            await this.client.upsert(this.documentsCollectionName, {
                points: [
                    {
                        id: document.id,
                        vector: documentEmbedding,
                        payload: {
                            filename: document.filename,
                            filepath: document.filepath,
                            fileSize: document.size,
                            modifiedTime: document.modifiedTime.toISOString(),
                            hash: document.hash,
                            fileType: document.type,
                            content: document.content || '',
                            createdAt: new Date().toISOString(),
                            updatedAt: new Date().toISOString()
                        }
                    }
                ]
            });

            // Додаємо чанки з ембедингами
            for (let i = 0; i < chunks.length; i++) {
                const chunkId = `${document.id}_chunk_${i}`;
                const embedding = await this.generateEmbedding(chunks[i]);

                await this.client.upsert(this.chunksCollectionName, {
                    points: [
                        {
                            id: chunkId,
                            vector: embedding,
                            payload: {
                                documentId: document.id,
                                chunkIndex: i,
                                content: chunks[i],
                                createdAt: new Date().toISOString()
                            }
                        }
                    ]
                });
            }

            this.logger.debug(`Документ ${document.filename} додано до бази з ${chunks.length} чанками`);

        } catch (error) {
            this.logger.error(`Помилка при додаванні документа ${document.filename}:`, error);
            throw error;
        }
    }

    private async generateEmbedding(text: string): Promise<number[]> {
        try {
            const response = await axios.post(this.embeddingService, {
                model: this.config.get('embedding.model', 'nomic-embed-text'),
                prompt: text
            }, {
                timeout: 30000
            });

            return response.data.embedding || response.data.embeddings || [];
        } catch (error) {
            this.logger.error('Помилка при генерації ембединга:', error);
            
            // Fallback - повертаємо випадковий вектор (для тестування)
            this.logger.warn('Використовуємо випадковий ембединг для тестування');
            return Array.from({ length: this.embeddingDimension }, () => Math.random() - 0.5);
        }
    }

    public async searchSimilar(query: string, limit: number = 10): Promise<SearchResult[]> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            // Генеруємо ембединг для запиту
            const queryEmbedding = await this.generateEmbedding(query);

            // Виконуємо векторний пошук
            const searchResults = await this.client.search(this.chunksCollectionName, {
                vector: queryEmbedding,
                limit: limit,
                with_payload: true
            });
            
            // Отримуємо метадані документів для знайдених чанків
            const documentIds = [...new Set(searchResults.map(r => r.payload?.documentId as string))];
            const documents = await this.getDocumentsById(documentIds);
            
            // Формуємо результати
            const results: SearchResult[] = [];
            for (const result of searchResults) {
                const documentId = result.payload?.documentId as string;
                const document = documents.find(d => d.id === documentId);
                
                if (document) {
                    results.push({
                        documentId,
                        filename: document.filename,
                        content: result.payload?.content as string,
                        similarity: result.score || 0,
                        chunkIndex: result.payload?.chunkIndex as number
                    });
                }
            }

            return results;
        } catch (error) {
            this.logger.error('Помилка при пошуку:', error);
            throw error;
        }
    }

    private cosineSimilarity(vec1: number[], vec2: number[]): number {
        if (vec1.length !== vec2.length) return 0;

        let dotProduct = 0;
        let norm1 = 0;
        let norm2 = 0;

        for (let i = 0; i < vec1.length; i++) {
            dotProduct += vec1[i] * vec2[i];
            norm1 += vec1[i] * vec1[i];
            norm2 += vec2[i] * vec2[i];
        }

        const magnitude = Math.sqrt(norm1) * Math.sqrt(norm2);
        return magnitude === 0 ? 0 : dotProduct / magnitude;
    }

    public async getDocumentByHash(hash: string): Promise<DocumentInfo | null> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            const response = await this.client.scroll(this.documentsCollectionName, {
                filter: {
                    must: [
                        {
                            key: 'hash',
                            match: {
                                value: hash
                            }
                        }
                    ]
                },
                limit: 1,
                with_payload: true
            });

            if (response.points.length === 0) return null;

            const point = response.points[0];
            return this.mapPointToDocument(point);
        } catch (error) {
            this.logger.error('Помилка при пошуку документа за хешем:', error);
            throw error;
        }
    }

    public async getDocumentByName(filename: string): Promise<DocumentInfo | null> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            const response = await this.client.scroll(this.documentsCollectionName, {
                filter: {
                    must: [
                        {
                            key: 'filename',
                            match: {
                                value: filename
                            }
                        }
                    ]
                },
                limit: 1,
                with_payload: true
            });

            if (response.points.length === 0) return null;

            const point = response.points[0];
            return this.mapPointToDocument(point);
        } catch (error) {
            this.logger.error('Помилка при пошуку документа за іменем:', error);
            throw error;
        }
    }

    public async getDocumentById(id: string): Promise<DocumentInfo | null> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            const response = await this.client.retrieve(this.documentsCollectionName, {
                ids: [id],
                with_payload: true
            });

            if (response.length === 0) return null;

            const point = response[0];
            return this.mapPointToDocument(point);
        } catch (error) {
            this.logger.error('Помилка при пошуку документа за ID:', error);
            throw error;
        }
    }

    private async getDocumentsById(ids: string[]): Promise<DocumentInfo[]> {
        if (!this.client || ids.length === 0) return [];

        try {
            const response = await this.client.retrieve(this.documentsCollectionName, {
                ids,
                with_payload: true
            });

            return response.map(this.mapPointToDocument);
        } catch (error) {
            this.logger.error('Помилка при отриманні документів за ID:', error);
            return [];
        }
    }

    private mapPointToDocument(point: any): DocumentInfo {
        const payload = point.payload || {};
        return {
            id: point.id,
            filename: payload.filename,
            filepath: payload.filepath,
            size: payload.fileSize,
            modifiedTime: new Date(payload.modifiedTime),
            hash: payload.hash,
            type: payload.fileType as any,
            content: payload.content
        };
    }

    public async getAllDocuments(): Promise<DocumentInfo[]> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            const response = await this.client.scroll(this.documentsCollectionName, {
                limit: 100,  // Збільшимо ліміт для отримання більшої кількості документів
                with_payload: true,
                order_by: {
                    key: 'createdAt',
                    direction: 'desc'
                }
            });

            return response.points.map(this.mapPointToDocument);
        } catch (error) {
            this.logger.error('Помилка при отриманні всіх документів:', error);
            throw error;
        }
    }

    public async deleteDocument(documentId: string): Promise<void> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            // Видаляємо документ з колекції документів
            await this.client.delete(this.documentsCollectionName, {
                points: [documentId]
            });

            // Знаходимо та видаляємо всі чанки цього документа
            const chunksResponse = await this.client.scroll(this.chunksCollectionName, {
                filter: {
                    must: [
                        {
                            key: 'documentId',
                            match: {
                                value: documentId
                            }
                        }
                    ]
                },
                limit: 1000,
                with_payload: false
            });

            if (chunksResponse.points.length > 0) {
                const chunkIds = chunksResponse.points.map(p => p.id);
                await this.client.delete(this.chunksCollectionName, {
                    points: chunkIds
                });
            }

            this.logger.info(`Документ ${documentId} видалено`);
        } catch (error) {
            this.logger.error(`Помилка при видаленні документа ${documentId}:`, error);
            throw error;
        }
    }

    public async getDocumentsCount(): Promise<number> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            const response = await this.client.count(this.documentsCollectionName, {});
            return response.count;
        } catch (error) {
            this.logger.error('Помилка при підрахунку документів:', error);
            return 0;
        }
    }

    public async getVectorsCount(): Promise<number> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            const response = await this.client.count(this.chunksCollectionName, {});
            return response.count;
        } catch (error) {
            this.logger.error('Помилка при підрахунку векторів:', error);
            return 0;
        }
    }

    public async cleanupOldDocuments(daysOld: number = 30): Promise<void> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            // Визначення часової межі для старих документів (daysOld днів тому)
            const cutoffDate = new Date();
            cutoffDate.setDate(cutoffDate.getDate() - daysOld);
            const cutoffDateStr = cutoffDate.toISOString();
            
            // Знаходимо всі документи, створені раніше за часову межу
            const oldDocsResponse = await this.client.scroll(this.documentsCollectionName, {
                filter: {
                    must: [
                        {
                            key: 'createdAt',
                            range: {
                                lt: cutoffDateStr
                            }
                        }
                    ]
                },
                with_payload: true,
                limit: 1000
            });

            if (oldDocsResponse.points.length === 0) {
                this.logger.info('Немає застарілих документів для видалення');
                return;
            }

            // Для кожного документа перевіряємо, чи використовувався він нещодавно
            const sevenDaysAgo = new Date();
            sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
            const sevenDaysAgoStr = sevenDaysAgo.toISOString();
            
            const docsToDelete = [];
            
            for (const doc of oldDocsResponse.points) {
                // Перевіряємо, чи є у документа чанки, що використовувались за останній тиждень
                const recentChunksResponse = await this.client.scroll(this.chunksCollectionName, {
                    filter: {
                        must: [
                            {
                                key: 'documentId',
                                match: {
                                    value: doc.id
                                }
                            },
                            {
                                key: 'createdAt',
                                range: {
                                    gt: sevenDaysAgoStr
                                }
                            }
                        ]
                    },
                    limit: 1
                });
                
                // Якщо немає недавніх чанків, додаємо документ до списку на видалення
                if (recentChunksResponse.points.length === 0) {
                    docsToDelete.push(doc.id);
                }
            }
            
            // Видаляємо застарілі документи
            if (docsToDelete.length > 0) {
                await this.client.delete(this.documentsCollectionName, {
                    points: docsToDelete
                });
                
                // Видаляємо відповідні чанки для кожного документа
                for (const docId of docsToDelete) {
                    const chunksResponse = await this.client.scroll(this.chunksCollectionName, {
                        filter: {
                            must: [
                                {
                                    key: 'documentId',
                                    match: {
                                        value: docId
                                    }
                                }
                            ]
                        },
                        limit: 1000
                    });
                    
                    if (chunksResponse.points.length > 0) {
                        const chunkIds = chunksResponse.points.map(p => p.id);
                        await this.client.delete(this.chunksCollectionName, {
                            points: chunkIds
                        });
                    }
                }
                
                this.logger.info(`Видалено ${docsToDelete.length} застарілих документів`);
            } else {
                this.logger.info('Немає застарілих документів для видалення');
            }
            
        } catch (error) {
            this.logger.error('Помилка при очищенні застарілих документів:', error);
            throw error;
        }
    }

    public async getDocumentContext(documentIds: string[]): Promise<string> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            // Отримуємо метадані документів
            const documents = await this.getDocumentsById(documentIds);
            if (documents.length === 0) return '';
            
            const result = [];
            
            // Для кожного документа отримуємо його чанки
            for (const doc of documents) {
                const chunksResponse = await this.client.scroll(this.chunksCollectionName, {
                    filter: {
                        must: [
                            {
                                key: 'documentId',
                                match: {
                                    value: doc.id
                                }
                            }
                        ]
                    },
                    order_by: {
                        key: 'chunkIndex',
                        direction: 'asc'
                    },
                    with_payload: true,
                    limit: 1000
                });
                
                // Додаємо чанки до результату
                for (const chunk of chunksResponse.points) {
                    result.push(`[${doc.filename}] ${chunk.payload?.content}`);
                }
            }
            
            return result.join('\n\n');
        } catch (error) {
            this.logger.error('Помилка при отриманні контексту документів:', error);
            throw error;
        }
    }

    public async close(): Promise<void> {
        this.logger.info('Підключення до бази даних закрито');
        // Qdrant client не потребує явного закриття з'єднання
    }

    public async getDocuments({ page = 1, limit = 10, fileType = null }: { page: number; limit: number; fileType: string | null; }): Promise<{ documents: any[]; total: number; }> {
        if (!this.client) throw new Error('База даних не ініціалізована');

        try {
            const filter: any = {};
            
            // Додаємо умову фільтрації за типом файлу, якщо вказано
            if (fileType) {
                filter.must = [{
                    key: 'fileType',
                    match: {
                        value: fileType
                    }
                }];
            }
            
            // Рахуємо загальну кількість документів
            let totalCount = 0;
            
            const countResponse = await this.client.count(this.documentsCollectionName, {
                filter: Object.keys(filter).length > 0 ? filter : undefined
            });
            totalCount = countResponse.count;
            
            // Отримуємо документи з пагінацією
            const offset = (page - 1) * limit;
            
            const response = await this.client.scroll(this.documentsCollectionName, {
                filter: Object.keys(filter).length > 0 ? filter : undefined,
                limit,
                offset,
                with_payload: true,
                order_by: {
                    key: 'createdAt',
                    direction: 'desc'
                }
            });
            
            // Перетворюємо дані у потрібний формат
            const documents = response.points.map(this.mapPointToDocument);
            
            return {
                documents,
                total: totalCount
            };
            
        } catch (error) {
            this.logger.error('Помилка при отриманні документів з пагінацією:', error);
            throw error;
        }
    }
}
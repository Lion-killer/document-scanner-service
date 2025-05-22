import * as sql from 'mssql';
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
    private pool: sql.ConnectionPool | null = null;
    private embeddingService: string;

    constructor(config: ConfigManager, logger: Logger) {
        this.config = config;
        this.logger = logger;
        this.embeddingService = config.get('embedding.service', 'http://localhost:11434/api/embeddings');
    }

    public async initialize(): Promise<void> {
        try {
            // Підключення до MS SQL Server
            const dbConfig = this.config.get('database');
            this.pool = new sql.ConnectionPool({
                server: dbConfig.server,
                database: dbConfig.database,
                user: dbConfig.username,
                password: dbConfig.password,
                options: {
                    encrypt: dbConfig.encrypt || false,
                    trustServerCertificate: dbConfig.trustServerCertificate || true
                }
            });

            await this.pool.connect();
            this.logger.info('Підключено до бази даних');

            // Створення таблиць якщо їх немає
            await this.createTables();
            
        } catch (error) {
            this.logger.error('Помилка при ініціалізації бази даних:', error);
            throw error;
        }
    }

    private async createTables(): Promise<void> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        const createDocumentsTable = `
            IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='documents' AND xtype='U')
            CREATE TABLE documents (
                id NVARCHAR(50) PRIMARY KEY,
                filename NVARCHAR(255) NOT NULL,
                filepath NVARCHAR(500) NOT NULL,
                file_size BIGINT NOT NULL,
                modified_time DATETIME2 NOT NULL,
                hash_value NVARCHAR(32) NOT NULL,
                file_type NVARCHAR(10) NOT NULL,
                content NTEXT,
                created_at DATETIME2 DEFAULT GETDATE(),
                updated_at DATETIME2 DEFAULT GETDATE()
            )
        `;

        const createChunksTable = `
            IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='document_chunks' AND xtype='U')
            CREATE TABLE document_chunks (
                id NVARCHAR(50) PRIMARY KEY,
                document_id NVARCHAR(50) NOT NULL,
                chunk_index INT NOT NULL,
                content NTEXT NOT NULL,
                embedding NVARCHAR(MAX), -- JSON array of embeddings
                created_at DATETIME2 DEFAULT GETDATE(),
                FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
            )
        `;

        const createIndexes = `
            IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name='idx_documents_hash')
            CREATE INDEX idx_documents_hash ON documents(hash_value);
            
            IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name='idx_documents_filename')
            CREATE INDEX idx_documents_filename ON documents(filename);
            
            IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name='idx_chunks_document')
            CREATE INDEX idx_chunks_document ON document_chunks(document_id);
        `;

        try {
            await this.pool.request().query(createDocumentsTable);
            await this.pool.request().query(createChunksTable);
            await this.pool.request().query(createIndexes);
            this.logger.info('Таблиці бази даних створено/перевірено');
        } catch (error) {
            this.logger.error('Помилка при створенні таблиць:', error);
            throw error;
        }
    }

    public async addDocument(document: DocumentInfo, chunks: string[]): Promise<void> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        const transaction = new sql.Transaction(this.pool);
        
        try {
            await transaction.begin();

            // Додаємо документ
            const insertDocQuery = `
                INSERT INTO documents (id, filename, filepath, file_size, modified_time, hash_value, file_type, content)
                VALUES (@id, @filename, @filepath, @fileSize, @modifiedTime, @hashValue, @fileType, @content)
            `;

            const docRequest = new sql.Request(transaction);
            await docRequest
                .input('id', sql.NVarChar(50), document.id)
                .input('filename', sql.NVarChar(255), document.filename)
                .input('filepath', sql.NVarChar(500), document.filepath)
                .input('fileSize', sql.BigInt, document.size)
                .input('modifiedTime', sql.DateTime2, document.modifiedTime)
                .input('hashValue', sql.NVarChar(32), document.hash)
                .input('fileType', sql.NVarChar(10), document.type)
                .input('content', sql.NText, document.content)
                .query(insertDocQuery);

            // Додаємо чанки з ембедингами
            for (let i = 0; i < chunks.length; i++) {
                const chunkId = `${document.id}_chunk_${i}`;
                const embedding = await this.generateEmbedding(chunks[i]);

                const insertChunkQuery = `
                    INSERT INTO document_chunks (id, document_id, chunk_index, content, embedding)
                    VALUES (@id, @documentId, @chunkIndex, @content, @embedding)
                `;

                const chunkRequest = new sql.Request(transaction);
                await chunkRequest
                    .input('id', sql.NVarChar(50), chunkId)
                    .input('documentId', sql.NVarChar(50), document.id)
                    .input('chunkIndex', sql.Int, i)
                    .input('content', sql.NText, chunks[i])
                    .input('embedding', sql.NVarChar(sql.MAX), JSON.stringify(embedding))
                    .query(insertChunkQuery);
            }

            await transaction.commit();
            this.logger.debug(`Документ ${document.filename} додано до бази з ${chunks.length} чанками`);

        } catch (error) {
            await transaction.rollback();
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
            return Array.from({ length: 384 }, () => Math.random() - 0.5);
        }
    }

    public async searchSimilar(query: string, limit: number = 10): Promise<SearchResult[]> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        try {
            // Генеруємо ембединг для запиту
            const queryEmbedding = await this.generateEmbedding(query);

            // Отримуємо всі чанки (в реальному застосунку слід використовувати векторний індекс)
            const getAllChunksQuery = `
                SELECT 
                    dc.id,
                    dc.document_id,
                    dc.chunk_index,
                    dc.content,
                    dc.embedding,
                    d.filename
                FROM document_chunks dc
                JOIN documents d ON dc.document_id = d.id
            `;

            const result = await this.pool.request().query(getAllChunksQuery);
            
            // Обчислюємо косинусну подібність
            const similarities = result.recordset.map(row => {
                const embedding = JSON.parse(row.embedding);
                const similarity = this.cosineSimilarity(queryEmbedding, embedding);
                
                return {
                    documentId: row.document_id,
                    filename: row.filename,
                    content: row.content,
                    similarity: similarity,
                    chunkIndex: row.chunk_index
                };
            });

            // Сортуємо за подібністю та повертаємо топ результатів
            return similarities
                .sort((a, b) => b.similarity - a.similarity)
                .slice(0, limit);

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
        if (!this.pool) throw new Error('База даних не ініціалізована');

        try {
            const query = 'SELECT * FROM documents WHERE hash_value = @hash';
            const result = await this.pool.request()
                .input('hash', sql.NVarChar(32), hash)
                .query(query);

            if (result.recordset.length === 0) return null;

            const row = result.recordset[0];
            return {
                id: row.id,
                filename: row.filename,
                filepath: row.filepath,
                size: row.file_size,
                modifiedTime: row.modified_time,
                hash: row.hash_value,
                type: row.file_type,
                content: row.content
            };
        } catch (error) {
            this.logger.error('Помилка при пошуку документа за хешем:', error);
            throw error;
        }
    }

    public async getDocumentByName(filename: string): Promise<DocumentInfo | null> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        try {
            const query = 'SELECT * FROM documents WHERE filename = @filename';
            const result = await this.pool.request()
                .input('filename', sql.NVarChar(255), filename)
                .query(query);

            if (result.recordset.length === 0) return null;

            const row = result.recordset[0];
            return {
                id: row.id,
                filename: row.filename,
                filepath: row.filepath,
                size: row.file_size,
                modifiedTime: row.modified_time,
                hash: row.hash_value,
                type: row.file_type,
                content: row.content
            };
        } catch (error) {
            this.logger.error('Помилка при пошуку документа за іменем:', error);
            throw error;
        }
    }

    public async getDocumentById(id: string): Promise<DocumentInfo | null> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        try {
            const query = 'SELECT * FROM documents WHERE id = @id';
            const result = await this.pool.request()
                .input('id', sql.NVarChar(50), id)
                .query(query);

            if (result.recordset.length === 0) return null;

            const row = result.recordset[0];
            return {
                id: row.id,
                filename: row.filename,
                filepath: row.filepath,
                size: row.file_size,
                modifiedTime: row.modified_time,
                hash: row.hash_value,
                type: row.file_type,
                content: row.content
            };
        } catch (error) {
            this.logger.error('Помилка при пошуку документа за ID:', error);
            throw error;
        }
    }

    public async getAllDocuments(): Promise<DocumentInfo[]> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        try {
            const query = 'SELECT * FROM documents ORDER BY created_at DESC';
            const result = await this.pool.request().query(query);

            return result.recordset.map(row => ({
                id: row.id,
                filename: row.filename,
                filepath: row.filepath,
                size: row.file_size,
                modifiedTime: row.modified_time,
                hash: row.hash_value,
                type: row.file_type,
                content: row.content
            }));
        } catch (error) {
            this.logger.error('Помилка при отриманні всіх документів:', error);
            throw error;
        }
    }

    public async deleteDocument(documentId: string): Promise<void> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        try {
            // Видаляємо документ (чанки видаляться автоматично через CASCADE)
            const query = 'DELETE FROM documents WHERE id = @id';
            await this.pool.request()
                .input('id', sql.NVarChar(50), documentId)
                .query(query);

            this.logger.info(`Документ ${documentId} видалено`);
        } catch (error) {
            this.logger.error(`Помилка при видаленні документа ${documentId}:`, error);
            throw error;
        }
    }

    public async getDocumentsCount(): Promise<number> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        try {
            const result = await this.pool.request().query('SELECT COUNT(*) as count FROM documents');
            return result.recordset[0].count;
        } catch (error) {
            this.logger.error('Помилка при підрахунку документів:', error);
            return 0;
        }
    }

    public async getVectorsCount(): Promise<number> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        try {
            const result = await this.pool.request().query('SELECT COUNT(*) as count FROM document_chunks');
            return result.recordset[0].count;
        } catch (error) {
            this.logger.error('Помилка при підрахунку векторів:', error);
            return 0;
        }
    }

    public async cleanupOldDocuments(daysOld: number = 30): Promise<void> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        try {
            const query = `
                DELETE FROM documents 
                WHERE created_at < DATEADD(day, -@daysOld, GETDATE())
                AND id NOT IN (
                    SELECT DISTINCT document_id 
                    FROM document_chunks 
                    WHERE created_at > DATEADD(day, -7, GETDATE())
                )
            `;

            const result = await this.pool.request()
                .input('daysOld', sql.Int, daysOld)
                .query(query);

            this.logger.info(`Видалено ${result.rowsAffected?.[0] || 0} застарілих документів`);
        } catch (error) {
            this.logger.error('Помилка при очищенні застарілих документів:', error);
            throw error;
        }
    }

    public async getDocumentContext(documentIds: string[]): Promise<string> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        try {
            const placeholders = documentIds.map((_, index) => `@id${index}`).join(',');
            const query = `
                SELECT d.filename, dc.content, dc.chunk_index
                FROM documents d
                JOIN document_chunks dc ON d.id = dc.document_id
                WHERE d.id IN (${placeholders})
                ORDER BY d.filename, dc.chunk_index
            `;

            const request = this.pool.request();
            documentIds.forEach((id, index) => {
                request.input(`id${index}`, sql.NVarChar(50), id);
            });

            const result = await request.query(query);
            
            return result.recordset
                .map(row => `[${row.filename}] ${row.content}`)
                .join('\n\n');

        } catch (error) {
            this.logger.error('Помилка при отриманні контексту документів:', error);
            throw error;
        }
    }

    public async close(): Promise<void> {
        if (this.pool) {
            await this.pool.close();
            this.logger.info('Підключення до бази даних закрито');
        }
    }

    public async getDocuments({ page = 1, limit = 10, fileType = null }: { page: number; limit: number; fileType: string | null; }): Promise<{ documents: any[]; total: number; }> {
        if (!this.pool) throw new Error('База даних не ініціалізована');

        try {
            // Базовий запит
            let countQuery = 'SELECT COUNT(*) as total FROM documents';
            let query = 'SELECT * FROM documents';
            
            // Додаємо умову фільтрації за типом файлу, якщо вказано
            const params: any = {};
            if (fileType) {
                countQuery += ' WHERE file_type = @fileType';
                query += ' WHERE file_type = @fileType';
                params.fileType = fileType;
            }
            
            // Додаємо сортування і пагінацію
            query += ' ORDER BY created_at DESC OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY';
            
            // Розраховуємо зміщення для пагінації
            const offset = (page - 1) * limit;
            params.offset = offset;
            params.limit = limit;
            
            // Виконуємо запит на кількість документів
            const countRequest = this.pool.request();
            if (fileType) {
                countRequest.input('fileType', sql.NVarChar, fileType);
            }
            const totalResult = await countRequest.query(countQuery);
            const total = totalResult.recordset[0].total;
            
            // Виконуємо основний запит
            const request = this.pool.request()
                .input('offset', sql.Int, offset)
                .input('limit', sql.Int, limit);
            
            if (fileType) {
                request.input('fileType', sql.NVarChar, fileType);
            }
            
            const result = await request.query(query);
            
            const documents = result.recordset.map(row => ({
                id: row.id,
                filename: row.filename,
                filepath: row.filepath,
                file_size: row.file_size,
                modified_time: row.modified_time,
                hash_value: row.hash_value,
                file_type: row.file_type,
                created_at: row.created_at
            }));
            
            return {
                documents,
                total
            };
        } catch (error) {
            this.logger.error('Помилка при отриманні документів з пагінацією:', error);
            throw error;
        }
    }
}
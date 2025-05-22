import * as fs from 'fs/promises';
import * as path from 'path';
import { createHash } from 'crypto';
import * as mammoth from 'mammoth';
import pdf from 'pdf-parse';
import { exec } from 'child_process';
import { promisify } from 'util';
import { ConfigManager } from '../config/ConfigManager';
import { Logger } from '../utils/Logger';
import { VectorDatabase } from './VectorDatabase';

const execAsync = promisify(exec);

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

export class DocumentScanner {
    private config: ConfigManager;
    private logger: Logger;
    private vectorDb: VectorDatabase;
    private lastScanTime: Date | null = null;
    private scanningInProgress: boolean = false;
    private supportedExtensions = ['.pdf', '.doc', '.docx'];

    constructor(config: ConfigManager, logger: Logger, vectorDb: VectorDatabase) {
        this.config = config;
        this.logger = logger;
        this.vectorDb = vectorDb;
    }

    public async scanDocuments(): Promise<{processed: number, skipped: number, errors: number}> {
        if (this.scanningInProgress) {
            this.logger.warn('Сканування вже виконується, пропускаємо новий запит');
            return { processed: 0, skipped: 0, errors: 0 };
        }
        
        const smbPath = this.config.get('smb.path');
        const stats = { processed: 0, skipped: 0, errors: 0 };

        try {
            this.scanningInProgress = true;
            this.logger.info(`Початок сканування папки: ${smbPath}`);
            
            // Монтування SMB папки якщо потрібно
            await this.ensureSMBMounted();
            
            // Отримання списку файлів
            const files = await this.getDocumentFiles(smbPath);
            this.logger.info(`Знайдено ${files.length} документів для обробки`);

            // Обробка кожного файлу
            for (const file of files) {
                try {
                    const shouldProcess = await this.shouldProcessFile(file);
                    if (!shouldProcess) {
                        stats.skipped++;
                        continue;
                    }

                    await this.processDocument(file);
                    stats.processed++;
                    
                    this.logger.info(`Оброблено: ${file.filename}`);
                } catch (error) {
                    stats.errors++;
                    this.logger.error(`Помилка при обробці ${file.filename}:`, error);
                }
            }

            this.lastScanTime = new Date();
            this.logger.info(`Сканування завершено. Оброблено: ${stats.processed}, Пропущено: ${stats.skipped}, Помилок: ${stats.errors}`);
            
            return stats;
        } catch (error) {
            this.logger.error('Помилка при скануванні документів:', error);
            throw error;
        } finally {
            this.scanningInProgress = false;
        }
    }

    private async ensureSMBMounted(): Promise<void> {
        const smbConfig = this.config.get('smb');
        const mountPoint = smbConfig.mountPoint || '/mnt/smb_docs';
        
        try {
            // Перевірка чи змонтовано
            await fs.access(mountPoint);
            
            // Перевірка чи є файли (тест на доступність)
            const files = await fs.readdir(mountPoint);
            if (files.length === 0) {
                this.logger.warn('SMB папка здається пустою, перевірте підключення');
            }
        } catch (error) {
            // Спроба монтування
            this.logger.info('Монтування SMB папки...');
            
            const mountCommand = `sudo mount -t cifs ${smbConfig.server}${smbConfig.share} ${mountPoint} -o username=${smbConfig.username},password=${smbConfig.password},uid=$(id -u),gid=$(id -g)`;
            
            try {
                await execAsync(mountCommand);
                this.logger.info('SMB папка успішно змонтована');
            } catch (mountError) {
                this.logger.error('Не вдалося змонтувати SMB папку:', mountError);
                throw new Error('Не вдалося отримати доступ до SMB папки');
            }
        }
    }

    private async getDocumentFiles(dirPath: string): Promise<DocumentInfo[]> {
        const documents: DocumentInfo[] = [];
        
        const scanDirectory = async (currentPath: string): Promise<void> => {
            try {
                const entries = await fs.readdir(currentPath, { withFileTypes: true });
                
                for (const entry of entries) {
                    const fullPath = path.join(currentPath, entry.name);
                    
                    if (entry.isDirectory()) {
                        // Рекурсивний пошук у підпапках
                        await scanDirectory(fullPath);
                    } else if (entry.isFile()) {
                        const ext = path.extname(entry.name).toLowerCase();
                        
                        if (this.supportedExtensions.includes(ext)) {
                            try {
                                const stats = await fs.stat(fullPath);
                                const fileBuffer = await fs.readFile(fullPath);
                                const hash = createHash('md5').update(fileBuffer).digest('hex');
                                
                                documents.push({
                                    id: hash,
                                    filename: entry.name,
                                    filepath: fullPath,
                                    size: stats.size,
                                    modifiedTime: stats.mtime,
                                    hash: hash,
                                    type: ext.substring(1) as 'pdf' | 'doc' | 'docx'
                                });
                            } catch (error) {
                                this.logger.warn(`Не вдалося обробити файл ${fullPath}:`, error);
                            }
                        }
                    }
                }
            } catch (error) {
                this.logger.error(`Помилка при скануванні директорії ${currentPath}:`, error);
            }
        };

        await scanDirectory(dirPath);
        return documents;
    }

    private async shouldProcessFile(document: DocumentInfo): Promise<boolean> {
        try {
            // Перевірка чи файл вже існує в базі з тим же хешем
            const existingDoc = await this.vectorDb.getDocumentByHash(document.hash);
            
            if (existingDoc) {
                // Файл не змінився
                return false;
            }

            // Перевірка за іменем файлу (можливо файл змінився)
            const existingByName = await this.vectorDb.getDocumentByName(document.filename);
            if (existingByName && existingByName.hash !== document.hash) {
                // Файл змінився - видаляємо стару версію
                await this.vectorDb.deleteDocument(existingByName.id);
                this.logger.info(`Файл ${document.filename} змінився, оновлюємо`);
            }

            return true;
        } catch (error) {
            this.logger.error(`Помилка при перевірці файлу ${document.filename}:`, error);
            return true; // У разі помилки все одно обробляємо
        }
    }

    private async processDocument(document: DocumentInfo): Promise<void> {
        try {
            // Витягування тексту з документа
            document.content = await this.extractTextFromDocument(document);
            
            if (!document.content || document.content.trim().length === 0) {
                this.logger.warn(`Не вдалося витягти текст з ${document.filename}`);
                return;
            }

            // Розділення тексту на чанки
            const chunks = this.splitTextIntoChunks(document.content, 1000, 200);
            
            // Збереження в векторну базу
            await this.vectorDb.addDocument(document, chunks);
            
            this.logger.debug(`Додано ${chunks.length} чанків для документа ${document.filename}`);
        } catch (error) {
            this.logger.error(`Помилка при обробці документа ${document.filename}:`, error);
            throw error;
        }
    }

    private async extractTextFromDocument(document: DocumentInfo): Promise<string> {
        const buffer = await fs.readFile(document.filepath);
        
        switch (document.type) {
            case 'pdf':
                return await this.extractFromPDF(buffer);
            case 'docx':
                return await this.extractFromDocx(buffer);
            case 'doc':
                return await this.extractFromDoc(document.filepath);
            default:
                throw new Error(`Непідтримуваний тип файлу: ${document.type}`);
        }
    }

    private async extractFromPDF(buffer: Buffer): Promise<string> {
        try {
            const data = await pdf(buffer);
            return data.text;
        } catch (error) {
            this.logger.error('Помилка при читанні PDF:', error);
            throw error;
        }
    }

    private async extractFromDocx(buffer: Buffer): Promise<string> {
        try {
            const result = await mammoth.extractRawText({ buffer });
            return result.value;
        } catch (error) {
            this.logger.error('Помилка при читанні DOCX:', error);
            throw error;
        }
    }

    private async extractFromDoc(filepath: string): Promise<string> {
        try {
            // Використовуємо antiword для .doc файлів
            const { stdout } = await execAsync(`antiword "${filepath}"`);
            return stdout;
        } catch (error) {
            this.logger.error('Помилка при читанні DOC (потрібен antiword):', error);
            
            // Альтернативний спосіб через LibreOffice
            try {
                const { stdout } = await execAsync(`libreoffice --headless --convert-to txt --outdir /tmp "${filepath}" && cat "/tmp/${path.basename(filepath, '.doc')}.txt"`);
                return stdout;
            } catch (libreError) {
                this.logger.error('Помилка при читанні DOC через LibreOffice:', libreError);
                throw new Error('Не вдалося прочитати .doc файл. Встановіть antiword або LibreOffice');
            }
        }
    }

    private splitTextIntoChunks(text: string, chunkSize: number = 1000, overlap: number = 200): string[] {
        const chunks: string[] = [];
        const sentences = text.split(/[.!?]+/).filter(s => s.trim().length > 0);
        
        let currentChunk = '';
        let currentSize = 0;
        
        for (const sentence of sentences) {
            const sentenceLength = sentence.trim().length;
            
            if (currentSize + sentenceLength > chunkSize && currentChunk.length > 0) {
                chunks.push(currentChunk.trim());
                
                // Створюємо перекриття
                const words = currentChunk.split(' ');
                const overlapWords = words.slice(-Math.floor(overlap / 5)); // Приблизно overlap символів
                currentChunk = overlapWords.join(' ') + ' ' + sentence.trim();
                currentSize = currentChunk.length;
            } else {
                currentChunk += (currentChunk ? ' ' : '') + sentence.trim();
                currentSize = currentChunk.length;
            }
        }
        
        if (currentChunk.trim().length > 0) {
            chunks.push(currentChunk.trim());
        }
        
        return chunks;
    }

    public getLastScanTime(): Date | null {
        return this.lastScanTime;
    }

    public isScanInProgress(): boolean {
        return this.scanningInProgress;
    }
}
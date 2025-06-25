import express from 'express';
import cron from 'node-cron';
import { DocumentScanner } from './services/DocumentScanner';
import { VectorDatabase } from './services/VectorDatabase';
import { OpenWebUIIntegration } from './services/OpenWebUIIntegration';
import { ConfigManager } from './config/ConfigManager';
import { Logger } from './utils/Logger';

// Функція для форматування розміру файлу
function formatFileSize(bytes: number): string {
    if (bytes === 0) return '0 Bytes';
    
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

class DocumentScannerApp {
    private app: express.Application;
    private scanner: DocumentScanner;
    private vectorDb: VectorDatabase;
    private openWebUI: OpenWebUIIntegration;
    private config: ConfigManager;
    private logger: Logger;

    constructor() {
        this.app = express();
        this.logger = new Logger();
        this.config = new ConfigManager(this.logger);
        this.vectorDb = new VectorDatabase(this.config, this.logger);
        this.scanner = new DocumentScanner(this.config, this.logger, this.vectorDb);
        this.openWebUI = new OpenWebUIIntegration(this.config, this.logger, this.vectorDb);
        
        this.setupMiddleware();
        this.setupRoutes();
        this.setupScheduler();
    }

    private setupMiddleware(): void {
        this.app.use(express.json());
        this.app.use(express.static('public'));
        
        // CORS для OpenWebUI
        this.app.use((req, res, next) => {
            res.header('Access-Control-Allow-Origin', '*');
            res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
            res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
            next();
        });
    }

    private setupRoutes(): void {
        // Основні маршрути API
        this.app.get('/api/status', (req, res) => {
            return res.json({
                status: 'active',
                lastScan: this.scanner.getLastScanTime(),
                documentsCount: this.vectorDb.getDocumentsCount(),
                vectorsCount: this.vectorDb.getVectorsCount(),
                scanInProgress: this.scanner.isScanInProgress()
            });
        });

        this.app.post('/api/scan/manual', async (req, res) => {
            try {
                this.logger.info('Запуск ручного сканування');
                const result = await this.scanner.scanDocuments();
                return res.json({ success: true, result });
            } catch (error: any) {
                this.logger.error('Помилка при ручному скануванні:', error);
                return res.status(500).json({ success: false, error: error.message });
            }
        });

        this.app.get('/api/documents', async (req, res) => {
            try {
                const page = parseInt(req.query.page as string) || 1;
                const limit = parseInt(req.query.limit as string) || 10;
                const type = req.query.type as string || null;
                
                const result = await this.vectorDb.getDocuments({
                    page,
                    limit,
                    fileType: type
                });
                
                return res.json({
                    documents: result.documents,
                    total: result.total,
                    page,
                    limit
                });
            } catch (error: any) {
                this.logger.error('Помилка при отриманні документів:', error);
                return res.status(500).json({ error: error.message });
            }
        });

        this.app.post('/api/search', async (req, res) => {
            try {
                const { query, limit = 10 } = req.body;
                const results = await this.vectorDb.searchSimilar(query, limit);
                return res.json(results);
            } catch (error: any) {
                this.logger.error('Помилка при пошуку:', error);
                return res.status(500).json({ error: error.message });
            }
        });

        this.app.get('/api/documents/:id', async (req, res) => {
            try {
                const { id } = req.params;
                const document = await this.vectorDb.getDocumentById(id);
                
                if (!document) {
                    return res.status(404).json({ error: 'Документ не знайдено' });
                }
                
                return res.json(document);
            } catch (error: any) {
                this.logger.error('Помилка при отриманні документа:', error);
                return res.status(500).json({ error: error.message });
            }
        });
        
        this.app.get('/api/documents/:id/preview', async (req, res) => {
            try {
                const { id } = req.params;
                const document = await this.vectorDb.getDocumentById(id);
                
                if (!document) {
                    return res.status(404).json({ error: 'Документ не знайдено' });
                }
                
                // Створюємо простий HTML документ для попереднього перегляду
                const htmlContent = `
                <!DOCTYPE html>
                <html lang="uk">
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <title>Перегляд документу: ${document.filename}</title>
                    <style>
                        body {
                            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                            margin: 0;
                            padding: 20px;
                            line-height: 1.6;
                            color: #333;
                            background-color: #f5f5f5;
                        }
                        .preview-container {
                            max-width: 800px;
                            margin: 0 auto;
                            border: 1px solid #ddd;
                            padding: 30px;
                            border-radius: 8px;
                            background-color: white;
                            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
                        }
                        .preview-header {
                            padding-bottom: 15px;
                            margin-bottom: 20px;
                            border-bottom: 1px solid #eee;
                        }
                        .preview-header h1 {
                            color: #2c3e50;
                            margin-top: 0;
                            font-size: 24px;
                        }
                        .preview-content {
                            white-space: pre-wrap;
                            overflow-wrap: break-word;
                            background-color: #f9f9f9;
                            padding: 15px;
                            border-radius: 5px;
                            border: 1px solid #e0e0e0;
                            font-family: monospace;
                        }
                        .meta-info {
                            margin-bottom: 5px;
                            color: #666;
                        }
                    </style>
                </head>
                <body>
                    <div class="preview-container">
                        <div class="preview-header">
                            <h1>${document.filename}</h1>
                            <p class="meta-info"><strong>Тип:</strong> ${document.type}</p>
                            <p class="meta-info"><strong>Розмір:</strong> ${formatFileSize(document.size)}</p>
                            <p class="meta-info"><strong>Дата модифікації:</strong> ${new Date(document.modifiedTime).toLocaleString()}</p>
                        </div>
                        <div class="preview-content">
                            ${document.content || 'Вміст документу недоступний'}
                        </div>
                    </div>
                </body>
                </html>
                `;
                
                res.setHeader('Content-Type', 'text/html');
                return res.send(htmlContent);
                
            } catch (error: any) {
                this.logger.error('Помилка при отриманні документа для перегляду:', error);
                return res.status(500).json({ error: error.message });
            }
        });
        
        this.app.delete('/api/documents/:id', async (req, res) => {
            try {
                const { id } = req.params;
                await this.vectorDb.deleteDocument(id);
                return res.json({ success: true });
            } catch (error: any) {
                this.logger.error('Помилка при видаленні документа:', error);
                return res.status(500).json({ error: error.message });
            }
        });

        // Інтеграція з OpenWebUI
        this.app.post('/api/openwebui/query', async (req, res) => {
            try {
                const { message, context } = req.body;
                const response = await this.openWebUI.processQuery(message, context);
                return res.json(response);
            } catch (error: any) {
                this.logger.error('Помилка при обробці запиту OpenWebUI:', error);
                return res.status(500).json({ error: error.message });
            }
        });
    }

    private setupScheduler(): void {
        // Автоматичне сканування кожні 30 хвилин
        cron.schedule('*/30 * * * *', async () => {
            try {
                this.logger.info('Запуск планового сканування');
                await this.scanner.scanDocuments();
            } catch (error: any) {
                this.logger.error('Помилка при плановому скануванні:', error);
            }
        });

        // Очищення векторної бази від застарілих документів щодня о 02:00
        cron.schedule('0 2 * * *', async () => {
            try {
                this.logger.info('Запуск очищення векторної бази');
                await this.vectorDb.cleanupOldDocuments();
            } catch (error: any) {
                this.logger.error('Помилка при очищенні:', error);
            }
        });
    }

    public async start(): Promise<void> {
        try {
            // Ініціалізація компонентів
            await this.vectorDb.initialize();
            await this.openWebUI.initialize();
            
            // Запуск першого сканування
            await this.scanner.scanDocuments();
            
            const port = this.config.get('server.port', 3000);
            this.app.listen(port, () => {
                this.logger.info(`Сервер запущено на порту ${port}`);
                this.logger.info('Додаток готовий до роботи');
            });
        } catch (error: any) {
            this.logger.error('Помилка при запуску додатку:', error);
            process.exit(1);
        }
    }

    public async stop(): Promise<void> {
        this.logger.info('Зупинка додатку...');
        await this.vectorDb.close();
        await this.openWebUI.close();
    }
}

// Запуск додатку
const app = new DocumentScannerApp();

// Обробка сигналів зупинки
process.on('SIGINT', async () => {
    console.log('\nОтримано сигнал SIGINT. Зупинка додатку...');
    await app.stop();
    process.exit(0);
});

process.on('SIGTERM', async () => {
    console.log('\nОтримано сигнал SIGTERM. Зупинка додатку...');
    await app.stop();
    process.exit(0);
});

// Запуск
app.start().catch(error => {
    console.error('Критична помилка при запуску:', error);
    process.exit(1);
});

export { DocumentScannerApp };
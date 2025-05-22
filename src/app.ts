import express from 'express';
import cron from 'node-cron';
import { DocumentScanner } from './services/DocumentScanner';
import { VectorDatabase } from './services/VectorDatabase';
import { OpenWebUIIntegration } from './services/OpenWebUIIntegration';
import { ConfigManager } from './config/ConfigManager';
import { Logger } from './utils/Logger';

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
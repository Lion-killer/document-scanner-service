import * as fs from 'fs';
import * as path from 'path';

enum LogLevel {
    ERROR = 0,
    WARN = 1,
    INFO = 2,
    DEBUG = 3
}

interface LogEntry {
    timestamp: string;
    level: string;
    message: string;
    data?: any;
}

export class Logger {
    private logLevel: LogLevel;
    private logFile: string | null;
    private logToConsole: boolean;

    constructor(level: string = 'info', logFile?: string, logToConsole: boolean = true) {
        this.logLevel = this.parseLogLevel(level);
        this.logFile = logFile || null;
        this.logToConsole = logToConsole;

        // Створюємо директорію для логів якщо потрібно
        if (this.logFile) {
            const logDir = path.dirname(this.logFile);
            if (!fs.existsSync(logDir)) {
                fs.mkdirSync(logDir, { recursive: true });
            }
        }
    }

    private parseLogLevel(level: string): LogLevel {
        switch (level.toLowerCase()) {
            case 'error': return LogLevel.ERROR;
            case 'warn': return LogLevel.WARN;
            case 'info': return LogLevel.INFO;
            case 'debug': return LogLevel.DEBUG;
            default: return LogLevel.INFO;
        }
    }

    private formatMessage(level: string, message: string, data?: any): string {
        const timestamp = new Date().toISOString();
        const logEntry: LogEntry = {
            timestamp,
            level: level.toUpperCase(),
            message,
            data
        };

        if (data !== undefined) {
            return `[${timestamp}] ${level.toUpperCase()}: ${message} ${JSON.stringify(data)}`;
        }
        return `[${timestamp}] ${level.toUpperCase()}: ${message}`;
    }

    private writeLog(level: string, message: string, data?: any): void {
        const formattedMessage = this.formatMessage(level, message, data);

        // Вивід у консоль
        if (this.logToConsole) {
            switch (level.toLowerCase()) {
                case 'error':
                    console.error(formattedMessage);
                    break;
                case 'warn':
                    console.warn(formattedMessage);
                    break;
                case 'debug':
                    console.debug(formattedMessage);
                    break;
                default:
                    console.log(formattedMessage);
            }
        }

        // Запис у файл
        if (this.logFile) {
            try {
                fs.appendFileSync(this.logFile, formattedMessage + '\n');
            } catch (error) {
                console.error('Помилка при записі в лог файл:', error);
            }
        }
    }

    public error(message: string, data?: any): void {
        if (this.logLevel >= LogLevel.ERROR) {
            this.writeLog('error', message, data);
        }
    }

    public warn(message: string, data?: any): void {
        if (this.logLevel >= LogLevel.WARN) {
            this.writeLog('warn', message, data);
        }
    }

    public info(message: string, data?: any): void {
        if (this.logLevel >= LogLevel.INFO) {
            this.writeLog('info', message, data);
        }
    }

    public debug(message: string, data?: any): void {
        if (this.logLevel >= LogLevel.DEBUG) {
            this.writeLog('debug', message, data);
        }
    }

    public setLevel(level: string): void {
        this.logLevel = this.parseLogLevel(level);
        this.info(`Рівень логування змінено на: ${level.toUpperCase()}`);
    }

    public rotateLogs(maxSize: number = 10 * 1024 * 1024): void { // 10MB за замовчуванням
        if (!this.logFile || !fs.existsSync(this.logFile)) {
            return;
        }

        try {
            const stats = fs.statSync(this.logFile);
            if (stats.size > maxSize) {
                const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
                const backupFile = `${this.logFile}.${timestamp}`;
                
                fs.renameSync(this.logFile, backupFile);
                this.info(`Лог файл перенесено до: ${backupFile}`);
                
                // Очищення старих бекапів (залишаємо останні 5)
                this.cleanupOldLogs();
            }
        } catch (error) {
            this.error('Помилка при ротації логів:', error);
        }
    }

    private cleanupOldLogs(): void {
        if (!this.logFile) return;

        try {
            const logDir = path.dirname(this.logFile);
            const logBaseName = path.basename(this.logFile);
            
            const files = fs.readdirSync(logDir)
                .filter(file => file.startsWith(logBaseName) && file !== logBaseName)
                .map(file => ({
                    name: file,
                    path: path.join(logDir, file),
                    stats: fs.statSync(path.join(logDir, file))
                }))
                .sort((a, b) => b.stats.mtime.getTime() - a.stats.mtime.getTime());

            // Видаляємо всі файли крім останніх 5
            files.slice(5).forEach(file => {
                fs.unlinkSync(file.path);
                this.debug(`Видалено старий лог файл: ${file.name}`);
            });

        } catch (error) {
            this.error('Помилка при очищенні старих логів:', error);
        }
    }

    public getLogs(lines: number = 100): string[] {
        if (!this.logFile || !fs.existsSync(this.logFile)) {
            return [];
        }

        try {
            const content = fs.readFileSync(this.logFile, 'utf8');
            const allLines = content.split('\n').filter(line => line.trim());
            
            return allLines.slice(-lines);
        } catch (error) {
            this.error('Помилка при читанні логів:', error);
            return [];
        }
    }

    public searchLogs(query: string, maxResults: number = 50): string[] {
        if (!this.logFile || !fs.existsSync(this.logFile)) {
            return [];
        }

        try {
            const content = fs.readFileSync(this.logFile, 'utf8');
            const allLines = content.split('\n');
            
            const matches = allLines
                .filter(line => line.toLowerCase().includes(query.toLowerCase()))
                .slice(-maxResults);
                
            return matches;
        } catch (error) {
            this.error('Помилка при пошуку в логах:', error);
            return [];
        }
    }

    public getLogStats(): {
        totalLines: number;
        errors: number;
        warnings: number;
        fileSize: number;
        lastModified: Date | null;
    } {
        const stats = {
            totalLines: 0,
            errors: 0,
            warnings: 0,
            fileSize: 0,
            lastModified: null as Date | null
        };

        if (!this.logFile || !fs.existsSync(this.logFile)) {
            return stats;
        }

        try {
            const fileStats = fs.statSync(this.logFile);
            const content = fs.readFileSync(this.logFile, 'utf8');
            const lines = content.split('\n').filter(line => line.trim());

            stats.totalLines = lines.length;
            stats.fileSize = fileStats.size;
            stats.lastModified = fileStats.mtime;
            
            stats.errors = lines.filter(line => line.includes('ERROR')).length;
            stats.warnings = lines.filter(line => line.includes('WARN')).length;

        } catch (error) {
            this.error('Помилка при отриманні статистики логів:', error);
        }

        return stats;
    }

    public createPerformanceTimer(name: string): () => void {
        const startTime = Date.now();
        this.debug(`Початок таймера: ${name}`);
        
        return () => {
            const endTime = Date.now();
            const duration = endTime - startTime;
            this.info(`Таймер ${name}: ${duration}ms`);
        };
    }

    public logMemoryUsage(): void {
        const usage = process.memoryUsage();
        const formatBytes = (bytes: number) => {
            return (bytes / 1024 / 1024).toFixed(2) + ' MB';
        };

        this.info('Використання пам\'яті:', {
            rss: formatBytes(usage.rss),
            heapTotal: formatBytes(usage.heapTotal),
            heapUsed: formatBytes(usage.heapUsed),
            external: formatBytes(usage.external)
        });
    }

    public async logAsyncOperation<T>(
        operationName: string,
        operation: () => Promise<T>
    ): Promise<T> {
        const timer = this.createPerformanceTimer(operationName);
        
        try {
            this.debug(`Початок операції: ${operationName}`);
            const result = await operation();
            this.debug(`Операція завершена успішно: ${operationName}`);
            return result;
        } catch (error) {
            this.error(`Помилка в операції ${operationName}:`, error);
            throw error;
        } finally {
            timer();
        }
    }
}
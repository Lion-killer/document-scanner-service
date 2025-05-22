import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';

dotenv.config();

interface DatabaseConfig {
    server: string;
    database: string;
    username: string;
    password: string;
    encrypt?: boolean;
    trustServerCertificate?: boolean;
}

interface SMBConfig {
    server: string;
    share: string;
    username: string;
    password: string;
    path: string;
    mountPoint?: string;
}

interface EmbeddingConfig {
    service: string;
    model: string;
}

interface LLMConfig {
    model: string;
    temperature: number;
    max_tokens: number;
}

interface ServerConfig {
    port: number;
    host: string;
}

interface AppConfig {
    database: DatabaseConfig;
    smb: SMBConfig;
    embedding: EmbeddingConfig;
    llm: LLMConfig;
    server: ServerConfig;
    ollama: {
        url: string;
    };
    openwebui: {
        url: string;
    };
    logging: {
        level: string;
        file: string;
    };
}

export class ConfigManager {
    private config: Partial<AppConfig>;
    private logger: any;

    constructor(logger?: any) {
        this.config = {};
        this.logger = logger || console;
        if (this.logger.info) {
            this.logger.info(`Ініціалізація ConfigManager (тільки .env)`);
        } else {
            this.logger.log(`Ініціалізація ConfigManager (тільки .env)`);
        }
        this.loadConfig();
    }

    private loadConfig(): void {
        // Завантаження змінних з .env (dotenv.config() вже викликано на початку файлу)
        try {
            // Перезапис зі змінних середовища (з .env)
            this.loadFromEnvironment();
            // Встановлення значень за замовчуванням для пропущених параметрів
            this.setDefaults();
        } catch (error: unknown) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            this.logger.error('Помилка при завантаженні конфігурації:', errorMessage);
            this.setDefaults();
        }
    }

    private loadFromEnvironment(): void {
        // База даних
        if (process.env.DB_SERVER) {
            this.config.database = {
                ...this.config.database,
                server: process.env.DB_SERVER,
                database: process.env.DB_NAME || this.config.database?.database || 'DocumentDB',
                username: process.env.DB_USER || this.config.database?.username || '',
                password: process.env.DB_PASSWORD || this.config.database?.password || '',
                encrypt: process.env.DB_ENCRYPT === 'true',
                trustServerCertificate: process.env.DB_TRUST_CERT === 'true'
            };
        }

        // SMB
        if (process.env.SMB_SERVER) {
            this.config.smb = {
                ...this.config.smb,
                server: process.env.SMB_SERVER,
                share: process.env.SMB_SHARE || this.config.smb?.share || '',
                username: process.env.SMB_USER || this.config.smb?.username || '',
                password: process.env.SMB_PASSWORD || this.config.smb?.password || '',
                path: process.env.SMB_PATH || this.config.smb?.path || '',
                mountPoint: process.env.SMB_MOUNT_POINT || this.config.smb?.mountPoint
            };
        }

        // Сервер
        if (process.env.PORT) {
            this.config.server = {
                ...this.config.server,
                port: parseInt(process.env.PORT),
                host: process.env.HOST || this.config.server?.host || '0.0.0.0'
            };
        }

        // Ollama
        if (process.env.OLLAMA_URL) {
            this.config.ollama = {
                url: process.env.OLLAMA_URL
            };
        }

        // OpenWebUI
        if (process.env.OPENWEBUI_URL) {
            this.config.openwebui = {
                url: process.env.OPENWEBUI_URL
            };
        }

        // LLM модель
        if (process.env.LLM_MODEL) {
            this.config.llm = {
                ...this.config.llm,
                model: process.env.LLM_MODEL,
                temperature: parseFloat(process.env.LLM_TEMPERATURE || '0.7'),
                max_tokens: parseInt(process.env.LLM_MAX_TOKENS || '2000')
            };
        }

        // Embedding модель
        if (process.env.EMBEDDING_MODEL) {
            this.config.embedding = {
                ...this.config.embedding,
                service: process.env.EMBEDDING_SERVICE || 'http://localhost:11434/api/embeddings',
                model: process.env.EMBEDDING_MODEL
            };
        }
    }

    private setDefaults(): void {
        // Значення за замовчуванням
        this.config = {
            database: {
                server: 'localhost',
                database: 'DocumentDB',
                username: 'sa',
                password: '',
                encrypt: false,
                trustServerCertificate: true,
                ...this.config.database
            },
            smb: {
                server: '',
                share: '',
                username: '',
                password: '',
                path: '/mnt/smb_docs',
                mountPoint: '/mnt/smb_docs',
                ...this.config.smb
            },
            embedding: {
                service: 'http://localhost:11434/api/embeddings',
                model: 'nomic-embed-text',
                ...this.config.embedding
            },
            llm: {
                model: 'llama3.2', // або "mistral", "mixtral", інша модель
                temperature: 0.7, // (0.3) нижче значення для більш точних відповідей при роботі з документами
                max_tokens: 2000,
                ...this.config.llm
            },
            server: {
                port: 3000,
                host: '0.0.0.0',
                ...this.config.server
            },
            ollama: {
                url: 'http://localhost:11434',
                ...this.config.ollama
            },
            openwebui: {
                url: 'http://localhost:8080',
                ...this.config.openwebui
            },
            logging: {
                level: 'info',
                file: 'logs/app.log',
                ...this.config.logging
            },
            ...this.config
        };
    }

    public get<T = any>(key: string, defaultValue?: T): T {
        const keys = key.split('.');
        let value: any = this.config;

        for (const k of keys) {
            if (value && typeof value === 'object' && k in value) {
                value = value[k];
            } else {
                return defaultValue as T;
            }
        }

        return value !== undefined ? value : defaultValue as T;
    }

    public set(key: string, value: any): void {
        const keys = key.split('.');
        let current: any = this.config;

        for (let i = 0; i < keys.length - 1; i++) {
            const k = keys[i];
            if (!(k in current) || typeof current[k] !== 'object') {
                current[k] = {};
            }
            current = current[k];
        }

        current[keys[keys.length - 1]] = value;
    }

    public saveConfig(): boolean {
        if (this.logger.info) {
            this.logger.info('Збереження конфігурації не потрібне: використовується лише .env');
        } else {
            this.logger.log('Збереження конфігурації не потрібне: використовується лише .env');
        }
        return true;
    }

    public validateConfig(): { valid: boolean; errors: string[] } {
        const errors: string[] = [];

        // Перевірка обов'язкових параметрів бази даних
        if (!this.get('database.server')) {
            errors.push('database.server обов\'язковий параметр');
        }
        if (!this.get('database.username')) {
            errors.push('database.username обов\'язковий параметр');
        }
        if (!this.get('database.password')) {
            errors.push('database.password обов\'язковий параметр');
        }

        // Перевірка SMB конфігурації
        if (!this.get('smb.server')) {
            errors.push('smb.server обов\'язковий параметр');
        }
        if (!this.get('smb.share')) {
            errors.push('smb.share обов\'язковий параметр');
        }
        if (!this.get('smb.username')) {
            errors.push('smb.username обов\'язковий параметр');
        }
        if (!this.get('smb.password')) {
            errors.push('smb.password обов\'язковий параметр');
        }

        // Перевірка портів
        const port = this.get('server.port');
        if (port && (port < 1 || port > 65535)) {
            errors.push('server.port повинен бути між 1 та 65535');
        }

        return {
            valid: errors.length === 0,
            errors
        };
    }

    public getFullConfig(): Partial<AppConfig> {
        return { ...this.config };
    }

    public createSampleConfig(): boolean {
        try {
            // Приклад конфігурації у форматі .env
            const sampleEnv = `# Приклад файлу .env для Document Scanner Service
# Скопіюйте цей файл як .env та відредагуйте значення відповідно до вашого середовища

# MSSQL
DB_SERVER=localhost
DB_NAME=DocumentDB
DB_USER=sa
DB_PASSWORD=YourPassword123!
DB_ENCRYPT=false
DB_TRUST_CERT=true

# SMB
SMB_SERVER=192.168.1.100
SMB_SHARE=shared/documents
SMB_USER=your_smb_user
SMB_PASSWORD=your_smb_password
SMB_PATH=/mnt/smb_docs
SMB_MOUNT_POINT=/mnt/smb_docs

# Embedding
EMBEDDING_SERVICE=http://localhost:11434/api/embeddings
EMBEDDING_MODEL=nomic-embed-text

# LLM
LLM_MODEL=llama3.2
LLM_TEMPERATURE=0.7
LLM_MAX_TOKENS=2000

# Server
PORT=3000
HOST=0.0.0.0

# Ollama
OLLAMA_URL=http://localhost:11434

# OpenWebUI
OPENWEBUI_URL=http://localhost:8080

# Logging
LOG_LEVEL=info
LOG_FILE=logs/app.log`;

            const samplePath = path.join(process.cwd(), '.env.example');
            
            // Create the directory if it doesn't exist
            const configDir = path.dirname(samplePath);
            if (!fs.existsSync(configDir)) {
                fs.mkdirSync(configDir, { recursive: true });
            }
            
            fs.writeFileSync(samplePath, sampleEnv);
            if (this.logger.info) {
                this.logger.info(`Зразок конфігурації створено: ${samplePath}`);
            } else {
                this.logger.log(`Зразок конфігурації створено: ${samplePath}`);
            }
            return true;
        } catch (error: unknown) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            this.logger.error('Помилка при створенні зразка конфігурації:', errorMessage);
            return false;
        }
    }
}
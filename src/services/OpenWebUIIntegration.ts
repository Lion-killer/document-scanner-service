import axios from 'axios';
import { ConfigManager } from '../config/ConfigManager';
import { Logger } from '../utils/Logger';
import { VectorDatabase } from './VectorDatabase';

interface QueryRequest {
    message: string;
    context?: string;
    model?: string;
    temperature?: number;
    max_tokens?: number;
}

interface QueryResponse {
    response: string;
    sources: Array<{
        filename: string;
        content: string;
        similarity: number;
    }>;
    model: string;
    usage?: {
        prompt_tokens: number;
        completion_tokens: number;
        total_tokens: number;
    };
}

export class OpenWebUIIntegration {
    private config: ConfigManager;
    private logger: Logger;
    private vectorDb: VectorDatabase;
    private ollamaUrl: string;
    private openWebUIUrl: string;

    constructor(config: ConfigManager, logger: Logger, vectorDb: VectorDatabase) {
        this.config = config;
        this.logger = logger;
        this.vectorDb = vectorDb;
        this.ollamaUrl = config.get('ollama.url', 'http://localhost:11434');
        this.openWebUIUrl = config.get('openwebui.url', 'http://localhost:3000');
    }

    public async initialize(): Promise<void> {
        try {
            // Перевірка підключення до Ollama
            await this.checkOllamaConnection();
            
            // Реєстрація як функції в OpenWebUI (якщо підтримується)
            await this.registerWithOpenWebUI();
            
            this.logger.info('OpenWebUI інтеграція ініціалізована');
        } catch (error: unknown) {
            this.logger.error('Помилка при ініціалізації OpenWebUI інтеграції:', error);
            throw error;
        }
    }

    private async checkOllamaConnection(): Promise<void> {
        try {
            const response = await axios.get(`${this.ollamaUrl}/api/tags`, {
                timeout: 5000
            });
            
            this.logger.info(`Підключено до Ollama. Доступні моделі: ${response.data.models?.length || 0}`);
        } catch (error: unknown) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            this.logger.warn('Не вдалося підключитися до Ollama:', errorMessage);
        }
    }

    private async registerWithOpenWebUI(): Promise<void> {
        try {
            // Спроба реєстрації функції документів в OpenWebUI
            const functionConfig = {
                id: 'document_search',
                name: 'Пошук в документах',
                description: 'Пошук інформації в завантажених документах',
                parameters: {
                    type: 'object',
                    properties: {
                        query: {
                            type: 'string',
                            description: 'Пошуковий запит'
                        },
                        limit: {
                            type: 'number',
                            description: 'Максимальна кількість результатів',
                            default: 5
                        }
                    },
                    required: ['query']
                }
            };

            await axios.post(`${this.openWebUIUrl}/api/functions`, functionConfig, {
                timeout: 5000,
                headers: {
                    'Content-Type': 'application/json'
                }
            });

            this.logger.info('Функція пошуку документів зареєстрована в OpenWebUI');
        } catch (error: unknown) {
            this.logger.debug('Не вдалося зареєструвати функцію в OpenWebUI (можливо, не підтримується)');
        }
    }

    public async processQuery(message: string, context?: string): Promise<QueryResponse> {
        try {
            // Пошук релевантних документів
            const searchResults = await this.vectorDb.searchSimilar(message, 5);
            
            // Формування контексту з знайдених документів
            const documentContext = searchResults
                .map(result => `[${result.filename}]\n${result.content}`)
                .join('\n\n---\n\n');

            // Формування промпту для LLM
            const systemPrompt = this.buildSystemPrompt();
            const userPrompt = this.buildUserPrompt(message, documentContext, context);

            // Запит до локальної LLM через Ollama
            const llmResponse = await this.queryLocalLLM(systemPrompt, userPrompt);

            return {
                response: llmResponse.response,
                sources: searchResults.map(result => ({
                    filename: result.filename,
                    content: result.content.substring(0, 200) + '...',
                    similarity: result.similarity
                })),
                model: llmResponse.model,
                usage: llmResponse.usage
            };

        } catch (error: unknown) {
            this.logger.error('Помилка при обробці запиту:', error);
            throw error;
        }
    }

    private buildSystemPrompt(): string {
        return `Ви - помічник для роботи з документами. Ваше завдання - відповідати на запитання користувачів, базуючись на наданих документах.

Правила:
1. Використовуйте тільки інформацію з наданих документів
2. Якщо інформації недостатньо, чесно повідомте про це
3. Завжди вказуйте джерело інформації (назву файлу)
4. Відповідайте українською мовою
5. Будьте точними та корисними

Формат відповіді:
- Дайте чітку відповідь на запитання
- Вкажіть джерела у форматі [Назва файлу]
- Якщо потрібно, надайте додаткові роз'яснення`;
    }

    private buildUserPrompt(message: string, documentContext: string, additionalContext?: string): string {
        let prompt = `Запитання користувача: ${message}\n\n`;
        
        if (documentContext.trim()) {
            prompt += `Контекст з документів:\n${documentContext}\n\n`;
        }
        
        if (additionalContext?.trim()) {
            prompt += `Додатковий контекст: ${additionalContext}\n\n`;
        }
        
        prompt += 'Будь ласка, дайте відповідь на основі наданої інформації.';
        
        return prompt;
    }

    private async queryLocalLLM(systemPrompt: string, userPrompt: string): Promise<{
        response: string;
        model: string;
        usage?: any;
    }> {
        const model = this.config.get('llm.model', 'llama3.2');
        const temperature = this.config.get('llm.temperature', 0.7);
        const maxTokens = this.config.get('llm.max_tokens', 2000);

        try {
            const response = await axios.post(`${this.ollamaUrl}/api/chat`, {
                model: model,
                messages: [
                    {
                        role: 'system',
                        content: systemPrompt
                    },
                    {
                        role: 'user',
                        content: userPrompt
                    }
                ],
                options: {
                    temperature: temperature,
                    num_predict: maxTokens
                },
                stream: false
            }, {
                timeout: 60000
            });

            return {
                response: response.data.message?.content || 'Не вдалося отримати відповідь',
                model: model,
                usage: {
                    prompt_tokens: response.data.prompt_eval_count || 0,
                    completion_tokens: response.data.eval_count || 0,
                    total_tokens: (response.data.prompt_eval_count || 0) + (response.data.eval_count || 0)
                }
            };

        } catch (error: unknown) {
            this.logger.error('Помилка при запиті до локальної LLM:', error);
            
            // Fallback відповідь
            return {
                response: 'Вибачте, не вдалося отримати відповідь від локальної LLM. Перевірте чи запущено Ollama та чи встановлено потрібну модель.',
                model: model
            };
        }
    }

    public async generateSummary(documentId: string): Promise<string> {
        try {
            const context = await this.vectorDb.getDocumentContext([documentId]);
            
            const summaryPrompt = `Створіть стислий реферат наступного документа українською мовою:

${context}

Реферат повинен містити:
1. Основну тему документа
2. Ключові пункти
3. Висновки (якщо є)

Максимум 200 слів.`;

            const response = await this.queryLocalLLM(
                'Ви - експерт з створення рефератів документів.',
                summaryPrompt
            );

            return response.response;

        } catch (error: unknown) {
            this.logger.error('Помилка при створенні реферату:', error);
            throw error;
        }
    }

    public async suggestQuestions(documentId: string): Promise<string[]> {
        try {
            const context = await this.vectorDb.getDocumentContext([documentId]);
            
            const questionsPrompt = `На основі наступного документа запропонуйте 5 питань, які користувач може поставити:

${context}

Питання повинні бути:
1. Релевантними до змісту
2. Корисними для розуміння документа
3. Українською мовою

Формат відповіді: список питань через новий рядок, кожне питання починається з "- "`;

            const response = await this.queryLocalLLM(
                'Ви - експерт з аналізу документів та формування питань.',
                questionsPrompt
            );

            // Парсинг відповіді на окремі питання
            const questions = response.response
                .split('\n')
                .filter(line => line.trim().startsWith('-'))
                .map(line => line.replace(/^-\s*/, '').trim())
                .filter(question => question.length > 0)
                .slice(0, 5);

            return questions;

        } catch (error: unknown) {
            this.logger.error('Помилка при генерації питань:', error);
            return [];
        }
    }

    public async translateQuery(query: string, targetLanguage: string = 'uk'): Promise<string> {
        try {
            const translatePrompt = `Переклади наступний текст на ${targetLanguage === 'uk' ? 'українську' : 'англійську'} мову:

${query}

Надай тільки переклад без додаткових коментарів.`;

            const response = await this.queryLocalLLM(
                'Ви - професійний перекладач.',
                translatePrompt
            );

            return response.response.trim();

        } catch (error: unknown) {
            this.logger.error('Помилка при перекладі:', error);
            return query; // Повертаємо оригінальний текст у разі помилки
        }
    }

    // Функція для OpenWebUI Function API
    public async documentSearchFunction(params: { query: string; limit?: number }): Promise<any> {
        try {
            const { query, limit = 5 } = params;
            const results = await this.vectorDb.searchSimilar(query, limit);
            
            return {
                success: true,
                results: results.map(result => ({
                    filename: result.filename,
                    content: result.content.substring(0, 300) + '...',
                    similarity: Math.round(result.similarity * 100) / 100
                }))
            };
        } catch (error: unknown) {
            return {
                success: false,
                error: error instanceof Error ? error.message : String(error)
            };
        }
    }

    public async close(): Promise<void> {
        this.logger.info('OpenWebUI інтеграція зупинена');
    }
}
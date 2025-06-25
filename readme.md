# Додаток для автоматичного сканування документів

Цей додаток автоматично сканує SMB папку з документами (PDF, DOC, DOCX), оновлює векторну базу даних і забезпечує інтеграцію з локальною LLM через OpenWebUI.

> **ВАЖЛИВО**: Даний контейнер містить ТІЛЬКИ сервіс сканування документів. Зовнішні сервіси (Ollama, Qdrant, OpenWebUI) мають бути розгорнуті окремо та доступні через мережу. Інструкції з налаштування середовища LXC/Proxmox та підключення до цих сервісів знаходяться в [LXC_DEPLOYMENT_README.md](scripts/LXC_DEPLOYMENT_README.md).

## Огляд функціональності

Document Scanner Service надає такі можливості:
- **Автоматичне сканування** документів у SMB-директорії
- **Векторна індексація** вмісту документів за допомогою Qdrant
- **Семантичний пошук** по контенту документів
- **Веб-інтерфейс** для зручного керування та перегляду
- **Інтеграція з OpenWebUI** для роботи з документами через LLM
- **API** для програмної взаємодії з сервісом

### Основні компоненти
- **Сканер документів**: автоматично виявляє та обробляє PDF, DOC, DOCX файли
- **Векторна база даних**: зберігає семантичні вектори документів для швидкого пошуку
- **REST API**: надає програмний доступ до всіх функцій сервісу
- **Веб-інтерфейс**: дозволяє зручно керувати документами та виконувати пошук

- Перегляд статусу системи
- Запуск ручного сканування документів
- Пошук по вмісту документів 
- Перегляд та фільтрація документів
- Видалення документів

Веб-інтерфейс автоматично встановлюється та налаштовується при розгортанні сервісу.

Детальні інструкції з налаштування середовища LXC/Proxmox та підключення до цих сервісів знаходяться в [LXC_DEPLOYMENT_README.md](scripts/LXC_DEPLOYMENT_README.md).

## Системні вимоги

- Node.js 18+ 
- Ubuntu/Debian Linux (для SMB монтування)
- Зовнішні сервіси (мають бути розгорнуті окремо):
  - Qdrant (векторна база даних)
  - Ollama (для локальної LLM та ембедингів)
  - OpenWebUI (опціонально)

> **ПРИМІТКА**: Скрипт розгортання автоматично встановлює всі необхідні залежності для різних версій Ubuntu/Debian.

## Встановлення та розгортання

Цей сервіс розроблено для роботи в контейнері LXC на основі Debian. Детальні інструкції з розгортання, включаючи налаштування контейнера та підключення до зовнішніх сервісів (Qdrant, Ollama та OpenWebUI), знаходяться в файлі [LXC_DEPLOYMENT_README.md](scripts/LXC_DEPLOYMENT_README.md).

### Базові залежності Linux для розробки

Якщо ви розробляєте або тестуєте додаток локально, вам знадобляться наступні залежності:

```bash
# Оновлення системи
apt update && apt upgrade -y

# Встановлення SMB клієнта
apt install cifs-utils -y

# Встановлення утиліт для обробки документів
apt install antiword libreoffice-writer -y

# Встановлення git
apt install git -y

# Встановлення Node.js
curl -sL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# Встановлення npm
apt install -y npm

# Встановлення TypeScript
npm install -g typescript

# Встановлення інших залежностей
npm install -g ts-node

# Створення точки монтування для SMB
mkdir -p /mnt/smb_docs
chown $USER:$USER /mnt/smb_docs
```

## Налаштування додатку

### 1. Клонування та встановлення

```bash
# Клонуйте репозиторій або створіть нову папку
git clone https://github.com/Lion-killer/document-scanner-service.git
# Або створіть нову папку вручну
mkdir document-scanner-service
cd document-scanner-service

# Скопіюйте файли проекту та встановіть залежності
npm install
```

### 2. Структура проекту

```
document-scanner-service/
├── src/
│   ├── app.ts                    # Головний файл додатку
│   ├── config/
│   │   └── ConfigManager.ts      # Менеджер конфігурації
│   ├── services/
│   │   ├── DocumentScanner.ts    # Сервіс сканування документів
│   │   ├── VectorDatabase.ts     # Сервіс векторної бази даних
│   │   └── OpenWebUIIntegration.ts # Інтеграція з OpenWebUI
│   └── utils/
│       └── Logger.ts             # Утиліта логування
├── public/
│   ├── index.html               # Головна сторінка веб-інтерфейсу
│   ├── styles.css               # Стилі веб-інтерфейсу
│   └── app.js                   # JavaScript для веб-інтерфейсу
├── scripts/
│   ├── LXC_DEPLOYMENT_README.md  # Інструкції з розгортання в LXC
│   ├── lxc_deployment.sh         # Скрипт розгортання в LXC
│   ├── lxc_setup.sh             # Скрипт налаштування LXC
│   ├── lxc_smb_mount.sh         # Скрипт монтування SMB
│   └── test_remote_connections.sh # Скрипт тестування з'єднань
├── .env                        # Файл конфігурації
├── package.json
├── tsconfig.json
└── readme.md
```

### 3. Конфігурація

Для налаштування змінних середовища та конфігурації сервісу дивіться [інструкцію з розгортання](scripts/LXC_DEPLOYMENT_README.md). Там описано як підключитися до зовнішніх сервісів (Qdrant, Ollama та OpenWebUI) і як налаштувати всі необхідні параметри сервісу у файлі `.env`.

```bash
# Створення зразка конфігурації
npm run create-config
```

## База даних

Колекції у векторній базі даних Qdrant створюються автоматично при першому запуску додатку. Деталі підключення до Qdrant та необхідні налаштування бази даних описані в [інструкції з розгортання](scripts/LXC_DEPLOYMENT_README.md).

## Запуск додатку

### 1. Збірка проекту

```bash
npm run build
```

### 2. Запуск в режимі розробки

```bash
npm run dev
```

### 3. Запуск в продакшені

```bash
npm start
```

### 4. Як systemd сервіс

Створіть файл `/etc/systemd/system/document-scanner.service`:

```ini
[Unit]
Description=Document Scanner Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=your_user
WorkingDirectory=/path/to/document-scanner-service
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

Активація сервісу:

```bash
systemctl daemon-reload
systemctl enable document-scanner
systemctl start document-scanner
systemctl status document-scanner
```

## Використання

### 1. API ендпоінти

- `GET /api/status` - Статус системи
- `POST /api/scan/manual` - Ручний запуск сканування
- `GET /api/documents` - Список документів
- `POST /api/search` - Пошук по документах
- `DELETE /api/documents/:id` - Видалення документа
- `POST /api/openwebui/query` - Запит до LLM з контекстом

### 2. Веб інтерфейс

Відкрийте браузер та перейдіть на `http://localhost:3000`

Особливості нового чат-інтерфейсу:
- **Взаємодія з документами через чат** - просто задайте питання і отримайте відповіді на основі ваших документів
- **Бокове меню** - доступ до всіх функцій через зручне бургер-меню
- **Попередній перегляд документів** - відкриття документів у зручному форматованому вигляді в окремому вікні
- **Джерела інформації** - відповіді містять посилання на документи, з яких була отримана інформація

Для швидкого запуску та перевірки сервісу можна використати скрипт PowerShell:
```powershell
.\scripts\start-document-scanner.ps1
```

Додаткові PowerShell скрипти для розробки та тестування на Windows:
```powershell
# Налаштування змінних середовища (параметри підключення до сервісів)
.\scripts\configure-env.ps1

# Тестування функціональності чату
.\scripts\test-chat-api.ps1

# Тестування доступності всіх компонентів
.\scripts\test-chat-functionality.ps1

# Тестування SMB-підключення
.\scripts\test-smb-connection.ps1

# Моніторинг стану сервісів в реальному часі
.\scripts\monitor-services.ps1

# Перезапуск сервісу після змін
.\scripts\update-chat-interface.ps1
```

### 3. Інтеграція з OpenWebUI

1. Відкрийте OpenWebUI за адресою, вказаною в конфігурації (.env файл, параметр OPENWEBUI_URL)
2. Додайте функцію пошуку документів
3. Використовуйте в чатах для роботи з документами

> **Примітка**: Адреса OpenWebUI налаштовується при розгортанні і має вказувати на зовнішній сервіс OpenWebUI.

## Налагодження

### 1. Перевірка логів

```bash
# Дивитися логи в реальному часі
tail -f logs/app.log

# Пошук помилок
grep ERROR logs/app.log
```

### 2. Перевірка SMB підключення

```bash
# Ручне монтування для тестування
mount -t cifs //192.168.1.100/shared /mnt/smb_docs \
  -o username=your_user,password=your_password,uid=$(id -u),gid=$(id -g)

# Перевірка доступу
ls -la /mnt/smb_docs
```

### 3. Перевірка зовнішніх сервісів

Для перевірки підключення до зовнішніх сервісів (Ollama, Qdrant, OpenWebUI) та перевірки їх працездатності використовуйте скрипт:

```bash
# Із директорії проекту
bash scripts/test_remote_connections.sh
```

Цей скрипт перевіряє доступність всіх зовнішніх сервісів, які сконфігуровані в `.env` файлі.

## Автоматизація

### 1. Резервне копіювання

Створіть скрипт `/home/user/backup-docs.sh`:

```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/documents"

# Створення директорії
mkdir -p $BACKUP_DIR

# Експорт колекцій Qdrant (якщо потрібно)
# Опціонально додайте команди для резервного копіювання ваших векторних даних

# Бекап конфігурації
cp /path/to/document-scanner-service/.env $BACKUP_DIR/env_$DATE.txt

echo "Бекап завершено: $BACKUP_DIR"
```

Додайте в crontab:

```bash
# Щоденний бекап о 2:00
0 2 * * * /home/user/backup-docs.sh
```

### 2. Моніторинг

Створіть скрипт моніторингу `/home/user/monitor-docs.sh`:

```bash
#!/bin/bash
SERVICE_NAME="document-scanner"

# Перевірка статусу сервісу
if ! systemctl is-active --quiet $SERVICE_NAME; then
    echo "Сервіс $SERVICE_NAME не активний, перезапуск..."
    systemctl restart $SERVICE_NAME
    
    # Надіслати повідомлення (налаштуйте за потребою)
    echo "Document Scanner Service restarted" | \
      mail -s "Service Alert" admin@example.com
fi

# Перевірка використання диску
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    echo "Попередження: використання диску $DISK_USAGE%"
fi
```

## Оптимізація продуктивності

### 1. Налаштування Qdrant

Для оптимізації продуктивності Qdrant можливо застосувати наступні рекомендації:

- Використовуйте правильні параметри індексації для ваших векторів
- Налаштуйте оптимальну кількість шардів для колекцій з великою кількістю документів
- Збільшуйте ліміт пам'яті для Qdrant в залежності від розміру вашої колекції

### 2. Оптимізація Node.js

Додайте в `package.json` скрипт для продакшену:

```json
{
  "scripts": {
    "start:prod": "node --max-old-space-size=4096 --optimize-for-size dist/app.js"
  }
}
```

## Розширення функціональності

### 1. Додавання нових типів файлів

Відредагуйте `DocumentScanner.ts`:

```typescript
// Додайте нові розширення
private supportedExtensions = ['.pdf', '.doc', '.docx', '.txt', '.rtf', '.odt'];

// Додайте методи обробки
private async extractFromTxt(buffer: Buffer): Promise<string> {
    return buffer.toString('utf-8');
}

private async extractFromRtf(filepath: string): Promise<string> {
    // Використайте unrtf або інші утиліти
    const { stdout } = await execAsync(`unrtf --text "${filepath}"`);
    return stdout;
}
```

### 2. Інтеграція з іншими LLM

Створіть новий сервіс `src/services/LLMRouter.ts`:

```typescript
export class LLMRouter {
    private providers: Map<string, LLMProvider> = new Map();

    public addProvider(name: string, provider: LLMProvider): void {
        this.providers.set(name, provider);
    }

    public async query(message: string, provider: string = 'ollama'): Promise<any> {
        const llm = this.providers.get(provider);
        if (!llm) throw new Error(`Provider ${provider} не знайдено`);
        
        return await llm.query(message);
    }
}
```

### 3. Веб-інтерфейс

Додаток включає в себе веб-інтерфейс для зручного керування та перегляду документів. Інтерфейс доступний за адресою `http://localhost:3000` і надає такі можливості:

- Перегляд статусу системи
- Запуск ручного сканування документів
- Пошук по вмісту документів 
- Перегляд та фільтрація документів
- Видалення документів

Веб-інтерфейс автоматично встановлюється та налаштовується при розгортанні сервісу.

## Безпека

### 1. Налаштування HTTPS

Створіть SSL сертифікати:

```bash
# Самопідписаний сертифікат для тестування
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes
```

Додайте HTTPS в додаток:

```typescript
import * as https from 'https';
import * as fs from 'fs';

// У app.ts
if (this.config.get('server.https', false)) {
    const options = {
        key: fs.readFileSync(this.config.get('server.keyFile', 'key.pem')),
        cert: fs.readFileSync(this.config.get('server.certFile', 'cert.pem'))
    };
    
    https.createServer(options, this.app).listen(port, () => {
        this.logger.info(`HTTPS сервер запущено на порту ${port}`);
    });
}
```

### 2. Аутентифікація

Додайте базову аутентифікацію:

```typescript
import * as crypto from 'crypto';

class AuthMiddleware {
    private apiKeys: Set<string> = new Set();

    constructor(keys: string[]) {
        keys.forEach(key => this.apiKeys.add(key));
    }

    public authenticate(req: any, res: any, next: any): void {
        const apiKey = req.headers['x-api-key'];
        
        if (!apiKey || !this.apiKeys.has(apiKey)) {
            return res.status(401).json({ error: 'Недійсний API ключ' });
        }
        
        next();
    }
}
```

### 3. Обмеження швидкості

```bash
npm install express-rate-limit
```

```typescript
import rateLimit from 'express-rate-limit';

const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 хвилин
    max: 100, // максимум 100 запитів
    message: 'Занадто багато запитів з цієї IP'
});

this.app.use('/api/', limiter);
```

## Підтримка та оновлення

### 1. Створення бекапів

```bash
#!/bin/bash
# backup.sh
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/document-scanner/$DATE"

mkdir -p $BACKUP_DIR

# Бекап конфігурації підключення до зовнішніх сервісів

# Бекап конфігурації
cp .env $BACKUP_DIR/
cp -r logs/ $BACKUP_DIR/

echo "Бекап створено: $BACKUP_DIR"
```

### 2. Автоматичні оновлення

```bash
#!/bin/bash
# update.sh
cd /path/to/document-scanner-service

# Зупинка сервісу
systemctl stop document-scanner

# Бекап поточної версії
cp -r . ../document-scanner-backup-$(date +%Y%m%d)

# Оновлення коду (git pull або копіювання нових файлів)
git pull origin main

# Встановлення залежностей
npm install

# Збірка
npm run build

# Запуск сервісу
systemctl start document-scanner

echo "Оновлення завершено"
```

### 3. Моніторинг логів

```bash
# Налаштування logrotate
tee /etc/logrotate.d/document-scanner << EOF
/path/to/document-scanner-service/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF
```

# Інформація для користувачів

Детальна інформація про використання сервісу, включаючи інструкції з пошуку, індексації документів та інтеграції з іншими сервісами, знаходиться вище в розділах "Використання", "Веб-інтерфейс" та "Оптимізація продуктивності".

# Інформація для розробників

Більш детальні інструкції з розгортання проекту в середовищі LXC/Proxmox дивіться у файлі [LXC_DEPLOYMENT_README.md](scripts/LXC_DEPLOYMENT_README.md).

## Troubleshooting

### Типові проблеми та рішення

1. **Помилка підключення до SMB**
   ```bash
   # Перевірка доступності сервера
   ping 192.168.1.100
   
   # Тестування SMB підключення
   smbclient -L //192.168.1.100 -U username
   ```

2. **Проблеми з підключенням до зовнішніх сервісів**
   
   Якщо виникають проблеми з підключенням до зовнішніх сервісів (Ollama, Qdrant, OpenWebUI):
   
   ```bash
   # Використовуйте скрипт для перевірки всіх підключень
   bash scripts/test_remote_connections.sh
   
   # Перевірка мережевої доступності зовнішніх сервісів
   ping ollama-host
   ping qdrant-host
   ping openwebui-host
   ```

4. **Проблеми з пам'яттю**
   ```bash
   # Моніторинг використання
   htop
   
   # Налаштування swap
   fallocate -l 4G /swapfile
   chmod 600 /swapfile
   mkswap /swapfile
   swapon /swapfile
   ```

Додаток готовий до використання! Слідуйте інструкціям покроково для успішного налаштування системи автоматичного сканування документів з інтеграцією векторної бази даних та локальної LLM.
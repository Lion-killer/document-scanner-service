#!/bin/bash
# lxc_deployment.sh - Скрипт для розгортання Сервісу Сканування Документів всередині LXC контейнера
#
# Використання:
# sudo ./lxc_deployment.sh [шлях_до_env_файлу]
#
# Приклад:
# sudo ./lxc_deployment.sh /шлях/до/.env
#
# Якщо шлях до .env не вказано, скрипт шукатиме .env в поточній директорії,
# а якщо не знайде - спробує клонувати репозиторій і використати .env.example з нього

# Функція для логування
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [LXC_DEPLOY] $1"
}

# Функція для виводу помилки та виходу
error_exit() {
    log "ПОМИЛКА: $1" >&2
    exit 1
}

# Перевірка запуску від імені root (необхідно для systemctl, apt)
if [ "$(id -u)" -ne 0 ]; then
  error_exit "Цей скрипт потрібно запускати з правами root (sudo)."
fi

# Шлях до додатку
APP_DIR="/opt/document-scanner-service"
DEFAULT_ENV_FILE="$APP_DIR/.env"

# Функція для завантаження змінних з .env файлу
load_env_file() {
    local env_file="$1"
    log "Завантаження змінних із файлу $env_file"
    
    if [ ! -f "$env_file" ]; then
        error_exit "Файл .env не знайдено: $env_file"
    fi
    
    # Завантажуємо змінні з .env файлу
    set -a  # автоматично експортувати змінні
    # Пропускаємо рядки з коментарями та порожні рядки
    source <(grep -v '^#' "$env_file" | grep -v '^\s*$')
    set +a
    
    log "Змінні успішно завантажено з $env_file"
}

# Визначення шляху до .env файлу
ENV_FILE="${1:-}"
GIT_REPO_URL="https://github.com/Lion-killer/document-scanner-service.git"
GIT_REPO_BRANCH="master"

# Якщо .env файл не вказано у параметрах
if [ -z "$ENV_FILE" ]; then
    log "Шлях до .env файлу не вказано, шукаємо .env в поточній директорії"
    if [ -f ".env" ]; then
        ENV_FILE="./.env"
        log "Знайдено файл .env в поточній директорії"
    # Шукаємо в директорії скрипта
    elif [ -f "$(dirname "$0")/.env" ]; then
        ENV_FILE="$(dirname "$0")/.env"
        log "Знайдено файл .env в директорії скрипта: $ENV_FILE"
    # Шукаємо в проекті
    elif [ -f "$(dirname "$0")/../.env" ]; then
        ENV_FILE="$(dirname "$0")/../.env"
        log "Знайдено файл .env в кореневій директорії проекту: $ENV_FILE"
    else
        log "Файл .env не знайдено в доступних директоріях"
        log "Необхідно вказати шлях до .env файлу. Використання: sudo ./lxc_deployment.sh /шлях/до/.env"
        error_exit "Файл .env не знайдено в доступних директоріях. Створіть .env файл або вкажіть шлях до нього."
        
        # Перевіряємо, чи встановлений git
        if ! command -v git &> /dev/null; then
            log "Git не знайдено. Встановлення Git..."
            apt-get update -y || error_exit "Не вдалося оновити пакети."
            apt-get install -y git || error_exit "Не вдалося встановити Git."
        fi
        
        # Створюємо тимчасову директорію для клонування
        TMP_DIR=$(mktemp -d)
        log "Клонування репозиторію у тимчасову директорію $TMP_DIR"
        git clone --depth=1 --branch $GIT_REPO_BRANCH $GIT_REPO_URL $TMP_DIR || error_exit "Не вдалося клонувати репозиторій для отримання .env.example"
        
        if [ -f "$TMP_DIR/.env.example" ]; then
            ENV_FILE="$TMP_DIR/.env.example"
            log "Використовуємо .env.example з репозиторію як файл конфігурації"
        else
            rm -rf $TMP_DIR
            error_exit "Файл .env.example не знайдено в репозиторії"
        fi
    fi
fi

# Завантажуємо змінні з .env файлу
load_env_file "$ENV_FILE"

# Перевірка обов'язкових змінних середовища
if [ -z "$DB_SERVER" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ] || [ -z "$OLLAMA_URL" ] || [ -z "$OPENWEBUI_URL" ]; then
    error_exit "Не вказані всі обов'язкові параметри в .env файлі: DB_SERVER, DB_USER, DB_PASSWORD, OLLAMA_URL, OPENWEBUI_URL"
fi

# Встановлюємо змінні для подальшого використання
MSSQL_HOST="$DB_SERVER"
MSSQL_USER="$DB_USER"
MSSQL_PASSWORD="$DB_PASSWORD"
MSSQL_DATABASE_NAME="$DB_NAME"
OLLAMA_HOST_URL="$OLLAMA_URL"
OPENWEBUI_HOST_URL="$OPENWEBUI_URL"

# Параметри SMB, якщо вони вказані в .env
if [ -n "$SMB_SERVER" ] && [ -n "$SMB_SHARE" ]; then
    # Формуємо повний шлях SMB
    if [[ "$SMB_SERVER" == "//"* ]]; then
        SMB_SERVER_SHARE="$SMB_SERVER/$SMB_SHARE"
    else
        SMB_SERVER_SHARE="//$SMB_SERVER/$SMB_SHARE"
    fi
    SMB_SHARE_NAME_ONLY="$SMB_SHARE"
    SMB_SERVER_IP_ONLY="$SMB_SERVER"
fi

log "Початок розгортання Document Scanner Service."
log "MSSQL Host: $MSSQL_HOST, User: $MSSQL_USER, DB: $MSSQL_DATABASE_NAME"
log "Ollama URL: $OLLAMA_HOST_URL"
log "OpenWebUI URL: $OPENWEBUI_HOST_URL"
log "Репозиторій коду: $GIT_REPO_URL (гілка: $GIT_REPO_BRANCH)"
if [ -n "$SMB_SERVER_SHARE" ]; then
    log "SMB Share: $SMB_SERVER_SHARE, Mount Point: $SMB_MOUNT_POINT, User: $SMB_USER"
fi

CONFIG_FILE="$APP_DIR/.env"

# 1. Оновлення системи та встановлення залежностей
log "Оновлення пакетів системи..."
apt-get update -y || error_exit "Не вдалося оновити пакети."

log "Перевірка та встановлення Git..."
if ! command -v git &> /dev/null; then
    log "Git не знайдено. Встановлення Git..."
    apt-get install -y git || error_exit "Не вдалося встановити Git."
fi
log "Git version: $(git --version)"

log "Встановлення Node.js (LTS) та npm..."
# Використання NodeSource для останньої LTS версії Node.js
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs || error_exit "Не вдалося встановити Node.js."
log "Node.js version: $(node -v)"
log "npm version: $(npm -v)"

log "Встановлення build-essential та python3 (для деяких npm пакетів)..."
apt-get install -y build-essential python3 || error_exit "Не вдалося встановити build-essential та python3."

# 2. Клонування репозиторію або перевірка наявності коду додатку
REPO_URL="$GIT_REPO_URL"
REPO_BRANCH="$GIT_REPO_BRANCH"

log "Перевірка наявності коду додатку або клонування з репозиторію $REPO_URL (гілка $REPO_BRANCH)..."
if [ ! -d "$APP_DIR" ]; then
    log "Директорія додатку $APP_DIR не існує. Клонування з репозиторію $REPO_URL..."
    mkdir -p "$(dirname "$APP_DIR")"
    git clone --branch $REPO_BRANCH $REPO_URL "$APP_DIR" || error_exit "Не вдалося склонувати репозиторій $REPO_URL."
    log "Репозиторій успішно склоновано в $APP_DIR"
else
    log "Директорія $APP_DIR вже існує. Перевірка, чи це Git-репозиторій..."
    if [ -d "$APP_DIR/.git" ]; then
        log "Оновлення існуючого Git репозиторію..."
        cd "$APP_DIR" || error_exit "Не вдалося перейти в директорію $APP_DIR."
        git fetch origin || log "ПОПЕРЕДЖЕННЯ: Не вдалося оновити репозиторій. Продовжуємо з існуючою версією."
        git reset --hard "origin/$REPO_BRANCH" || log "ПОПЕРЕДЖЕННЯ: Не вдалося оновити до останньої версії гілки $REPO_BRANCH. Продовжуємо з існуючою версією."
    else
        log "Директорія $APP_DIR не є Git-репозиторієм."
        # Перевірка, чи містить директорія файл package.json
        if [ ! -f "$APP_DIR/package.json" ]; then
            error_exit "Директорія $APP_DIR не є Git-репозиторієм і не містить файл package.json. Видаліть директорію для автоматичного клонування або додайте файли вручну."
        fi
    fi
fi

cd "$APP_DIR" || error_exit "Не вдалося перейти в директорію $APP_DIR."

# 3. Встановлення залежностей додатку
log "Встановлення npm залежностей для $APP_DIR..."
npm install --omit=dev || error_exit "Не вдалося встановити npm залежності."

# 4. Створення/Оновлення конфігураційного файлу .env
log "Створення/Оновлення .env файлу..."

# Створення директорії додатку, якщо її немає
mkdir -p "$APP_DIR" # Створюємо директорію, якщо її немає

# Експортуємо змінні у .env
log "Оновлення .env файлу в $APP_DIR..."

cat > "$APP_DIR/.env" <<EOL
# MSSQL
DB_SERVER=$MSSQL_HOST
DB_NAME=$MSSQL_DATABASE_NAME
DB_USER=$MSSQL_USER
DB_PASSWORD=$MSSQL_PASSWORD
DB_ENCRYPT=false
DB_TRUST_CERT=true

# Ollama
OLLAMA_URL=$OLLAMA_HOST_URL
EMBEDDING_SERVICE=${OLLAMA_HOST_URL}/api/embeddings
EMBEDDING_MODEL=nomic-embed-text

# LLM
LLM_MODEL=llama3.2
LLM_TEMPERATURE=0.7
LLM_MAX_TOKENS=2000

# OpenWebUI
OPENWEBUI_URL=$OPENWEBUI_HOST_URL

# Server
PORT=3000
HOST=0.0.0.0

# Logging
LOG_LEVEL=info
LOG_FILE=logs/app.log
EOL

# SMB конфігурація, якщо параметри надані
if [ -n "$SMB_SERVER_SHARE" ]; then
    log "Додавання SMB конфігурації в .env..."
    cat >> "$APP_DIR/.env" <<EOL

# SMB
SMB_SERVER=$SMB_SERVER_IP_ONLY
SMB_SHARE=$SMB_SHARE_NAME_ONLY
SMB_USER=$SMB_USER
SMB_PASSWORD=$SMB_PASSWORD
SMB_PATH=$SMB_MOUNT_POINT
SMB_MOUNT_POINT=$SMB_MOUNT_POINT
EOL

    # Запуск скрипта монтування SMB, якщо він існує
    SMB_MOUNT_SCRIPT="/opt/scripts/lxc_smb_mount.sh"
    if [ -f "$SMB_MOUNT_SCRIPT" ]; then
        log "Запуск скрипта монтування SMB: $SMB_MOUNT_SCRIPT"
        # Передаємо SMB_SERVER_SHARE як є, бо скрипт очікує повний шлях
        bash "$SMB_MOUNT_SCRIPT" "$SMB_SERVER_SHARE" "$SMB_MOUNT_POINT" "$SMB_USER" "$SMB_PASSWORD"
        # Перевірка успішності монтування
        if mount | grep -q "$SMB_MOUNT_POINT"; then
            log "SMB ресурс успішно змонтовано в $SMB_MOUNT_POINT."
        else
            log "ПОПЕРЕДЖЕННЯ: Не вдалося автоматично змонтувати SMB ресурс. Перевірте налаштування та логи $SMB_MOUNT_SCRIPT."
        fi
    else
        log "ПОПЕРЕДЖЕННЯ: Скрипт $SMB_MOUNT_SCRIPT не знайдено. SMB монтування не буде виконано автоматично."
    fi
fi

log ".env файл успішно оновлено:"
cat "$APP_DIR/.env"

# 5. Збірка проекту (якщо потрібно)
if [ -f "$APP_DIR/tsconfig.json" ] && jq -e '.compilerOptions.outDir' "$APP_DIR/tsconfig.json" > /dev/null; then
    log "Збірка проекту TypeScript..."
    npm run build || error_exit "Не вдалося зібрати проект."
    log "Проект зібрано."
else
    log "Пропускаємо крок збірки (немає tsconfig.json або outDir не вказано)."
fi

# 6. Налаштування systemd сервісу
SERVICE_NAME="document-scanner"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
# Визначаємо стартовий скрипт. Якщо є outDir, то використовуємо його, інакше app.ts
START_SCRIPT="dist/app.js" # За замовчуванням для збірки TypeScript
if [ -f "$APP_DIR/tsconfig.json" ] && jq -e '.compilerOptions.outDir' "$APP_DIR/tsconfig.json" > /dev/null; then
    OUT_DIR=$(jq -r '.compilerOptions.outDir' "$APP_DIR/tsconfig.json")
    START_SCRIPT="${OUT_DIR}/app.js" # Припускаємо, що головний файл app.js
    # Перевірка, чи існує app.js у outDir
    if [ ! -f "$APP_DIR/$START_SCRIPT" ]; then
        log "ПОПЕРЕДЖЕННЯ: Головний файл $APP_DIR/$START_SCRIPT не знайдено після збірки. Перевірте налаштування tsconfig.json та структуру проекту."
        # Спробуємо знайти інший .js файл, якщо app.js немає
        FIRST_JS_IN_DIST=$(find "$APP_DIR/$OUT_DIR" -name '*.js' -print -quit)
        if [ -n "$FIRST_JS_IN_DIST" ]; then
            START_SCRIPT=$(realpath --relative-to="$APP_DIR" "$FIRST_JS_IN_DIST")
            log "Використовуємо знайдений файл: $START_SCRIPT"
        else
             error_exit "Не знайдено жодного .js файлу в $APP_DIR/$OUT_DIR. Неможливо визначити стартовий скрипт."
        fi
    fi
elif [ -f "$APP_DIR/src/app.ts" ] && [ -f "$APP_DIR/tsconfig.json" ]; then
    # Якщо є tsconfig, але немає outDir, можливо, використовується ts-node
    START_SCRIPT="src/app.ts"
    PRE_EXEC="npx ts-node"
    log "Виявлено TypeScript проект без outDir, буде використано ts-node."
elif [ -f "$APP_DIR/app.js" ]; then
    START_SCRIPT="app.js" # Для JavaScript проектів
else
    error_exit "Не вдалося визначити стартовий скрипт (app.js, dist/app.js або src/app.ts)."
fi


log "Створення systemd сервісу $SERVICE_FILE для $START_SCRIPT..."
cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=Document Scanner Service
After=network.target

[Service]
Type=simple
User=nobody # Або інший непривілейований користувач
Group=nogroup # Або інша група
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node $START_SCRIPT
# Якщо використовується ts-node:
# ExecStart=/usr/bin/npm run start # Або конкретна команда для запуску з ts-node, наприклад:
# ExecStart=$APP_DIR/node_modules/.bin/ts-node $START_SCRIPT
# Або якщо npx встановлено глобально:
# ExecStart=/usr/bin/npx ts-node $START_SCRIPT

Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOL

# Якщо потрібен ts-node, модифікуємо ExecStart
if [[ "$PRE_EXEC" == "npx ts-node" ]]; then
    # Перевіряємо, чи є команда start в package.json
    if jq -e '.scripts.start' "$APP_DIR/package.json" > /dev/null; then
        EXEC_START_CMD="/usr/bin/npm run start"
    else
        # Шукаємо ts-node в локальних node_modules або використовуємо npx
        TS_NODE_PATH="$APP_DIR/node_modules/.bin/ts-node"
        if [ -f "$TS_NODE_PATH" ]; then
            EXEC_START_CMD="$TS_NODE_PATH $START_SCRIPT"
        else
            # Перевірка, чи встановлено npx
            if ! command -v npx &> /dev/null; then
                log "npx не встановлено. Встановлюємо npx (частина npm)..."
                apt-get install -y npm # npm зазвичай включає npx
            fi
            EXEC_START_CMD="/usr/bin/npx ts-node $START_SCRIPT"
        fi
    fi
    sed -i "s|ExecStart=.*|ExecStart=$EXEC_START_CMD|" "$SERVICE_FILE"
    log "Оновлено ExecStart для ts-node: $EXEC_START_CMD"
fi


log "Systemd service file $SERVICE_FILE створено:"
cat "$SERVICE_FILE"

log "Перезавантаження конфігурації systemd, включення та запуск сервісу $SERVICE_NAME..."
systemctl daemon-reload || error_exit "Не вдалося виконати daemon-reload."
systemctl enable "${SERVICE_NAME}.service" || error_exit "Не вдалося включити сервіс $SERVICE_NAME."
systemctl restart "${SERVICE_NAME}.service" || log "ПОПЕРЕДЖЕННЯ: Не вдалося негайно запустити сервіс $SERVICE_NAME. Перевірте логи: journalctl -u $SERVICE_NAME -f"

# Перевірка статусу сервісу
sleep 5 # Даємо час сервісу запуститися
if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    log "Сервіс $SERVICE_NAME успішно запущено та активний."
else
    log "ПОПЕРЕДЖЕННЯ: Сервіс $SERVICE_NAME не активний після запуску. Перевірте логи:"
    log "sudo journalctl -u $SERVICE_NAME -n 50 --no-pager"
fi

log "Розгортання Document Scanner Service завершено."
log "Рекомендується запустити /opt/scripts/test_remote_connections.sh для перевірки з'єднань."
log "Для перегляду логів сервісу: sudo journalctl -u $SERVICE_NAME -f"

exit 0

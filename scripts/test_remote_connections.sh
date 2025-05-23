#!/bin/bash
# test_remote_connections.sh - Скрипт для тестування з''єднання з віддаленими сервісами
# Використання: ./test_remote_connections.sh <remote_mssql_host> <remote_ollama_host> <remote_openwebui_host> [mssql_user] [mssql_password] [mssql_db]

set -e # Вихід при першій помилці

# Функція для логування
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [TEST_CONN] $1"
}

# Функція для виводу помилки (але не виходу, щоб продовжити інші тести)
log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [TEST_CONN] ПОМИЛКА: $1" >&2
}

# Функція для завантаження змінних з .env файлу
load_env_file() {
    local env_file="$1"
    log "Завантаження змінних із файлу $env_file"
    
    if [ ! -f "$env_file" ]; then
        log_error "Файл .env не знайдено: $env_file"
        return 1
    fi
    
    # Завантажуємо змінні з .env файлу
    set -a  # автоматично експортувати змінні
    # Пропускаємо рядки з коментарями та порожні рядки
    source <(grep -v '^#' "$env_file" | grep -v '^\s*$')
    set +a
    
    log "Змінні успішно завантажено з $env_file"
    return 0
}

# Спочатку спробуємо завантажити дані з .env файлу 
ENV_LOADED=false

# Перевіряємо можливі шляхи до .env
ENV_FILE="${1:-}"

# Якщо ENV_FILE вказано і це файл .env
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    load_env_file "$ENV_FILE" && ENV_LOADED=true
    shift # зсуваємо параметри, якщо перший був шляхом до .env
elif [ -f "/opt/document-scanner-service/.env" ]; then
    load_env_file "/opt/document-scanner-service/.env" && ENV_LOADED=true
elif [ -f "./env" ]; then
    load_env_file "./env" && ENV_LOADED=true
elif [ -f "$(dirname "$0")/.env" ]; then
    load_env_file "$(dirname "$0")/.env" && ENV_LOADED=true
elif [ -f "$(dirname "$0")/../.env" ]; then
    load_env_file "$(dirname "$0")/../.env" && ENV_LOADED=true
fi

# Якщо змінні не завантажені з .env, використовуємо параметри командного рядка
if [ "$ENV_LOADED" = false ]; then
    log "Файл .env не знайдено, використовуємо параметри командного рядка"
    MSSQL_HOST=${1}
    OLLAMA_HOST=${2} # Очікується тільки хостнейм/IP, порт буде :11434
    OPENWEBUI_HOST=${3} # Очікується тільки хостнейм/IP, порт буде :8080
    MSSQL_USER=${4:-sa}
    MSSQL_PASSWORD=${5:-YourPassword123!} # Пароль за замовчуванням, якщо не передано
    MSSQL_DB_NAME=${6:-DocumentDB} # База даних за замовчуванням
else
    # Якщо .env завантажено, але параметри командного рядка вказані, вони мають пріоритет
    [ -n "${1:-}" ] && MSSQL_HOST="$1"
    [ -n "${2:-}" ] && OLLAMA_HOST="$2"
    [ -n "${3:-}" ] && OPENWEBUI_HOST="$3"
    [ -n "${4:-}" ] && MSSQL_USER="$4"
    [ -n "${5:-}" ] && MSSQL_PASSWORD="$5"
    [ -n "${6:-}" ] && MSSQL_DB_NAME="$6" 
    
    # Мапуємо змінні з .env формату до формату скрипту, якщо вони не встановлені
    [ -z "${MSSQL_HOST:-}" ] && [ -n "${DB_SERVER:-}" ] && MSSQL_HOST="$DB_SERVER"
    [ -z "${OLLAMA_HOST:-}" ] && [ -n "${OLLAMA_URL:-}" ] && OLLAMA_HOST="$(echo "$OLLAMA_URL" | sed -E 's/https?:\/\///')"
    [ -z "${OPENWEBUI_HOST:-}" ] && [ -n "${OPENWEBUI_URL:-}" ] && OPENWEBUI_HOST="$(echo "$OPENWEBUI_URL" | sed -E 's/https?:\/\///')"
    [ -z "${MSSQL_USER:-}" ] && [ -n "${DB_USER:-}" ] && MSSQL_USER="$DB_USER"
    [ -z "${MSSQL_PASSWORD:-}" ] && [ -n "${DB_PASSWORD:-}" ] && MSSQL_PASSWORD="$DB_PASSWORD"
    [ -z "${MSSQL_DB_NAME:-}" ] && [ -n "${DB_NAME:-}" ] && MSSQL_DB_NAME="$DB_NAME"
fi

# Перевірка обов'язкових параметрів
if [ -z "$MSSQL_HOST" ] || [ -z "$OLLAMA_HOST" ] || [ -z "$OPENWEBUI_HOST" ]; then
    log_error "Не вказані всі обов'язкові хости: MSSQL_HOST, OLLAMA_HOST, OPENWEBUI_HOST"
    echo "Використання: $0 [шлях_до_env_файлу] або $0 <remote_mssql_host> <remote_ollama_host> <remote_openwebui_host> [mssql_user] [mssql_password] [mssql_db]"
    exit 1
fi

log "Тестування з''єднання з віддаленими сервісами:"
log "- MSSQL Host: $MSSQL_HOST, User: $MSSQL_USER, DB: $MSSQL_DB_NAME"
log "- Ollama Host: $OLLAMA_HOST (порт 11434)"
log "- OpenWebUI Host: $OPENWEBUI_HOST (порт 8080)"
echo "" # Порожній рядок для кращої читабельності

ERRORS_COUNT=0

# Тест MSSQL з'єднання
test_mssql() {
    log "Тестування з''єднання з MSSQL ($MSSQL_HOST)..."
    
    # Встановлення утиліт для тестування, якщо потрібно
    if ! command -v sqlcmd &> /dev/null; then
        log "Встановлення mssql-tools..."
        # Додавання репозиторію Microsoft (приклад для Debian/Ubuntu)
        # Перевірте актуальність інструкцій для вашого дистрибутива
        curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
        OS_VERSION=$(lsb_release -rs | cut -d. -f1) # 11 для Bullseye, 12 для Bookworm
        if [[ "$OS_VERSION" == "11" || "$OS_VERSION" == "12" ]]; then
             curl "https://packages.microsoft.com/config/debian/$OS_VERSION/prod.list" | tee /etc/apt/sources.list.d/mssql-release.list > /dev/null
        else
            log_error "Непідтримувана версія Debian/Ubuntu для автоматичного встановлення mssql-tools. Спробуйте встановити вручну."
            return 1
        fi
       
        apt-get update -y
        ACCEPT_EULA=Y apt-get install -y mssql-tools unixodbc-dev
        # Додавання до PATH (може потребувати перезапуску сесії або source ~/.bashrc)
        if ! grep -q '/opt/mssql-tools/bin' ~/.bashrc; then
            echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
            log "Додано /opt/mssql-tools/bin до PATH в ~/.bashrc. Перезапустіть термінал або виконайте 'source ~/.bashrc'."
        fi
        export PATH="$PATH:/opt/mssql-tools/bin" # Для поточної сесії
    fi
    
    # Тест з'єднання
    if sqlcmd -S "$MSSQL_HOST" -U "$MSSQL_USER" -P "$MSSQL_PASSWORD" -Q "SELECT @@VERSION" -W -h-1 -b -t 5 > /dev/null 2>&1; then
        log "✅ З''єднання з MSSQL ($MSSQL_HOST) успішне!"
        VERSION_INFO=$(sqlcmd -S "$MSSQL_HOST" -U "$MSSQL_USER" -P "$MSSQL_PASSWORD" -Q "SELECT @@VERSION" -W -h-1 -b -t 5 | head -n 1)
        log "   Версія MSSQL: $VERSION_INFO"
    else
        log_error "❌ Помилка з''єднання з MSSQL сервером $MSSQL_HOST. Перевірте хост, порт, логін, пароль та налаштування мережі/брандмауера."
        return 1
    fi
    
    # Перевірка наявності бази даних
    # Використовуємо IF EXISTS для уникнення помилки, якщо БД не існує
    QUERY_CHECK_DB="IF DB_ID('$MSSQL_DB_NAME') IS NOT NULL SELECT 'Exists' ELSE SELECT 'Not Exists'"
    DB_EXISTS_RESULT=$(sqlcmd -S "$MSSQL_HOST" -U "$MSSQL_USER" -P "$MSSQL_PASSWORD" -Q "$QUERY_CHECK_DB" -W -h-1 -b -t 5)

    if [[ "$DB_EXISTS_RESULT" == "Exists" ]]; then
        log "✅ База даних '$MSSQL_DB_NAME' існує на сервері $MSSQL_HOST."
    else
        log "⚠️ База даних '$MSSQL_DB_NAME' НЕ існує на сервері $MSSQL_HOST."
        # Можна додати логіку створення, якщо потрібно, але для тесту це може бути зайвим
        # log "   Спроба створення бази даних '$MSSQL_DB_NAME'..."
        # if sqlcmd -S "$MSSQL_HOST" -U "$MSSQL_USER" -P "$MSSQL_PASSWORD" -Q "CREATE DATABASE [$MSSQL_DB_NAME]" -W -h-1 -b -t 10 > /dev/null 2>&1; then
        #     log "   ✅ База даних '$MSSQL_DB_NAME' успішно створена."
        # else
        #     log_error "   ❌ Не вдалося створити базу даних '$MSSQL_DB_NAME'."
        #     return 1
        # fi
    fi
    
    return 0
}

# Тест Ollama з'єднання
test_ollama() {
    OLLAMA_API_URL="http://$OLLAMA_HOST:11434"
    log "Тестування з''єднання з Ollama ($OLLAMA_API_URL)..."
    
    # Перевірка доступності API
    if curl -s --connect-timeout 5 "${OLLAMA_API_URL}/api/tags" > /tmp/ollama_tags.json; then
        log "✅ З''єднання з Ollama API ($OLLAMA_API_URL) успішне!"
        
        # Отримання списку моделей
        log "   Доступні моделі в Ollama:"
        if command -v jq &> /dev/null; then
            jq -r '.models[].name' /tmp/ollama_tags.json | sed 's/^/     - /' || log "     Не вдалося розпарсити моделі за допомогою jq."
        else
            log "     (jq не встановлено, неможливо вивести список моделей красиво)"
            cat /tmp/ollama_tags.json
        fi
        
        # Перевірка наявності необхідних моделей
        REQUIRED_MODELS=("llama3.2" "nomic-embed-text") # Моделі, які використовуються сервісом
        ALL_MODELS_FOUND=true
        for MODEL in "${REQUIRED_MODELS[@]}"; do
            if jq -e --arg m "$MODEL" '.models[] | select(.name == $m or .name == ($m + ":latest"))' /tmp/ollama_tags.json > /dev/null; then
                log "   ✅ Необхідна модель '$MODEL' знайдена в Ollama."
            else
                log "   ⚠️ Необхідна модель '$MODEL' НЕ знайдена в Ollama! Її потрібно буде завантажити (pull) в Ollama."
                ALL_MODELS_FOUND=false
            fi
        done
        if [ "$ALL_MODELS_FOUND" = false ]; then
             return 1 # Повертаємо помилку, якщо не всі моделі знайдені
        fi
    else
        log_error "❌ Помилка з''єднання з Ollama API ($OLLAMA_API_URL). Перевірте, чи Ollama запущено, доступний по мережі та порт 11434 відкритий."
        return 1
    fi
    rm -f /tmp/ollama_tags.json
    return 0
}

# Тест OpenWebUI з'єднання
test_openwebui() {
    OPENWEBUI_URL="http://$OPENWEBUI_HOST:8080"
    log "Тестування з''єднання з OpenWebUI ($OPENWEBUI_URL)..."
    
    # Перевірка доступності веб-інтерфейсу (простий GET запит)
    # OpenWebUI може не мати простого /api/status, тому перевіряємо головну сторінку
    if curl -s --connect-timeout 5 -L "$OPENWEBUI_URL" -o /dev/null -w "%{http_code}" | grep -q "200"; then
        log "✅ З''єднання з OpenWebUI ($OPENWEBUI_URL) успішне (отримано HTTP 200)."
    else
        HTTP_CODE=$(curl -s --connect-timeout 5 -L "$OPENWEBUI_URL" -o /dev/null -w "%{http_code}")
        log_error "❌ Помилка з''єднання з OpenWebUI ($OPENWEBUI_URL). Отримано HTTP код: $HTTP_CODE. Перевірте, чи OpenWebUI запущено, доступний по мережі та порт 8080 відкритий."
        return 1
    fi
    
    return 0
}

# Головна функція
main() {
    # Тестування MSSQL
    if test_mssql; then
        log "✅ MSSQL тести пройдено успішно."
    else
        log_error "❌ MSSQL тести провалено."
        ((ERRORS_COUNT++))
    fi
    echo ""
    
    # Тестування Ollama
    if test_ollama; then
        log "✅ Ollama тести пройдено успішно."
    else
        log_error "❌ Ollama тести провалено."
        ((ERRORS_COUNT++))
    fi
    echo ""
    
    # Тестування OpenWebUI
    if test_openwebui; then
        log "✅ OpenWebUI тести пройдено успішно."
    else
        log_error "❌ OpenWebUI тести провалено."
        ((ERRORS_COUNT++))
    fi
    echo ""
    
    log "======================================================"
    
    if [ $ERRORS_COUNT -eq 0 ]; then
        log "✅ Всі тести з''єднання пройдені успішно!"
        log "   Можна продовжувати розгортання сервісу."
    else
        log_error "⚠️ Виявлено $ERRORS_COUNT помилок у тестах з''єднання."
        log_error "   Будь ласка, виправте проблеми перед продовженням розгортання."
        log "======================================================"
        exit 1 # Вихід з кодом помилки, якщо є проблеми
    fi
    
    log "======================================================"
    exit 0
}

# Запуск скрипту
main "$@"

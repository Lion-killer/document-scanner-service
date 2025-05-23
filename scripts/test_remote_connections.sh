#!/bin/bash
# test_remote_connections.sh - Скрипт для тестування з''єднання з віддаленими сервісами
# Використання: ./test_remote_connections.sh <qdrant_url> <remote_ollama_host> <remote_openwebui_host>

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
    QDRANT_URL=${1}
    OLLAMA_HOST=${2} # Очікується тільки хостнейм/IP, порт буде :11434
    OPENWEBUI_HOST=${3} # Очікується тільки хостнейм/IP, порт буде :8080
else
    # Якщо .env завантажено, але параметри командного рядка вказані, вони мають пріоритет
    [ -n "${1:-}" ] && QDRANT_URL="$1"
    [ -n "${2:-}" ] && OLLAMA_HOST="$2"
    [ -n "${3:-}" ] && OPENWEBUI_HOST="$3"
    
    # Мапуємо змінні з .env формату до формату скрипту, якщо вони не встановлені
    [ -z "${QDRANT_URL:-}" ] && [ -n "${DB_URL:-}" ] && QDRANT_URL="$DB_URL"
    [ -z "${OLLAMA_HOST:-}" ] && [ -n "${OLLAMA_URL:-}" ] && OLLAMA_HOST="$(echo "$OLLAMA_URL" | sed -E 's/https?:\/\///')"
    [ -z "${OPENWEBUI_HOST:-}" ] && [ -n "${OPENWEBUI_URL:-}" ] && OPENWEBUI_HOST="$(echo "$OPENWEBUI_URL" | sed -E 's/https?:\/\///')"
fi

# Перевірка обов'язкових параметрів
if [ -z "$QDRANT_URL" ] || [ -z "$OLLAMA_HOST" ] || [ -z "$OPENWEBUI_HOST" ]; then
    log_error "Не вказані всі обов'язкові параметри: QDRANT_URL, OLLAMA_HOST, OPENWEBUI_HOST"
    echo "Використання: $0 [шлях_до_env_файлу] або $0 <qdrant_url> <remote_ollama_host> <remote_openwebui_host>"
    exit 1
fi

log "Тестування з''єднання з віддаленими сервісами:"
log "- Qdrant URL: $QDRANT_URL"
log "- Ollama Host: $OLLAMA_HOST (порт 11434)"
log "- OpenWebUI Host: $OPENWEBUI_HOST (порт 8080)"
echo "" # Порожній рядок для кращої читабельності

ERRORS_COUNT=0

# Тест Qdrant з'єднання
test_qdrant() {
    log "Тестування з''єднання з Qdrant ($QDRANT_URL)..."
    
    # Встановлення утиліт для тестування, якщо потрібно
    if ! command -v curl &> /dev/null; then
        log "Встановлення curl..."
        apt-get update -y
        apt-get install -y curl
    fi
    
    # Тест з'єднання - перевіримо доступність API
    QDRANT_API_URL="$(echo $QDRANT_URL | sed 's/\/$//')/collections"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$QDRANT_API_URL")
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        log "✅ З''єднання з Qdrant ($QDRANT_URL) успішне!"
        
        # Отримаємо інформацію про версію Qdrant
        VERSION_INFO=$(curl -s "$QDRANT_URL" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$VERSION_INFO" ]]; then
            log "   Версія Qdrant: $VERSION_INFO"
        else
            log "   Не вдалося отримати інформацію про версію Qdrant"
        fi
        
        # Перевіримо існуючі колекції
        COLLECTIONS=$(curl -s "$QDRANT_API_URL" | grep -o '"collections":\[.*\]' || echo "Немає колекцій")
        log "   Існуючі колекції: $COLLECTIONS"
        
        # Перевіримо, чи існують необхідні колекції
        if [[ "$COLLECTIONS" == *"documents"* ]]; then
            log "   ✅ Колекція 'documents' існує."
        else
            log "   ⚠️ Колекція 'documents' не існує. Вона буде створена при першому запуску."
        fi
        
        if [[ "$COLLECTIONS" == *"document_chunks"* ]]; then
            log "   ✅ Колекція 'document_chunks' існує."
        else
            log "   ⚠️ Колекція 'document_chunks' не існує. Вона буде створена при першому запуску."
        fi
    else
        log_error "❌ Помилка з''єднання з Qdrant сервером $QDRANT_URL. Код відповіді: $HTTP_CODE. Перевірте URL та налаштування мережі/брандмауера."
        return 1
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
    # Тестування Qdrant
    if test_qdrant; then
        log "✅ Qdrant тести пройдено успішно."
    else
        log_error "❌ Qdrant тести провалено."
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

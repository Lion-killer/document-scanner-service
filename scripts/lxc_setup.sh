#!/bin/bash
# lxc_setup.sh - Скрипт для створення та базового налаштування LXC контейнера на Debian

# Функція для логування
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [LXC_SETUP] $1"
}

# Функція для виводу помилки та виходу
error_exit() {
    log "ПОМИЛКА: $1" >&2
    exit 1
}

# Перевірка наявності LXC
if ! command -v lxc-create &> /dev/null; then
    error_exit "LXC не встановлено. Будь ласка, встановіть LXC та спробуйте знову."
fi

# Функція для завантаження змінних з .env файлу
load_env_file() {
    local env_file="$1"
    log "Завантаження змінних із файлу $env_file"
    
    if [ ! -f "$env_file" ]; then
        log "Файл .env не знайдено: $env_file"
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

# Спочатку перевіряємо, чи перший параметр - це шлях до файлу .env
if [ -n "${1:-}" ] && [ -f "$1" ] && [[ "$1" == *.env ]]; then
    load_env_file "$1"
    shift  # Зсуваємо параметри, якщо перший був шляхом до .env
# Шукаємо .env у стандартних місцях
elif [ -f "./env" ]; then
    load_env_file "./env"
elif [ -f "$(dirname "$0")/.env" ]; then
    load_env_file "$(dirname "$0")/.env"
elif [ -f "$(dirname "$0")/../.env" ]; then
    load_env_file "$(dirname "$0")/../.env"
fi

# Параметри
CONTAINER_NAME=${1:-${LXC_CONTAINER_NAME:-doc-scanner-lxc}}
DEBIAN_RELEASE=${2:-${LXC_DEBIAN_RELEASE:-bullseye}} # або bookworm, buster тощо

log "Початок створення LXC контейнера: $CONTAINER_NAME ($DEBIAN_RELEASE)"

# Перевірка, чи контейнер вже існує
if lxc-ls | grep -q "^${CONTAINER_NAME}$"; then
    log "Контейнер $CONTAINER_NAME вже існує."
    # Запитуємо користувача, чи хоче він його перезаписати
    read -p "Контейнер $CONTAINER_NAME вже існує. Видалити та створити заново? (y/N): " choice
    case "$choice" in
      y|Y ) 
        log "Видалення існуючого контейнера $CONTAINER_NAME..."
        lxc-stop -n "$CONTAINER_NAME" --timeout 60 || log "Не вдалося зупинити контейнер (можливо, вже зупинений)."
        lxc-destroy -n "$CONTAINER_NAME" || error_exit "Не вдалося видалити контейнер $CONTAINER_NAME."
        log "Існуючий контейнер $CONTAINER_NAME видалено."
        ;;
      * ) 
        log "Створення контейнера скасовано користувачем."
        exit 0
        ;;
    esac
fi

# Створення контейнера
log "Створення контейнера $CONTAINER_NAME з образом Debian $DEBIAN_RELEASE..."
lxc-create -t debian -n "$CONTAINER_NAME" -- -r "$DEBIAN_RELEASE" || error_exit "Не вдалося створити контейнер $CONTAINER_NAME."

log "Контейнер $CONTAINER_NAME успішно створено."

# Запуск контейнера
log "Запуск контейнера $CONTAINER_NAME..."
lxc-start -n "$CONTAINER_NAME" -d || error_exit "Не вдалося запустити контейнер $CONTAINER_NAME."

# Очікування запуску контейнера та мережі
log "Очікування стабілізації мережі в контейнері (до 30 секунд)..."
MAX_RETRIES=15
RETRY_COUNT=0
while ! lxc-attach -n "$CONTAINER_NAME" -- ping -c 1 -W 2 google.com &> /dev/null; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
        log "ПОПЕРЕДЖЕННЯ: Не вдалося перевірити доступ до Інтернету з контейнера $CONTAINER_NAME. Продовжуємо..."
        break
    fi
    sleep 2
done
if [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; then
    log "Мережа в контейнері $CONTAINER_NAME активна."
fi

# Встановлення базових пакетів всередині контейнера
log "Встановлення базових пакетів (sudo, curl, gnupg, git, apt-transport-https, ca-certificates) в контейнері $CONTAINER_NAME..."
lxc-attach -n "$CONTAINER_NAME" -- apt-get update -y || log "Помилка при apt-get update в контейнері."
lxc-attach -n "$CONTAINER_NAME" -- apt-get install -y sudo curl gnupg git apt-transport-https ca-certificates || error_exit "Не вдалося встановити базові пакети в контейнері."

# Створення директорії для скриптів розгортання
log "Створення директорії /opt/scripts в контейнері..."
lxc-attach -n "$CONTAINER_NAME" -- mkdir -p /opt/scripts

# Копіювання скриптів розгортання в контейнер
SCRIPT_DIR=$(dirname "$(realpath "$0")") # Директорія, де знаходиться lxc_setup.sh

for script_name in lxc_deployment.sh test_remote_connections.sh lxc_smb_mount.sh; do
    if [ -f "$SCRIPT_DIR/$script_name" ]; then
        log "Копіювання $script_name в контейнер $CONTAINER_NAME:/opt/scripts/"
        cp "$SCRIPT_DIR/$script_name" "/var/lib/lxc/$CONTAINER_NAME/rootfs/opt/scripts/$script_name"
        lxc-attach -n "$CONTAINER_NAME" -- chmod +x "/opt/scripts/$script_name"
    else
        log "ПОПЕРЕДЖЕННЯ: Скрипт $script_name не знайдено в $SCRIPT_DIR. Пропускаємо копіювання."
    fi
done

log "Базове налаштування контейнера $CONTAINER_NAME завершено."
log "IP-адреса контейнера:"
lxc-info -n "$CONTAINER_NAME" -iH
log "Для доступу до консолі контейнера виконайте: lxc-attach -n $CONTAINER_NAME"
log "Не забудьте скопіювати вихідний код вашого проекту в /opt/document-scanner-service всередині контейнера."

exit 0

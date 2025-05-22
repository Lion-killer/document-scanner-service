#!/bin/bash
# lxc_smb_mount.sh - Скрипт для монтування SMB/CIFS ресурсу всередині LXC контейнера

# Функція для логування
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SMB_MOUNT] $1"
}

# Функція для виводу помилки та виходу
error_exit() {
    log "ПОМИЛКА: $1" >&2
    exit 1
}

# Перевірка запуску від імені root
if [ "$(id -u)" -ne 0 ]; then
  error_exit "Цей скрипт потрібно запускати з правами root (sudo)."
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
elif [ -f /opt/document-scanner-service/.env ]; then
    load_env_file "/opt/document-scanner-service/.env"
elif [ -f "./env" ]; then
    load_env_file "./env"
elif [ -f "$(dirname "$0")/.env" ]; then
    load_env_file "$(dirname "$0")/.env"
elif [ -f "$(dirname "$0")/../.env" ]; then
    load_env_file "$(dirname "$0")/../.env"
fi

# Параметри
SMB_SERVER_SHARE=${1:-$SMB_SERVER/$SMB_SHARE} # Повний шлях, наприклад //192.168.1.100/share або smb://server/share
SMB_MOUNT_POINT=${2:-$SMB_MOUNT_POINT}
SMB_USER=${3:-$SMB_USER}
SMB_PASSWORD=${4:-$SMB_PASSWORD}
SMB_DOMAIN=${5:-WORKGROUP} # Опціональний параметр домену

# Перевірка обов'язкових параметрів
if [ -z "$SMB_SERVER_SHARE" ] || [ -z "$SMB_MOUNT_POINT" ] || [ -z "$SMB_USER" ] || [ -z "$SMB_PASSWORD" ]; then
    error_exit "Не вказані всі обов'язкові параметри: SMB_SERVER_SHARE, SMB_MOUNT_POINT, SMB_USER, SMB_PASSWORD"
fi

log "Початок налаштування SMB монтування."
log "Ресурс: $SMB_SERVER_SHARE"
log "Точка монтування: $SMB_MOUNT_POINT"
log "Користувач: $SMB_USER"

# 1. Встановлення cifs-utils, якщо ще не встановлено
if ! command -v mount.cifs &> /dev/null; then
    log "Встановлення cifs-utils..."
    apt-get update -y || error_exit "Не вдалося оновити пакети."
    apt-get install -y cifs-utils || error_exit "Не вдалося встановити cifs-utils."
fi

# 2. Створення точки монтування, якщо вона не існує
if [ ! -d "$SMB_MOUNT_POINT" ]; then
    log "Створення точки монтування $SMB_MOUNT_POINT..."
    mkdir -p "$SMB_MOUNT_POINT" || error_exit "Не вдалося створити точку монтування $SMB_MOUNT_POINT."
fi

# 3. Створення файлу з обліковими даними
CRED_DIR="/etc/samba/credentials"
mkdir -p "$CRED_DIR"
# Генеруємо унікальне ім'я для файлу облікових даних на основі шляху монтування
SANITIZED_MOUNT_POINT=$(echo "$SMB_MOUNT_POINT" | sed 's/[^a-zA-Z0-9]/_/g')
CRED_FILE="$CRED_DIR/${SANITIZED_MOUNT_POINT}.cred"

log "Створення файлу облікових даних $CRED_FILE..."
cat > "$CRED_FILE" <<EOL
username=$SMB_USER
password=$SMB_PASSWORD
domain=$SMB_DOMAIN
EOL
chmod 600 "$CRED_FILE" || error_exit "Не вдалося встановити права на файл $CRED_FILE."

# 4. Додавання запису в /etc/fstab для автоматичного монтування
FSTAB_ENTRY="$SMB_SERVER_SHARE $SMB_MOUNT_POINT cifs credentials=$CRED_FILE,iocharset=utf8,gid=$(id -g nobody),uid=$(id -u nobody),file_mode=0664,dir_mode=0775,vers=3.0,_netdev 0 0"
# vers=3.0 - можна спробувати 2.1 або 1.0, якщо є проблеми
# _netdev - для очікування мережі перед монтуванням

# Перевірка, чи запис вже існує
if grep -qF "$SMB_MOUNT_POINT" /etc/fstab; then
    log "Запис для $SMB_MOUNT_POINT вже існує в /etc/fstab. Оновлюємо..."
    # Видаляємо старий запис (простий варіант, може бути неідеальним для складних fstab)
    sed -i.bak "\|$SMB_MOUNT_POINT|d" /etc/fstab
fi

log "Додавання запису в /etc/fstab..."
echo "$FSTAB_ENTRY" >> /etc/fstab
log "Запис в /etc/fstab додано/оновлено:"
grep "$SMB_MOUNT_POINT" /etc/fstab

# 5. Спроба монтування
log "Спроба змонтувати $SMB_MOUNT_POINT..."
# Розмонтовуємо, якщо вже змонтовано (щоб застосувати нові налаштування з fstab)
if mount | grep -q "$SMB_MOUNT_POINT"; then
    log "Ресурс вже змонтовано в $SMB_MOUNT_POINT. Розмонтовуємо для перемонтажу..."
    umount "$SMB_MOUNT_POINT" || log "Попередження: не вдалося розмонтувати $SMB_MOUNT_POINT. Можливо, він використовується."
fi

mount "$SMB_MOUNT_POINT"
# Або mount -a для перевірки всіх записів з fstab

if mount | grep -q "$SMB_MOUNT_POINT"; then
    log "✅ SMB ресурс $SMB_SERVER_SHARE успішно змонтовано в $SMB_MOUNT_POINT."

    # Оновлення конфігурації сервісу в .env, якщо файл існує
    APP_ENV_FILE="/opt/document-scanner-service/.env"
    if [ -f "$APP_ENV_FILE" ]; then
        log "Оновлення SMB_PATH та SMB_MOUNT_POINT в $APP_ENV_FILE на $SMB_MOUNT_POINT..."
        
        # Перевірка, чи існують вже змінні SMB_PATH та SMB_MOUNT_POINT в .env
        if grep -q "SMB_PATH=" "$APP_ENV_FILE"; then
            # Якщо змінні існують, оновлюємо їх значення
            sed -i "s|SMB_PATH=.*|SMB_PATH=$SMB_MOUNT_POINT|" "$APP_ENV_FILE"
            sed -i "s|SMB_MOUNT_POINT=.*|SMB_MOUNT_POINT=$SMB_MOUNT_POINT|" "$APP_ENV_FILE"
        else
            # Якщо змінних немає, додаємо їх в кінець файлу
            echo "" >> "$APP_ENV_FILE"
            echo "# Оновлені параметри SMB" >> "$APP_ENV_FILE"
            echo "SMB_PATH=$SMB_MOUNT_POINT" >> "$APP_ENV_FILE"
            echo "SMB_MOUNT_POINT=$SMB_MOUNT_POINT" >> "$APP_ENV_FILE"
        fi
        
        log "SMB_PATH та SMB_MOUNT_POINT в $APP_ENV_FILE оновлено."
    else
        log "ПОПЕРЕДЖЕННЯ: Файл конфігурації $APP_ENV_FILE не знайдено. Шлях SMB не буде оновлено автоматично."
    fi
else
    error_exit "Не вдалося змонтувати SMB ресурс. Перевірте облікові дані, шлях до ресурсу, доступність сервера та логи системи (dmesg, journalctl)."
fi

log "Налаштування SMB монтування завершено."
exit 0

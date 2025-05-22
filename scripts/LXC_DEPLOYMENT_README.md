# Інструкція з розгортання Document Scanner Service у LXC (Proxmox)

Цей посібник пояснює, як розгорнути Document Scanner Service у контейнері LXC на основі Debian у середовищі Proxmox. Передбачається, що **MSSQL Server, Ollama та OpenWebUI вже розгорнуті й доступні як окремі сервіси**.

## Необхідні умови

1.  **Proxmox LXC-хост:** Сервер Proxmox із налаштованим LXC (контейнеризація має бути активована).
2.  **Зовнішні сервіси:**
    *   **MSSQL Server:** Має бути доступний з контейнера LXC. Потрібні: хост/IP, порт (за замовчуванням 1433), ім'я користувача, пароль і назва бази даних.
    *   **Ollama Service:** Має бути доступний з контейнера LXC. Потрібна базова URL-адреса (наприклад, `http://<ollama-host>:11434`). Переконайтеся, що потрібні моделі (`llama3.2`, `nomic-embed-text`) доступні на цьому екземплярі Ollama.
    *   **OpenWebUI Service:** Має бути доступний з контейнера LXC. Потрібна базова URL-адреса (наприклад, `http://<openwebui-host>:8080`).
3.  **Файли проекту:** Файли проекту `document-scanner-service`, включаючи директорію `scripts`.
4.  **Git:** Встановлений git у контейнері або на Proxmox-хості, якщо плануєте клонувати репозиторій напряму.

## Кроки розгортання

### Крок 1: Підготовка Proxmox та скриптів

1.  Створіть LXC-контейнер через веб-інтерфейс Proxmox або за допомогою CLI. Рекомендується використовувати Debian (наприклад, шаблон Debian 12).
2.  Встановіть у контейнері базові утиліти (`sudo`, `curl`, `git` тощо) та Node.js (або використовуйте скрипти для автоматизації).
3.  Переконайтеся, що всі скрипти у директорії `scripts` (`lxc_setup.sh`, `lxc_deployment.sh`, `test_remote_connections.sh`, `lxc_smb_mount.sh`) мають права на виконання:
    ```bash
    chmod +x scripts/*.sh
    ```
4.  Скопіюйте проект у контейнер (наприклад, через SCP, git clone або Proxmox Console).

### Крок 2: Створення LXC-контейнера (якщо не зроблено через Proxmox)

Якщо ви не створювали контейнер через веб-інтерфейс Proxmox, можна скористатися CLI:
```bash
pct create <VMID> local:vztmpl/debian-12-standard_*.tar.zst --cores 2 --memory 2048 --net0 name=eth0,bridge=vmbr0,ip=dhcp --rootfs local-lvm:8 --unprivileged 1 --features nesting=1
pct start <VMID>
pct exec <VMID> -- /bin/bash
```

### Крок 3: Розгортання сервісу у LXC-контейнері

1.  Увійдіть у контейнер через Proxmox Console або SSH:
    ```bash
    pct enter <VMID>
    # або через веб-консоль Proxmox
    ```
2.  Перейдіть у директорію скриптів:
    ```bash
    cd /opt/scripts
    ```
3.  Запустіть скрипт `lxc_deployment.sh`, вказавши параметри підключення до зовнішніх сервісів.

    **Приклад:**
    ```bash
    sudo ./lxc_deployment.sh \
        --mssql-host "ip_або_хост_mssql" \
        --mssql-user "користувач_mssql" \
        --mssql-pass "пароль_mssql" \
        --mssql-db "DocumentDB" \
        --ollama-url "http://ip_ollama:11434" \
        --openwebui-url "http://ip_openwebui:8080" \
        --project-source "/шлях/до/document-scanner-service" # або git URL
        # Додатково для SMB:
        # --smb-server "//smb-сервер/шар" \
        # --smb-mount "/mnt/smb_share" \
        # --smb-user "користувач_smb" \
        # --smb-pass "пароль_smb"
    ```
    *   Замініть приклади на свої дані.
    *   `--project-source` може бути локальним шляхом у контейнері або git-репозиторієм.

    Скрипт виконає:
    *   Встановлення Node.js, npm та залежностей (якщо потрібно).
    *   Копіювання/отримання коду застосунку у `/opt/document-scanner-service`.    *   Встановлення залежностей проекту (`npm install`).
    *   Збірку проекту, якщо це TypeScript (`npm run build`).
    *   Генерацію `/opt/document-scanner-service/.env` з параметрами підключення.
    *   Налаштування та запуск systemd-сервісу (`document-scanner.service`).
    *   (Опціонально) Монтування SMB-шару, якщо вказані параметри.

### Крок 4: Тестування підключень до зовнішніх сервісів

Після розгортання, перебуваючи у контейнері, запустіть скрипт `test_remote_connections.sh` для перевірки підключень:

```bash
sudo /opt/scripts/test_remote_connections.sh \
    --mssql-host "ip_або_хост_mssql" \
    --mssql-user "користувач_mssql" \
    --mssql-pass "пароль_mssql" \
    --mssql-db "DocumentDB" \
    --ollama-host "ip_ollama" \ # лише хост/IP
    --openwebui-host "ip_openwebui" # лише хост/IP
```
Скрипт перевірить:
*   Підключення до MSSQL та наявність бази даних.
*   Доступність Ollama API та наявність потрібних моделей.
*   Доступність OpenWebUI.

### Крок 5: (Опціонально) Керування SMB-шаром

*   Скрипт `lxc_smb_mount.sh` викликається з `lxc_deployment.sh`, якщо вказані параметри SMB.
*   Для ручного демонтування використовуйте стандартні команди Linux, наприклад: `sudo umount /mnt/smb_share`.

## Керування сервісом (у контейнері)

Після розгортання керуйте сервісом `document-scanner.service` через systemctl:

*   **Статус:** `sudo systemctl status document-scanner.service`
*   **Запуск:** `sudo systemctl start document-scanner.service`
*   **Зупинка:** `sudo systemctl stop document-scanner.service`
*   **Перезапуск:** `sudo systemctl restart document-scanner.service`
*   **Логи:** `sudo journalctl -u document-scanner.service -f`

## Файл конфігурації

Головний конфігураційний файл — `/opt/document-scanner-service/.env` у контейнері. Він генерується автоматично скриптом `lxc_deployment.sh`.

**Приклад структури `.env`:**
```properties
# MSSQL
DB_SERVER=ip_або_хост_mssql
DB_NAME=DocumentDB
DB_USER=користувач_mssql
DB_PASSWORD=пароль_mssql
DB_ENCRYPT=false
DB_TRUST_CERT=true

# Ollama
OLLAMA_URL=http://ip_ollama:11434
EMBEDDING_SERVICE=http://ip_ollama:11434/api/embeddings
EMBEDDING_MODEL=nomic-embed-text

# LLM
LLM_MODEL=llama3.2
LLM_TEMPERATURE=0.7
LLM_MAX_TOKENS=2000

# OpenWebUI
OPENWEBUI_URL=http://ip_openwebui:8080

# Server
PORT=3000
HOST=0.0.0.0

# SMB - якщо налаштовано
SMB_SERVER=smb-сервер
SMB_SHARE=шар
SMB_USER=користувач_smb
SMB_PASSWORD=пароль_smb
SMB_PATH=/mnt/smb_share
SMB_MOUNT_POINT=/mnt/smb_share

# Logging
LOG_LEVEL=info
LOG_FILE=logs/app.log
```

## Вирішення проблем

*   **Мережа LXC:** Переконайтеся, що контейнер має доступ до мережі та може резолвити імена зовнішніх сервісів.
*   **Фаєрволи:** Перевірте, чи не блокують фаєрволи (на хості, у контейнері чи на серверах зовнішніх сервісів) підключення.
*   **Логи сервісу:** Використовуйте `journalctl -u document-scanner.service` у контейнері для перегляду логів.
*   **Встановлення залежностей:** Якщо `npm install` не спрацьовує, перевірте наявність системних залежностей (`build-essential`, `python3` тощо). Скрипт намагається встановити основні.

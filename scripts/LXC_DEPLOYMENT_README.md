# Інструкція з розгортання Document Scanner Service у LXC (Proxmox)

Цей посібник пояснює, як розгорнути Document Scanner Service у контейнері LXC на основі Debian у середовищі Proxmox. Передбачається, що **MSSQL Server, Ollama та OpenWebUI вже розгорнуті й доступні як окремі сервіси**.

## Необхідні умови

1.  **Proxmox LXC-хост:** Сервер Proxmox із налаштованим LXC (контейнеризація має бути активована).
2.  **Зовнішні сервіси:**
    *   **MSSQL Server:** Має бути доступний з контейнера LXC. Потрібні: хост/IP, порт (за замовчуванням 1433), ім'я користувача, пароль і назва бази даних.
    *   **Ollama Service:** Має бути доступний з контейнера LXC. Потрібна базова URL-адреса (наприклад, `http://<ollama-host>:11434`). Переконайтеся, що потрібні моделі (`llama3.2`, `nomic-embed-text`) доступні на цьому екземплярі Ollama.
    *   **OpenWebUI Service:** Має бути доступний з контейнера LXC. Потрібна базова URL-адреса (наприклад, `http://<openwebui-host>:8080`).
3.  **Доступ до інтернету:** Контейнер повинен мати доступ до GitHub для клонування репозиторію проекту `document-scanner-service`.
4.  **Git:** Встановлений git у контейнері (скрипт розгортання встановить Git, якщо його немає).

## Кроки розгортання

### Крок 1: Підготовка Proxmox та LXC контейнера

1.  Створіть LXC-контейнер через веб-інтерфейс Proxmox або за допомогою CLI. Рекомендується використовувати Debian (наприклад, шаблон Debian 12).
2.  Рекомендується встановити у контейнері базові утиліти (`sudo`, `curl` тощо), хоча скрипт розгортання автоматично встановить Git, Node.js та інші необхідні залежності.
3.  Завантажте файли скрипту `lxc_deployment.sh` та `.env` з репозиторію у контейнер. Це можна зробити одним з таких способів:
   
   **Варіант 1:** За допомогою `wget` безпосередньо у контейнері:
   ```bash
   # Завантаження скрипту розгортання
   wget -O /tmp/lxc_deployment.sh https://raw.githubusercontent.com/Lion-killer/document-scanner-service/master/scripts/lxc_deployment.sh
   chmod +x /tmp/lxc_deployment.sh
   
   # Завантаження прикладу .env файлу
   wget -O /tmp/.env https://raw.githubusercontent.com/Lion-killer/document-scanner-service/master/.env.example
   ```
   
   **Варіант 2:** Скопіювати файли з хоста у контейнер:
   ```bash
   # Копіювання скрипту розгортання
   pct push <VMID> /шлях/до/lxc_deployment.sh /tmp/lxc_deployment.sh
   pct exec <VMID> -- chmod +x /tmp/lxc_deployment.sh
   
   # Копіювання .env файлу
   pct push <VMID> /шлях/до/.env /tmp/.env
   ```
   
4.  Відредагуйте файл `.env` із потрібними параметрами конфігурації. Скрипт автоматично клонуватиме весь проект з GitHub під час розгортання.

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
2.  Переконайтеся, що файл `.env` містить необхідні параметри конфігурації. Відредагуйте його за потреби:

    ```bash
    # Відредагуйте .env файл із правильними параметрами підключення
    nano /tmp/.env
    ```
    
    **Приклад .env файлу:**
    ```properties
    # MSSQL
    DB_SERVER=192.168.1.100:1433
    DB_NAME=DocumentDB
    DB_USER=sa
    DB_PASSWORD=YourPassword123!
    DB_ENCRYPT=false
    DB_TRUST_CERT=true

    # Ollama
    OLLAMA_URL=http://192.168.1.101:11434
    EMBEDDING_SERVICE=http://192.168.1.101:11434/api/embeddings
    EMBEDDING_MODEL=nomic-embed-text

    # LLM
    LLM_MODEL=llama3.2
    LLM_TEMPERATURE=0.7
    LLM_MAX_TOKENS=2000

    # OpenWebUI
    OPENWEBUI_URL=http://192.168.1.102:8080

    # Server
    PORT=3000
    HOST=0.0.0.0

    # SMB - опціонально
    SMB_SERVER=192.168.1.200
    SMB_SHARE=docs
    SMB_USER=smb_user
    SMB_PASSWORD=smb_password
    SMB_PATH=/mnt/smb_docs
    SMB_MOUNT_POINT=/mnt/smb_docs

    # Logging
    LOG_LEVEL=info
    LOG_FILE=logs/app.log
    ```
    
3.  Запустіть завантажений скрипт `lxc_deployment.sh`, вказавши шлях до файлу `.env`:

    ```bash
    /tmp/lxc_deployment.sh /tmp/.env
    ```
    
    Або запустіть скрипт без параметрів, якщо `.env` файл знаходиться в поточній директорії:
    
    ```bash
    /tmp/lxc_deployment.sh
    ```
    
    > **Примітка:** Якщо файл `.env` не вказано, скрипт шукатиме файл `.env` в поточній директорії. Якщо такого файлу немає, скрипт автоматично клонує репозиторій і використає `.env.example` як шаблон.

    Скрипт виконає:
    *   Встановлення Git, Node.js, npm та необхідних залежностей.
    *   Клонування коду проекту з GitHub у директорію `/opt/document-scanner-service`.
    *   Встановлення залежностей проекту (`npm install`).
    *   Збірку проекту TypeScript (`npm run build`).
    *   Генерацію `/opt/document-scanner-service/.env` з параметрами підключення.
    *   Налаштування та запуск systemd-сервісу (`document-scanner.service`).
    *   (Опціонально) Монтування SMB-шару, якщо вказані параметри.

### Крок 4: Тестування підключень до зовнішніх сервісів

Після розгортання, перебуваючи у контейнері, запустіть скрипт `test_remote_connections.sh` який був автоматично клоновано з GitHub:

```bash
# Скрипт автоматично використає /opt/document-scanner-service/.env
/opt/scripts/test_remote_connections.sh
```

Або вкажіть шлях до файлу .env:

```bash
/opt/scripts/test_remote_connections.sh /шлях/до/.env
```

Альтернативно, ви можете запустити його з параметрами для перевірки конкретних підключень:

```bash
/opt/scripts/test_remote_connections.sh \
    "ip_або_хост_mssql" \
    "користувач_mssql" \
    "пароль_mssql" \
    "DocumentDB" \
    "ip_ollama:11434" \
    "ip_openwebui:8080"
```

Скрипт перевірить:
*   Підключення до MSSQL та наявність бази даних.
*   Доступність Ollama API та наявність потрібних моделей.
*   Доступність OpenWebUI.

### Крок 5: (Опціонально) Керування SMB-шаром

*   Скрипт `lxc_smb_mount.sh` викликається з `lxc_deployment.sh`, якщо вказані параметри SMB.
*   Скрипт також можна запустити вручну, передавши шлях до .env файлу або параметри напряму:

    ```bash
    # Використання .env файлу
    /opt/scripts/lxc_smb_mount.sh /шлях/до/.env
    
    # Або з параметрами командного рядка
    /opt/scripts/lxc_smb_mount.sh "//server/share" "/mnt/smb_point" "username" "password"
    ```

*   Для ручного демонтування використовуйте стандартні команди Linux, наприклад: `umount /mnt/smb_share`.

## Керування сервісом (у контейнері)

Після розгортання керуйте сервісом `document-scanner.service` через systemctl:

*   **Статус:** `systemctl status document-scanner.service`
*   **Запуск:** `systemctl start document-scanner.service`
*   **Зупинка:** `systemctl stop document-scanner.service`
*   **Перезапуск:** `systemctl restart document-scanner.service`
*   **Логи:** `journalctl -u document-scanner.service -f`

## Оновлення сервісу з GitHub

Для оновлення коду сервісу до останньої версії з GitHub:

```bash
# Зупинити сервіс
systemctl stop document-scanner.service

# Перейти в директорію проекту
cd /opt/document-scanner-service

# Оновити код з репозиторію
git fetch origin
git reset --hard origin/master  # або іншої гілки, якщо потрібно

# Встановити нові залежності, якщо потрібно
npm install --omit=dev

# Зібрати проект
npm run build

# Запустити сервіс
systemctl start document-scanner.service
```

Цей процес можна автоматизувати за допомогою скрипта. Наприклад, ви можете створити файл `/opt/scripts/update_service.sh`:

```bash
#!/bin/bash
cd /opt/document-scanner-service && \
systemctl stop document-scanner.service && \
git fetch origin && \
git reset --hard origin/master && \
npm install --omit=dev && \
npm run build && \
systemctl start document-scanner.service && \
echo "Сервіс успішно оновлено до останньої версії!"
```

Не забудьте зробити скрипт виконуваним:
```bash
chmod +x /opt/scripts/update_service.sh
```

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

*   **Доступ до GitHub:** Переконайтеся, що контейнер має доступ до інтернету та може підключитися до GitHub для клонування репозиторію. Якщо доступу немає, можна тимчасово змінити файл hosts або використовувати проксі.
*   **Мережа LXC:** Переконайтеся, що контейнер має доступ до мережі та може резолвити імена зовнішніх сервісів.
*   **Фаєрволи:** Перевірте, чи не блокують фаєрволи (на хості, у контейнері чи на серверах зовнішніх сервісів) підключення.
*   **Логи сервісу:** Використовуйте `journalctl -u document-scanner.service` у контейнері для перегляду логів.
*   **Встановлення залежностей:** Якщо `npm install` не спрацьовує, перевірте наявність системних залежностей (`build-essential`, `python3` тощо). Скрипт намагається встановити основні.
*   **Проблеми з клонуванням:** Якщо виникають проблеми з автоматичним клонуванням, можна клонувати репозиторій вручну:
    ```bash
    git clone https://github.com/Lion-killer/document-scanner-service.git /opt/document-scanner-service
    cd /opt/document-scanner-service
    chmod +x scripts/*.sh
    # Потім запустити скрипт розгортання з цієї директорії
    ```

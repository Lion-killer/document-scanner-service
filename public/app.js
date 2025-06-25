// Глобальні змінні
let currentPage = 1;
let itemsPerPage = 10;
let totalPages = 1;
let allDocuments = [];
let scanInProgress = false;
let chatHistory = [];
let sidebarVisible = false;

// Ініціалізація при завантаженні сторінки
window.addEventListener('load', () => {
    updateSidebarStatus();
    checkInfoBannerStatus();
    // При старті сайдбар схований на мобільних пристроях
    const sidebar = document.getElementById('sidebar');
    const mainContent = document.querySelector('.main-content');
    
    if (window.innerWidth <= 768) {
        sidebar.classList.add('hidden');
        mainContent.classList.add('sidebar-hidden');
    } else {
        sidebarVisible = true;
    }
});

// Функція оновлення статусу на бічній панелі
async function updateSidebarStatus() {
    try {
        const response = await fetch('/api/status');
        const data = await response.json();
        
        document.getElementById('sidebar-status').innerHTML = `
            <p><strong>Статус:</strong> ${data.status}</p>
            <p><strong>Останнє сканування:</strong> ${data.lastScan || 'Ніколи'}</p>
            <p><strong>Кількість документів:</strong> ${data.documentsCount || 0}</p>
            <p><strong>Кількість векторів:</strong> ${data.vectorsCount || 0}</p>
        `;
        
        // Оновлення статусу сканування
        scanInProgress = data.scanInProgress || false;
        const scanButton = document.getElementById('sidebarScanButton');
        
        if (scanInProgress) {
            scanButton.disabled = true;
            scanButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Сканування...';
        } else {
            scanButton.disabled = false;
            scanButton.innerHTML = '<i class="fas fa-sync-alt"></i> Ручне сканування';
        }
        
        // Завантаження документів у сайдбар
        loadSidebarDocuments();
    } catch (error) {
        console.error('Помилка при завантаженні статусу:', error);
        document.getElementById('sidebar-status').innerHTML = `
            <p class="error">Помилка при завантаженні статусу</p>
            <p>Перевірте з'єднання з сервером</p>
        `;
    }
}

// Перевірка, чи потрібно показувати інформаційний банер
function checkInfoBannerStatus() {
    const bannerDismissed = localStorage.getItem('previewInfoBannerDismissed');
    if (bannerDismissed === 'true') {
        const banner = document.querySelector('.info-banner');
        if (banner) {
            banner.style.display = 'none';
        }
    }
}

// Приховання інформаційного банера
function dismissInfoBanner() {
    const banner = document.querySelector('.info-banner');
    if (banner) {
        banner.style.display = 'none';
        localStorage.setItem('previewInfoBannerDismissed', 'true');
    }
}

// Оновлення статусу системи
async function refreshStatus() {
    try {
        const response = await fetch('/api/status');
        const data = await response.json();
        
        document.getElementById('status').innerHTML = `
            <p><strong>Статус:</strong> ${data.status}</p>
            <p><strong>Останнє сканування:</strong> ${data.lastScan || 'Ніколи'}</p>
            <p><strong>Кількість документів:</strong> ${data.documentsCount || 0}</p>
            <p><strong>Кількість векторів:</strong> ${data.vectorsCount || 0}</p>
        `;
        
        // Оновлення статусу сканування
        scanInProgress = data.scanInProgress || false;
        const scanButton = document.getElementById('scanButton');
        
        if (scanInProgress) {
            scanButton.disabled = true;
            scanButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Сканування...';
        } else {
            scanButton.disabled = false;
            scanButton.innerHTML = '<i class="fas fa-sync-alt"></i> Ручне сканування';
        }
    } catch (error) {
        console.error('Помилка при завантаженні статусу:', error);
        document.getElementById('status').innerHTML = `
            <p class="error">Помилка при завантаженні статусу</p>
            <p>Перевірте з'єднання з сервером</p>
        `;
    }
}

// Запуск ручного сканування
async function manualScan() {
    const scanButton = document.getElementById('scanButton');
    try {
        scanButton.disabled = true;
        scanButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Сканування...';
        
        const response = await fetch('/api/scan/manual', { method: 'POST' });
        const data = await response.json();
        
        if (data.success) {
            alert('Сканування запущено успішно');
            
            // Періодично перевіряти статус сканування
            const checkInterval = setInterval(async () => {
                await refreshStatus();
                if (!scanInProgress) {
                    clearInterval(checkInterval);
                    loadDocuments(); // Оновити список документів після завершення
                }
            }, 5000);
        } else {
            alert('Помилка при скануванні: ' + (data.error || 'Невідома помилка'));
            scanButton.disabled = false;
            scanButton.innerHTML = '<i class="fas fa-sync-alt"></i> Ручне сканування';
        }
    } catch (error) {
        console.error('Помилка при скануванні:', error);
        alert('Помилка при скануванні: Перевірте з\'єднання з сервером');
        scanButton.disabled = false;
        scanButton.innerHTML = '<i class="fas fa-sync-alt"></i> Ручне сканування';
    }
}

// Пошук документів
async function searchDocuments() {
    const query = document.getElementById('searchQuery').value;
    if (!query.trim()) return;

    try {
        document.getElementById('searchResults').innerHTML = '<p>Пошук...</p>';
        
        const response = await fetch('/api/search', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ query, limit: 20 })
        });
        
        const results = await response.json();
        
        if (results.length === 0) {
            document.getElementById('searchResults').innerHTML = '<p>Нічого не знайдено</p>';
            return;
        }
        
        const resultsHtml = results.map(result => {
            // Підсвітити знайдені входження запиту
            let highlightedContent = result.content;
            const queryTerms = query.toLowerCase().split(' ').filter(term => term.length > 2);
            
            queryTerms.forEach(term => {
                const regex = new RegExp(`(${term})`, 'gi');
                highlightedContent = highlightedContent.replace(regex, '<span class="highlight">$1</span>');
            });
            
            return `
                <div class="document-item">
                    <h3>${result.filename}</h3>
                    <p><strong>Подібність:</strong> ${(result.similarity * 100).toFixed(1)}%</p>
                    <p><strong>Дата:</strong> ${new Date(result.created_at || new Date()).toLocaleDateString()}</p>
                    <p>${highlightedContent.substring(0, 300)}${highlightedContent.length > 300 ? '...' : ''}</p>
                    <div class="button-group">
                        <button onclick="showFullDocument('${result.documentId}')"><i class="fas fa-eye"></i> Переглянути</button>
                        <button onclick="openDocumentPreview('${result.documentId}', '${result.filename}')" style="background-color: #e67e22;"><i class="fas fa-external-link-alt"></i> Попередній перегляд</button>
                    </div>
                </div>
            `;
        }).join('');
        
        document.getElementById('searchResults').innerHTML = resultsHtml;
    } catch (error) {
        console.error('Помилка пошуку:', error);
        document.getElementById('searchResults').innerHTML = '<p class="error">Помилка при пошуку</p>';
    }
}

// Завантаження всіх документів
async function loadDocuments(page = 1) {
    currentPage = page;
    
    try {
        document.getElementById('documentsList').innerHTML = '<p>Завантаження...</p>';
        
        // Отримати тип документу для фільтрації
        const docType = document.getElementById('docTypeFilter').value;
        
        const response = await fetch(`/api/documents?page=${page}&limit=${itemsPerPage}${docType ? `&type=${docType}` : ''}`);
        const data = await response.json();
        
        if (!data.documents || data.documents.length === 0) {
            document.getElementById('documentsList').innerHTML = '<p>Документів не знайдено</p>';
            document.getElementById('pagination').innerHTML = '';
            return;
        }
        
        allDocuments = data.documents;
        totalPages = Math.ceil(data.total / itemsPerPage);
        
        const documentsHtml = data.documents.map(doc => `
            <div class="document-item">
                <h3>${doc.filename}</h3>
                <p><strong>Тип:</strong> ${doc.file_type || doc.type}</p>
                <p><strong>Розмір:</strong> ${formatFileSize(doc.file_size || doc.size)}</p>
                <p><strong>Дата додавання:</strong> ${new Date(doc.created_at || doc.modifiedTime).toLocaleDateString()}</p>
                <div class="button-group">
                    <button onclick="showFullDocument('${doc.id}')"><i class="fas fa-eye"></i> Переглянути</button>
                    <button onclick="openDocumentPreview('${doc.id}', '${doc.filename}')" style="background-color: #e67e22;"><i class="fas fa-external-link-alt"></i> Попередній перегляд</button>
                    <button onclick="deleteDocument('${doc.id}')" style="background-color: #e74c3c;"><i class="fas fa-trash"></i> Видалити</button>
                </div>
            </div>
        `).join('');
        
        document.getElementById('documentsList').innerHTML = documentsHtml;
        
        // Відображення пагінації
        renderPagination();
    } catch (error) {
        console.error('Помилка завантаження документів:', error);
        document.getElementById('documentsList').innerHTML = '<p class="error">Помилка при завантаженні документів</p>';
    }
}

// Відображення пагінації
function renderPagination() {
    if (totalPages <= 1) {
        document.getElementById('pagination').innerHTML = '';
        return;
    }
    
    let paginationHtml = '';
    
    // Кнопка "Попередня сторінка"
    paginationHtml += `<button ${currentPage === 1 ? 'disabled' : ''} onclick="loadDocuments(${currentPage - 1})">«</button>`;
    
    // Номери сторінок
    const maxVisiblePages = 5;
    let startPage = Math.max(1, currentPage - Math.floor(maxVisiblePages / 2));
    let endPage = Math.min(totalPages, startPage + maxVisiblePages - 1);
    
    if (endPage - startPage < maxVisiblePages - 1) {
        startPage = Math.max(1, endPage - maxVisiblePages + 1);
    }
    
    // Перша сторінка
    if (startPage > 1) {
        paginationHtml += `<button onclick="loadDocuments(1)">1</button>`;
        if (startPage > 2) {
            paginationHtml += `<span>...</span>`;
        }
    }
    
    // Номери сторінок
    for (let i = startPage; i <= endPage; i++) {
        paginationHtml += `<button class="${i === currentPage ? 'active' : ''}" onclick="loadDocuments(${i})">${i}</button>`;
    }
    
    // Остання сторінка
    if (endPage < totalPages) {
        if (endPage < totalPages - 1) {
            paginationHtml += `<span>...</span>`;
        }
        paginationHtml += `<button onclick="loadDocuments(${totalPages})">${totalPages}</button>`;
    }
    
    // Кнопка "Наступна сторінка"
    paginationHtml += `<button ${currentPage === totalPages ? 'disabled' : ''} onclick="loadDocuments(${currentPage + 1})">»</button>`;
    
    document.getElementById('pagination').innerHTML = paginationHtml;
}

// Форматування розміру файлу
function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

// Повний перегляд документа
async function showFullDocument(id) {
    try {
        const response = await fetch(`/api/documents/${id}`);
        const document = await response.json();
        
        if (!document) {
            alert('Документ не знайдено');
            return;
        }
        
        // Створення модального вікна для перегляду
        const modal = document.createElement('div');
        modal.style.position = 'fixed';
        modal.style.top = '0';
        modal.style.left = '0';
        modal.style.width = '100%';
        modal.style.height = '100%';
        modal.style.backgroundColor = 'rgba(0, 0, 0, 0.7)';
        modal.style.zIndex = '1000';
        modal.style.display = 'flex';
        modal.style.justifyContent = 'center';
        modal.style.alignItems = 'center';
        
        const modalContent = document.createElement('div');
        modalContent.style.backgroundColor = 'white';
        modalContent.style.padding = '30px';
        modalContent.style.borderRadius = '8px';
        modalContent.style.maxWidth = '800px';
        modalContent.style.width = '90%';
        modalContent.style.maxHeight = '80%';
        modalContent.style.overflowY = 'auto';
        
        modalContent.innerHTML = `
            <h2>${document.filename}</h2>
            <p><strong>Тип:</strong> ${document.file_type || document.type}</p>
            <p><strong>Розмір:</strong> ${formatFileSize(document.file_size || document.size)}</p>
            <p><strong>Дата додавання:</strong> ${new Date(document.created_at || document.modifiedTime).toLocaleDateString()}</p>
            <hr>
            <div class="button-group" style="margin: 15px 0;">
                <button id="previewDocBtn" style="background-color: #e67e22;"><i class="fas fa-external-link-alt"></i> Попередній перегляд</button>
                <button id="closeModalBtn" style="background-color: #7f8c8d;"><i class="fas fa-times"></i> Закрити</button>
            </div>
            <hr>
            <div style="white-space: pre-wrap; margin-top: 15px;">
                ${document.content || 'Вміст недоступний'}
            </div>
        `;
        
        modal.appendChild(modalContent);
        document.body.appendChild(modal);
        
        // Обробник для попереднього перегляду документа
        document.getElementById('previewDocBtn').addEventListener('click', () => {
            openDocumentPreview(id, document.filename || '');
        });
        
        // Закриття модального вікна
        document.getElementById('closeModalBtn').addEventListener('click', () => {
            document.body.removeChild(modal);
        });
        
        // Закриття по кліку поза модальним вікном
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                document.body.removeChild(modal);
            }
        });
    } catch (error) {
        console.error('Помилка при отриманні документа:', error);
        alert('Помилка при отриманні документа');
    }
}

// Відкриття попереднього перегляду документа в новому вікні
function openDocumentPreview(id, filename) {
    const previewUrl = `/api/documents/${id}/preview`;
    const previewWindow = window.open(
        previewUrl,
        `preview_${id}`,
        'width=800,height=600,resizable=yes,scrollbars=yes,status=yes'
    );
    
    if (!previewWindow) {
        alert('Будь ласка, дозвольте спливаючі вікна для цього сайту, щоб користуватися функцією попереднього перегляду.');
    }
}

// Функції для роботи з чатом
async function sendMessage(event) {
    if (event) event.preventDefault();
    
    const messageInput = document.getElementById('message-input');
    const message = messageInput.value.trim();
    
    if (!message) return;
    
    // Додаємо повідомлення користувача до чату
    appendMessage(message, 'user');
    
    // Очищуємо поле вводу і скидаємо його висоту
    messageInput.value = '';
    messageInput.style.height = 'auto';
    
    // Показуємо індикатор завантаження
    const loadingIndicator = appendMessage('Пошук інформації в документах...', 'assistant', true);
    
    try {
        // Запит до API для обробки повідомлення
        const response = await fetch('/api/openwebui/query', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ message })
        });
        
        const result = await response.json();
        
        // Видаляємо індикатор завантаження
        if (loadingIndicator) {
            loadingIndicator.remove();
        }
        
        // Додаємо відповідь асистента
        appendMessage(result.response, 'assistant');
        
        // Якщо є джерела, показуємо їх
        if (result.sources && result.sources.length > 0) {
            appendSources(result.sources);
        }
    } catch (error) {
        console.error('Помилка при отриманні відповіді:', error);
        
        // Видаляємо індикатор завантаження
        if (loadingIndicator) {
            loadingIndicator.remove();
        }
        
        // Показуємо повідомлення про помилку
        appendMessage('Виникла помилка при обробці запиту. Будь ласка, спробуйте ще раз.', 'assistant error');
    }
    
    // Прокручуємо чат до останнього повідомлення
    scrollToBottom();
}

// Додавання повідомлення в чат
function appendMessage(content, role, isLoading = false) {
    const chatMessages = document.getElementById('chat-messages');
    const messageDiv = document.createElement('div');
    
    messageDiv.className = `message ${role}-message`;
    
    if (isLoading) {
        messageDiv.innerHTML = `
            <div class="message-content">
                <div class="loading-dots">
                    <span></span><span></span><span></span>
                </div>
            </div>
        `;
    } else {
        messageDiv.innerHTML = `
            <div class="message-avatar">
                <i class="fas fa-${role === 'user' ? 'user' : 'robot'}"></i>
            </div>
            <div class="message-content">
                ${formatMessage(content)}
            </div>
        `;
    }
    
    // Очищаємо вітальне повідомлення при першому повідомленні
    const welcomeMessage = document.querySelector('.welcome-message');
    if (welcomeMessage && chatMessages.childElementCount === 0) {
        welcomeMessage.style.display = 'none';
    }
    
    chatMessages.appendChild(messageDiv);
    return messageDiv;
}

// Додавання джерел у чат
function appendSources(sources) {
    const chatMessages = document.getElementById('chat-messages');
    const sourcesDiv = document.createElement('div');
    
    sourcesDiv.className = 'message-sources';
    
    const sourcesList = sources.map(source => `
        <div class="source-item">
            <h4>${source.filename}</h4>
            <p>${source.content}</p>
            <div class="source-actions">
                <button onclick="showFullDocument('${source.documentId || ''}')">
                    <i class="fas fa-eye"></i> Переглянути
                </button>
                <button onclick="openDocumentPreview('${source.documentId || ''}', '${source.filename}')" style="background-color: #e67e22;">
                    <i class="fas fa-external-link-alt"></i> Попередній перегляд
                </button>
            </div>
        </div>
    `).join('');
    
    sourcesDiv.innerHTML = `
        <div class="sources-header">
            <h3>Джерела інформації</h3>
        </div>
        <div class="sources-list">
            ${sourcesList}
        </div>
    `;
    
    chatMessages.appendChild(sourcesDiv);
}

// Форматування повідомлення (підтримка маркдауну)
function formatMessage(text) {
    // Заміна посилань на HTML якірні теги
    text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank">$1</a>');
    
    // Перетворення \n на <br>
    text = text.replace(/\n/g, '<br>');
    
    return text;
}

// Автоматичне розтягування поля вводу
function autoResize(textarea) {
    textarea.style.height = 'auto';
    textarea.style.height = (textarea.scrollHeight) + 'px';
}

// Прокручування чату вниз
function scrollToBottom() {
    const chatArea = document.getElementById('chat-area');
    chatArea.scrollTop = chatArea.scrollHeight;
}

// Встановлення прикладу запиту в поле вводу
function setExampleQuery(query) {
    const messageInput = document.getElementById('message-input');
    messageInput.value = query;
    messageInput.focus();
    autoResize(messageInput);
}

// Переключення бічної панелі
function toggleSidebar() {
    const sidebar = document.getElementById('sidebar');
    sidebar.classList.toggle('hidden');
}

// Створення нового чату
function newChat() {
    // Очищаємо чат
    const chatMessages = document.getElementById('chat-messages');
    chatMessages.innerHTML = '';
    
    // Показуємо вітальне повідомлення
    const welcomeMessage = document.querySelector('.welcome-message');
    if (welcomeMessage) {
        welcomeMessage.style.display = 'block';
    }
    
    // Закриваємо бічну панель на мобільних пристроях
    if (window.innerWidth < 768) {
        toggleSidebar();
    }
}

// Функції для роботи з модальним вікном допомоги
function showHelpModal() {
    const modal = document.getElementById('helpModal');
    if (modal) {
        modal.style.display = 'flex';
    }
}

function closeHelpModal() {
    const modal = document.getElementById('helpModal');
    if (modal) {
        modal.style.display = 'none';
    }
}

// Закриття модального вікна допомоги по кліку поза вікном
window.addEventListener('click', (event) => {
    const modal = document.getElementById('helpModal');
    if (event.target === modal) {
        modal.style.display = 'none';
    }
});

// Видалення документа
async function deleteDocument(id) {
    if (!confirm('Ви впевнені, що хочете видалити цей документ?')) {
        return;
    }
    
    try {
        const response = await fetch(`/api/documents/${id}`, {
            method: 'DELETE'
        });
        
        const result = await response.json();
        
        if (result.success) {
            alert('Документ успішно видалено');
            
            // Оновлення списку документів
            refreshDocumentsList();
            
            // Додавання інформації в чат, якщо потрібно
            const chatMessages = document.getElementById('chat-messages');
            if (chatMessages && chatMessages.childElementCount > 0) {
                appendMessage('Документ успішно видалено з системи', 'system');
            }
        } else {
            alert('Помилка при видаленні документа: ' + (result.error || 'Невідома помилка'));
        }
    } catch (error) {
        console.error('Помилка при видаленні документа:', error);
        alert('Помилка при видаленні документа');
    }
}

// Оновлення списку документів в бічній панелі
async function refreshDocumentsList() {
    try {
        // Отримати тип документу для фільтрації
        const docType = document.getElementById('docTypeFilter').value;
        
        const response = await fetch(`/api/documents?page=1&limit=5${docType ? `&type=${docType}` : ''}`);
        const data = await response.json();
        
        if (!data.documents || data.documents.length === 0) {
            document.getElementById('sidebar-documentsList').innerHTML = '<p>Документів не знайдено</p>';
            return;
        }
        
        const documentsHtml = data.documents.map(doc => `
            <div class="sidebar-document-item">
                <h4>${doc.filename}</h4>
                <p>${doc.file_type || doc.type} - ${formatFileSize(doc.file_size || doc.size)}</p>
                <div class="button-group">
                    <button onclick="showFullDocument('${doc.id}')"><i class="fas fa-eye"></i></button>
                    <button onclick="openDocumentPreview('${doc.id}', '${doc.filename}')" style="background-color: #e67e22;"><i class="fas fa-external-link-alt"></i></button>
                    <button onclick="askAboutDocument('${doc.id}', '${doc.filename}')" style="background-color: #27ae60;"><i class="fas fa-comments"></i></button>
                </div>
            </div>
        `).join('');
        
        document.getElementById('sidebar-documentsList').innerHTML = documentsHtml;
    } catch (error) {
        console.error('Помилка завантаження документів:', error);
        document.getElementById('sidebar-documentsList').innerHTML = '<p class="error">Помилка при завантаженні документів</p>';
    }
}

// Запитати про документ у чаті
async function askAboutDocument(id, filename) {
    // Закриваємо бічну панель на мобільних пристроях
    if (window.innerWidth < 768) {
        toggleSidebar();
    }
    
    // Додаємо запит про документ
    const query = `Розкажи про вміст документу ${filename}`;
    
    // Встановлюємо запит у поле вводу
    const messageInput = document.getElementById('message-input');
    messageInput.value = query;
    messageInput.focus();
    
    // Відправляємо запит
    sendMessage();
}

// Ініціалізація бічної панелі статусу
async function refreshSidebarStatus() {
    try {
        const response = await fetch('/api/status');
        const data = await response.json();
        
        document.getElementById('sidebar-status').innerHTML = `
            <p><strong>Статус:</strong> ${data.status}</p>
            <p><strong>Останнє сканування:</strong> ${data.lastScan || 'Ніколи'}</p>
            <p><strong>Кількість документів:</strong> ${data.documentsCount || 0}</p>
        `;
        
        // Оновлення статусу сканування
        scanInProgress = data.scanInProgress || false;
        const scanButton = document.getElementById('sidebarScanButton');
        
        if (scanInProgress) {
            scanButton.disabled = true;
            scanButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Сканування...';
        } else {
            scanButton.disabled = false;
            scanButton.innerHTML = '<i class="fas fa-sync-alt"></i> Ручне сканування';
        }
        
        // Оновлення списку документів
        refreshDocumentsList();
    } catch (error) {
        console.error('Помилка при завантаженні статусу:', error);
        document.getElementById('sidebar-status').innerHTML = `
            <p class="error">Помилка при завантаженні статусу</p>
            <p>Перевірте з'єднання з сервером</p>
        `;
    }
}

// ================== НОВІ CHAT ФУНКЦІЇ ==================

// Перемикання відображення бічної панелі
function toggleSidebar() {
    const sidebar = document.getElementById('sidebar');
    sidebar.classList.toggle('hidden');
}

// Автоматичне змінення розміру текстової області
function autoResize(textarea) {
    textarea.style.height = 'auto';
    textarea.style.height = (textarea.scrollHeight) + 'px';
}

// Новий чат
function newChat() {
    // Очищення історії
    chatHistory = [];
    
    // Очищення вікна чату
    const chatArea = document.getElementById('chat-messages');
    chatArea.innerHTML = '';
    
    // Показ привітання
    document.querySelector('.welcome-message').style.display = 'block';
    
    // Очищення поля вводу
    document.getElementById('message-input').value = '';
    
    // Закрити сайдбар на мобільних
    if (window.innerWidth <= 768) {
        toggleSidebar();
    }
}

// Відправка повідомлення
async function sendMessage(event) {
    if (event) event.preventDefault();
    
    const messageInput = document.getElementById('message-input');
    const message = messageInput.value.trim();
    
    if (!message) return;
    
    // Приховати привітання
    document.querySelector('.welcome-message').style.display = 'none';
    
    // Показати повідомлення користувача
    addUserMessage(message);
    
    // Очистити поле вводу
    messageInput.value = '';
    messageInput.style.height = 'auto';
    
    // Додати індикатор завантаження
    const loadingIndicator = addLoadingMessage();
    
    try {
        // Виклик API для отримання відповіді
        const response = await fetch('/api/openwebui/query', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ message })
        });
        
        const data = await response.json();
        
        // Видалення індикатора завантаження
        loadingIndicator.remove();
        
        // Додавання відповіді від AI
        addBotMessage(data.response, data.sources);
        
    } catch (error) {
        console.error('Помилка при відправці повідомлення:', error);
        
        // Видалення індикатора завантаження
        loadingIndicator.remove();
        
        // Додавання повідомлення про помилку
        addSystemMessage('Помилка при отриманні відповіді. Перевірте з\'єднання з сервером.');
    }
}

// Додавання повідомлення користувача в чат
function addUserMessage(message) {
    const chatMessages = document.getElementById('chat-messages');
    
    const messageElement = document.createElement('div');
    messageElement.className = 'chat-message user-message';
    messageElement.innerHTML = `
        <div class="message-content">
            <p>${escapeHtml(message)}</p>
        </div>
    `;
    
    chatMessages.appendChild(messageElement);
    scrollToBottom();
    
    // Додавання в історію
    chatHistory.push({ role: 'user', content: message });
}

// Додавання повідомлення від бота в чат
function addBotMessage(message, sources = []) {
    const chatMessages = document.getElementById('chat-messages');
    
    // Форматування повідомлення (заміна посилань на документи)
    let formattedMessage = message;
    
    // Додавання джерел, якщо вони є
    let sourcesHtml = '';
    if (sources && sources.length > 0) {
        sourcesHtml = '<div class="message-sources">';
        sourcesHtml += '<p><strong>Джерела:</strong></p>';
        sourcesHtml += '<ul>';
        
        sources.forEach(source => {
            sourcesHtml += `<li>
                <p><strong>${source.filename}</strong> (схожість: ${(source.similarity * 100).toFixed(1)}%)</p>
                <button onclick="openDocumentPreview('${source.documentId}', '${source.filename}')" class="source-preview-btn">
                    <i class="fas fa-external-link-alt"></i> Перегляд
                </button>
            </li>`;
        });
        
        sourcesHtml += '</ul></div>';
    }
    
    const messageElement = document.createElement('div');
    messageElement.className = 'chat-message bot-message';
    messageElement.innerHTML = `
        <div class="message-content">
            <div class="message-text">${formattedMessage}</div>
            ${sourcesHtml}
        </div>
    `;
    
    chatMessages.appendChild(messageElement);
    scrollToBottom();
    
    // Додавання в історію
    chatHistory.push({ role: 'assistant', content: message });
}

// Додавання системного повідомлення в чат
function addSystemMessage(message) {
    const chatMessages = document.getElementById('chat-messages');
    
    const messageElement = document.createElement('div');
    messageElement.className = 'chat-message system-message';
    messageElement.innerHTML = `
        <div class="message-content">
            <p>${escapeHtml(message)}</p>
        </div>
    `;
    
    chatMessages.appendChild(messageElement);
    scrollToBottom();
}

// Додавання індикатора завантаження
function addLoadingMessage() {
    const chatMessages = document.getElementById('chat-messages');
    
    const loadingElement = document.createElement('div');
    loadingElement.className = 'chat-message bot-message loading';
    loadingElement.innerHTML = `
        <div class="message-content">
            <div class="typing-indicator">
                <span></span>
                <span></span>
                <span></span>
            </div>
        </div>
    `;
    
    chatMessages.appendChild(loadingElement);
    scrollToBottom();
    
    return loadingElement;
}

// Прокручування чату вниз
function scrollToBottom() {
    const chatArea = document.getElementById('chat-area');
    chatArea.scrollTop = chatArea.scrollHeight;
}

// Запит до документу через чат
function chatAboutDocument(id, filename) {
    // Приховати привітання
    document.querySelector('.welcome-message').style.display = 'none';
    
    // Додавання системного повідомлення
    addSystemMessage(`Обраний документ: ${filename}`);
    
    // Встановити фокус на вхідне повідомлення
    const inputField = document.getElementById('message-input');
    inputField.value = `Розкажи про вміст документу "${filename}".`;
    autoResize(inputField);
    inputField.focus();
    
    // Закрити сайдбар на мобільних
    if (window.innerWidth <= 768) {
        toggleSidebar();
    }
}

// Екранування HTML
function escapeHtml(unsafe) {
    return unsafe
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

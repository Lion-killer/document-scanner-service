// Глобальні змінні
let currentPage = 1;
let itemsPerPage = 10;
let totalPages = 1;
let allDocuments = [];
let scanInProgress = false;

// Ініціалізація при завантаженні сторінки
window.addEventListener('load', () => {
    refreshStatus();
    loadDocuments();
});

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
            scanButton.textContent = "Сканування...";
        } else {
            scanButton.disabled = false;
            scanButton.textContent = "Ручне сканування";
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
        scanButton.textContent = "Сканування...";
        
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
            scanButton.textContent = "Ручне сканування";
        }
    } catch (error) {
        console.error('Помилка при скануванні:', error);
        alert('Помилка при скануванні: Перевірте з\'єднання з сервером');
        scanButton.disabled = false;
        scanButton.textContent = "Ручне сканування";
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
                    <p><strong>Дата:</strong> ${new Date(result.created_at).toLocaleDateString()}</p>
                    <p>${highlightedContent.substring(0, 300)}${highlightedContent.length > 300 ? '...' : ''}</p>
                    <button onclick="showFullDocument('${result.id}')">Переглянути</button>
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
                <p><strong>Тип:</strong> ${doc.file_type}</p>
                <p><strong>Розмір:</strong> ${formatFileSize(doc.file_size)}</p>
                <p><strong>Дата додавання:</strong> ${new Date(doc.created_at).toLocaleDateString()}</p>
                <div class="button-group">
                    <button onclick="showFullDocument('${doc.id}')">Переглянути</button>
                    <button onclick="deleteDocument('${doc.id}')" style="background-color: #e74c3c;">Видалити</button>
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
            <p><strong>Тип:</strong> ${document.file_type}</p>
            <p><strong>Розмір:</strong> ${formatFileSize(document.file_size)}</p>
            <p><strong>Дата додавання:</strong> ${new Date(document.created_at).toLocaleDateString()}</p>
            <hr>
            <div style="white-space: pre-wrap; margin-top: 15px;">
                ${document.content || 'Вміст недоступний'}
            </div>
            <hr>
            <div style="text-align: right; margin-top: 20px;">
                <button id="closeModalBtn" style="background-color: #7f8c8d;">Закрити</button>
            </div>
        `;
        
        modal.appendChild(modalContent);
        document.body.appendChild(modal);
        
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
            loadDocuments(currentPage); // Оновлення списку
        } else {
            alert('Помилка при видаленні документа: ' + (result.error || 'Невідома помилка'));
        }
    } catch (error) {
        console.error('Помилка при видаленні документа:', error);
        alert('Помилка при видаленні документа');
    }
}

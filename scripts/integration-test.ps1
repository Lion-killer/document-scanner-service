# Integration Test Script
# This PowerShell script performs integration testing of the Document Scanner service

param(
    [switch]$Interactive = $true,  # Run in interactive mode with prompts
    [switch]$FullTest = $false,    # Run all tests including document processing
    [switch]$SkipSetup = $false,   # Skip the setup phase
    [string]$TestDataPath = ""     # Path to test data files
)

Write-Host "Document Scanner - Integration Test" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan

# Set paths
$appPath = "C:\Users\Administrator\source\repos\document-scanner-service"
$envPath = "$appPath\.env"
$testDataDir = if ($TestDataPath) { $TestDataPath } else { "$appPath\test-data" }
$scriptsDir = "$appPath\scripts"

# Test result tracking
$totalTests = 0
$passedTests = 0
$failedTests = 0
$skippedTests = 0

# Function to display test result
function Report-TestResult {
    param (
        [string]$TestName,
        [bool]$Success,
        [string]$Details = ""
    )
    
    $totalTests++
    
    if ($Success) {
        $passedTests++
        Write-Host "✓ $TestName" -ForegroundColor Green
    } else {
        $failedTests++
        Write-Host "✗ $TestName" -ForegroundColor Red
        if ($Details) {
            Write-Host "  Details: $Details" -ForegroundColor Red
        }
    }
}

# Function to skip a test
function Skip-Test {
    param (
        [string]$TestName,
        [string]$Reason = "Test skipped"
    )
    
    $script:totalTests++
    $script:skippedTests++
    Write-Host "⦻ $TestName" -ForegroundColor Yellow
    Write-Host "  Reason: $Reason" -ForegroundColor Yellow
}

# Function to verify required services
function Test-RequiredServices {
    # Check Node.js
    try {
        $nodeVersion = node --version
        $nodeOk = $true
        Write-Host "Node.js: $nodeVersion" -ForegroundColor Green
    } catch {
        $nodeOk = $false
        Write-Host "Node.js: Not found" -ForegroundColor Red
    }
    
    # Check Ollama
    try {
        $ollamaResponse = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 2 -ErrorAction Stop
        $ollamaOk = $true
        Write-Host "Ollama: Running" -ForegroundColor Green
    } catch {
        $ollamaOk = $false
        Write-Host "Ollama: Not running" -ForegroundColor Red
    }
    
    # Check Qdrant
    try {
        $qdrantResponse = Invoke-WebRequest -Uri "http://localhost:6333/collections" -Method GET -TimeoutSec 2 -ErrorAction Stop
        $qdrantOk = $true
        Write-Host "Qdrant: Running" -ForegroundColor Green
    } catch {
        $qdrantOk = $false
        Write-Host "Qdrant: Not running" -ForegroundColor Red
    }
    
    # Overall check
    $allServicesOk = $nodeOk -and $ollamaOk -and $qdrantOk
    
    return @{
        AllServicesOk = $allServicesOk
        NodeOk = $nodeOk
        OllamaOk = $ollamaOk
        QdrantOk = $qdrantOk
    }
}

# Function to check the Document Scanner service
function Test-DocumentScannerService {
    try {
        $statusResponse = Invoke-WebRequest -Uri "http://localhost:3000/api/status" -Method GET -TimeoutSec 2 -ErrorAction Stop
        
        if ($statusResponse.StatusCode -eq 200) {
            Write-Host "Document Scanner service is running" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Document Scanner service returned status code: $($statusResponse.StatusCode)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Document Scanner service is not running" -ForegroundColor Red
        return $false
    }
}

# Function to start the Document Scanner service
function Start-DocumentScannerService {
    Write-Host "Starting Document Scanner service..." -ForegroundColor Yellow
    
    # Check if service is already running
    if (Test-DocumentScannerService) {
        Write-Host "Service is already running" -ForegroundColor Green
        return $true
    }
    
    # Check if we should start the service
    if ($Interactive) {
        $startService = Read-Host "Document Scanner service is not running. Start it? (y/n)"
        if ($startService -ne 'y') {
            Write-Host "Service not started, tests will be skipped" -ForegroundColor Yellow
            return $false
        }
    }
    
    # Start the service
    $startScript = "$scriptsDir\start-document-scanner.ps1"
    
    if (Test-Path $startScript) {
        try {
            # Use PowerShell to run the script in a new process
            $process = Start-Process -FilePath "powershell.exe" -ArgumentList "-File `"$startScript`"" -PassThru
            
            # Wait for the service to start (max 30 seconds)
            $maxAttempts = 30
            $attempts = 0
            $serviceRunning = $false
            
            Write-Host "Waiting for service to start..." -ForegroundColor Yellow
            
            while (-not $serviceRunning -and $attempts -lt $maxAttempts) {
                Start-Sleep -Seconds 1
                $attempts++
                Write-Host "." -NoNewline -ForegroundColor Yellow
                
                try {
                    $statusCheck = Invoke-WebRequest -Uri "http://localhost:3000/api/status" -Method GET -TimeoutSec 1 -ErrorAction Stop
                    if ($statusCheck.StatusCode -eq 200) {
                        $serviceRunning = $true
                    }
                } catch {
                    # Service not ready yet
                }
            }
            
            Write-Host ""
            
            if ($serviceRunning) {
                Write-Host "Document Scanner service started successfully" -ForegroundColor Green
                return $true
            } else {
                Write-Host "Timed out waiting for service to start" -ForegroundColor Red
                return $false
            }
        } catch {
            Write-Host "Error starting service: $_" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "Start script not found: $startScript" -ForegroundColor Red
        return $false
    }
}

# Function to prepare test data
function Prepare-TestData {
    # Check if test data directory exists
    if (-not (Test-Path $testDataDir)) {
        New-Item -Path $testDataDir -ItemType Directory -Force | Out-Null
        
        # Create sample test files
        @"
Це тестовий документ для перевірки функціональності Document Scanner.
Він містить зразковий текст для перевірки можливості пошуку та індексації.

Ключові функції системи:
1. Сканування документів у різних форматах
2. Векторна індексація тексту
3. Семантичний пошук інформації
4. Взаємодія через чат-інтерфейс

Цей тестовий файл використовується для інтеграційного тестування.
"@ | Out-File -FilePath "$testDataDir\test_document_1.txt" -Encoding utf8
        
        @"
ІНФОРМАЦІЯ ПРО ПОДАТКОВУ ЗВІТНІСТЬ

Цей документ містить важливу інформацію щодо податкової звітності.

Періоди подання звітності:
- Щоквартально: до 20 числа місяця, наступного за звітним кварталом
- Щорічно: до 1 березня року, наступного за звітним

Форми звітності:
1. Декларація про прибуток підприємства
2. Звіт про суми нарахованого доходу застрахованих осіб
3. Податкова декларація з податку на додану вартість

При заповненні звітів необхідно вказувати точну інформацію та дотримуватись усіх вимог податкового законодавства.
"@ | Out-File -FilePath "$testDataDir\test_document_2.txt" -Encoding utf8
        
        @"
АНАЛІЗ ОСТАННІХ ФІНАНСОВИХ ПОКАЗНИКІВ

Даний документ представляє аналіз фінансових показників за останній квартал.

Основні показники:
1. Виручка: 1,245,000 грн
2. Чистий прибуток: 387,500 грн
3. Рентабельність: 31.1%
4. Коефіцієнт ліквідності: 1.8

Спостерігається зростання виручки на 12% порівняно з попереднім кварталом.
Прибуток зріс на 8.5% завдяки оптимізації операційних витрат.

Рекомендації:
- Збільшити інвестиції в маркетинг
- Розглянути можливість розширення асортименту продукції
- Впровадити нову CRM систему для покращення роботи з клієнтами
"@ | Out-File -FilePath "$testDataDir\test_document_3.txt" -Encoding utf8
        
        Write-Host "Created sample test documents in $testDataDir" -ForegroundColor Green
    } else {
        Write-Host "Using existing test data in $testDataDir" -ForegroundColor Yellow
    }
    
    # Count test files
    $fileCount = (Get-ChildItem -Path $testDataDir -File).Count
    
    if ($fileCount -eq 0) {
        Write-Host "No test files found in $testDataDir" -ForegroundColor Red
        return $false
    }
    
    Write-Host "Found $fileCount test files" -ForegroundColor Green
    return $true
}

# Function to process test documents
function Process-TestDocuments {
    # Check if batch processor script exists
    $batchScript = "$scriptsDir\batch-document-processor.ps1"
    
    if (-not (Test-Path $batchScript)) {
        Write-Host "Batch document processor script not found: $batchScript" -ForegroundColor Red
        return $false
    }
    
    Write-Host "Processing test documents..." -ForegroundColor Yellow
    
    # Get SMB share info from .env
    $smbHost = "localhost"
    $smbShare = "share"
    
    if (Test-Path $envPath) {
        $envContent = Get-Content -Path $envPath -Raw
        
        if ($envContent -match 'SMB_HOST=//([^/]+)/(.+)') {
            $smbHost = $matches[1]
            $smbShare = $matches[2]
        }
    }
    
    # Run batch processor
    try {
        & "$batchScript" -SourceDirectory $testDataDir -DestinationShare "\\$smbHost\$smbShare" -AutoScan
        return $true
    } catch {
        Write-Host "Error processing test documents: $_" -ForegroundColor Red
        return $false
    }
}

# Function to test API endpoints
function Test-ApiEndpoints {
    $endpoints = @(
        @{ Url = "/api/status"; Method = "GET"; Name = "Status API" },
        @{ Url = "/api/documents?page=1&limit=5"; Method = "GET"; Name = "Documents API" },
        @{ Url = "/api/search"; Method = "POST"; Body = @{ query = "податкова" } | ConvertTo-Json; Name = "Search API" }
    )
    
    $allPassed = $true
    
    foreach ($endpoint in $endpoints) {
        try {
            $params = @{
                Uri = "http://localhost:3000$($endpoint.Url)"
                Method = $endpoint.Method
                TimeoutSec = 5
                ErrorAction = "Stop"
            }
            
            if ($endpoint.Body) {
                $params.Body = $endpoint.Body
                $params.ContentType = "application/json"
            }
            
            $response = Invoke-WebRequest @params
            
            if ($response.StatusCode -eq 200) {
                Report-TestResult -TestName $endpoint.Name -Success $true
            } else {
                Report-TestResult -TestName $endpoint.Name -Success $false -Details "Status code: $($response.StatusCode)"
                $allPassed = $false
            }
        } catch {
            Report-TestResult -TestName $endpoint.Name -Success $false -Details $_.Exception.Message
            $allPassed = $false
        }
    }
    
    return $allPassed
}

# Function to test chat functionality
function Test-ChatFunctionality {
    $queryTests = @(
        @{ Query = "Розкажи про вміст документів"; Name = "Basic Document Information Query" },
        @{ Query = "Знайди інформацію про податкову звітність"; Name = "Specific Information Search" }
    )
    
    $allPassed = $true
    
    foreach ($test in $queryTests) {
        try {
            $requestBody = @{
                message = $test.Query
            } | ConvertTo-Json
            
            $response = Invoke-RestMethod -Uri "http://localhost:3000/api/openwebui/query" -Method POST -Body $requestBody -ContentType "application/json" -ErrorAction Stop
            
            # Check if response has expected properties
            if ($response.response -and $response.sources) {
                Report-TestResult -TestName $test.Name -Success $true
            } else {
                Report-TestResult -TestName $test.Name -Success $false -Details "Invalid response format"
                $allPassed = $false
            }
        } catch {
            Report-TestResult -TestName $test.Name -Success $false -Details $_.Exception.Message
            $allPassed = $false
        }
    }
    
    return $allPassed
}

# Function to test document preview
function Test-DocumentPreview {
    try {
        # Get a document ID first
        $docsResponse = Invoke-RestMethod -Uri "http://localhost:3000/api/documents?page=1&limit=1" -Method GET -ErrorAction Stop
        
        if ($docsResponse.documents -and $docsResponse.documents.Count -gt 0) {
            $docId = $docsResponse.documents[0].id
            
            # Test preview endpoint
            $previewResponse = Invoke-WebRequest -Uri "http://localhost:3000/api/documents/$docId/preview" -Method GET -ErrorAction Stop
            
            if ($previewResponse.StatusCode -eq 200 -and $previewResponse.Content -like "*<html*") {
                Report-TestResult -TestName "Document Preview" -Success $true
                return $true
            } else {
                Report-TestResult -TestName "Document Preview" -Success $false -Details "Invalid preview content"
                return $false
            }
        } else {
            Skip-Test -TestName "Document Preview" -Reason "No documents available for preview"
            return $false
        }
    } catch {
        Report-TestResult -TestName "Document Preview" -Success $false -Details $_.Exception.Message
        return $false
    }
}

# Main test execution
try {
    # Phase 1: Check required services
    Write-Host "`nPhase 1: Checking required services" -ForegroundColor Magenta
    $serviceCheck = Test-RequiredServices
    
    if (-not $serviceCheck.AllServicesOk) {
        if ($Interactive) {
            $continueAnyway = Read-Host "Some required services are not running. Continue anyway? (y/n)"
            if ($continueAnyway -ne 'y') {
                Write-Host "Test aborted" -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "Required services check failed" -ForegroundColor Red
            exit 1
        }
    }
    
    # Phase 2: Setup
    if (-not $SkipSetup) {
        Write-Host "`nPhase 2: Setup" -ForegroundColor Magenta
        
        # Prepare test data
        $dataReady = Prepare-TestData
        Report-TestResult -TestName "Test Data Preparation" -Success $dataReady
        
        # Start Document Scanner service
        $serviceRunning = Start-DocumentScannerService
        Report-TestResult -TestName "Service Startup" -Success $serviceRunning
        
        if (-not $serviceRunning) {
            Write-Host "Cannot proceed without Document Scanner service running" -ForegroundColor Red
            exit 1
        }
        
        # Process test documents (if full test)
        if ($FullTest) {
            $documentsProcessed = Process-TestDocuments
            Report-TestResult -TestName "Test Document Processing" -Success $documentsProcessed
        } else {
            Skip-Test -TestName "Test Document Processing" -Reason "Skipped (not in full test mode)"
        }
    } else {
        Write-Host "`nPhase 2: Setup (Skipped)" -ForegroundColor Yellow
        $serviceRunning = Test-DocumentScannerService
        
        if (-not $serviceRunning) {
            Write-Host "Cannot proceed without Document Scanner service running" -ForegroundColor Red
            exit 1
        }
    }
    
    # Phase 3: API Testing
    Write-Host "`nPhase 3: API Testing" -ForegroundColor Magenta
    $apiTestResult = Test-ApiEndpoints
    
    # Phase 4: Chat Functionality Testing
    Write-Host "`nPhase 4: Chat Functionality Testing" -ForegroundColor Magenta
    $chatTestResult = Test-ChatFunctionality
    
    # Phase 5: Document Preview Testing
    Write-Host "`nPhase 5: Document Preview Testing" -ForegroundColor Magenta
    $previewTestResult = Test-DocumentPreview
    
    # Summary
    Write-Host "`n===================================" -ForegroundColor Cyan
    Write-Host "Integration Test Results Summary" -ForegroundColor Cyan
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "Total Tests: $totalTests" -ForegroundColor White
    Write-Host "Passed: $passedTests" -ForegroundColor Green
    Write-Host "Failed: $failedTests" -ForegroundColor Red
    Write-Host "Skipped: $skippedTests" -ForegroundColor Yellow
    
    $successRate = [math]::Round(($passedTests / ($totalTests - $skippedTests)) * 100, 1)
    Write-Host "Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } elseif ($successRate -ge 60) { "Yellow" } else { "Red" })
    
    # Final status
    if ($failedTests -eq 0) {
        Write-Host "`nINTEGRATION TEST PASSED" -ForegroundColor Green
    } else {
        Write-Host "`nINTEGRATION TEST FAILED ($failedTests failed tests)" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Error during integration testing: $_" -ForegroundColor Red
    exit 1
}

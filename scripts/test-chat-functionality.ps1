# Chat Functionality Test Script
# This PowerShell script tests the Document Scanner chat interface functionality

Write-Host "Document Scanner - Chat Functionality Test" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Navigation to the application directory
$appPath = "C:\Users\Administrator\source\repos\document-scanner-service"
Set-Location -Path $appPath

# Test URL endpoints
function Test-Endpoint {
    param (
        [string]$Endpoint,
        [string]$Description
    )
    
    Write-Host "Testing $Description... " -NoNewline -ForegroundColor Yellow
    
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3000$Endpoint" -Method GET -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "OK ($($response.StatusCode))" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Failed ($($response.StatusCode))" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Failed (Error: $($_.Exception.Message))" -ForegroundColor Red
        return $false
    }
}

# Test Status API
$statusOk = Test-Endpoint -Endpoint "/api/status" -Description "API Status endpoint"

# Test Documents API
$documentsOk = Test-Endpoint -Endpoint "/api/documents?page=1&limit=5" -Description "API Documents endpoint"

# Test Web UI
$webUiOk = Test-Endpoint -Endpoint "/" -Description "Web UI"

# Check if Ollama is running
Write-Host "Checking Ollama status... " -NoNewline -ForegroundColor Yellow
try {
    $ollamaResponse = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -ErrorAction Stop
    Write-Host "OK (Running)" -ForegroundColor Green
    $ollamaOk = $true
} catch {
    Write-Host "Failed (Error: $($_.Exception.Message))" -ForegroundColor Red
    $ollamaOk = $false
}

# Overall status check
Write-Host "`nTest Results Summary:" -ForegroundColor Cyan
Write-Host "--------------------" -ForegroundColor Cyan
Write-Host "Web UI:      $($webUiOk ? 'OK ✓' : 'Failed ✗')" -ForegroundColor ($webUiOk ? 'Green' : 'Red')
Write-Host "API Status:  $($statusOk ? 'OK ✓' : 'Failed ✗')" -ForegroundColor ($statusOk ? 'Green' : 'Red')
Write-Host "API Docs:    $($documentsOk ? 'OK ✓' : 'Failed ✗')" -ForegroundColor ($documentsOk ? 'Green' : 'Red')
Write-Host "Ollama LLM:  $($ollamaOk ? 'OK ✓' : 'Failed ✗')" -ForegroundColor ($ollamaOk ? 'Green' : 'Red')

if ($webUiOk -and $statusOk -and $documentsOk -and $ollamaOk) {
    Write-Host "`nChat system is ready to use!" -ForegroundColor Green
    
    # Open browser if everything is OK
    $openBrowser = Read-Host "Would you like to open the chat interface in your browser? (y/n)"
    if ($openBrowser -eq 'y') {
        Start-Process "http://localhost:3000"
    }
} else {
    Write-Host "`nSome components of the chat system are not working properly." -ForegroundColor Red
    Write-Host "Please check the logs and ensure all services are running." -ForegroundColor Yellow
    
    # Offer to restart the service
    $restart = Read-Host "Would you like to restart the document scanner service? (y/n)"
    if ($restart -eq 'y') {
        # Stop and restart the service
        $appProcess = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*document-scanner*" }
        
        if ($appProcess) {
            Write-Host "Stopping existing service..." -ForegroundColor Yellow
            Stop-Process -Id $appProcess.Id -Force
            Start-Sleep -Seconds 2
        }
        
        Write-Host "Starting service..." -ForegroundColor Green
        Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", "Set-Location '$appPath'; npm start"
    }
}

Write-Host "`nChat functionality test completed!" -ForegroundColor Cyan

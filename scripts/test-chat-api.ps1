# Chat API Test Script
# This PowerShell script tests the Document Scanner chat functionality by making API calls to test the LLM integration

param (
    [switch]$Verbose = $false
)

Write-Host "Document Scanner - Chat API Test" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

# Set paths
$appPath = "C:\Users\Administrator\source\repos\document-scanner-service"
$logPath = "$appPath\logs"

# Validate server is running
Write-Host "Checking if service is running..." -ForegroundColor Yellow
try {
    $statusResponse = Invoke-WebRequest -Uri "http://localhost:3000/api/status" -Method GET -ErrorAction Stop
    if ($statusResponse.StatusCode -eq 200) {
        Write-Host "Service is running!" -ForegroundColor Green
        $statusResult = $statusResponse.Content | ConvertFrom-Json
        Write-Host "Documents count: $($statusResult.documentsCount)" -ForegroundColor White
    }
} catch {
    Write-Host "Error: Service is not running" -ForegroundColor Red
    Write-Host "Please start the service first with .\scripts\start-document-scanner.ps1" -ForegroundColor Yellow
    exit 1
}

# Function to test the chat API
function Test-ChatAPI {
    param (
        [string]$QueryText,
        [string]$TestName
    )
    
    Write-Host "`nTest: $TestName" -ForegroundColor Cyan
    Write-Host "Query: '$QueryText'" -ForegroundColor Yellow
    
    try {
        $requestBody = @{
            message = $QueryText
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "http://localhost:3000/api/openwebui/query" -Method POST -Body $requestBody -ContentType "application/json" -ErrorAction Stop
        
        Write-Host "Response: " -ForegroundColor Green
        Write-Host $response.response -ForegroundColor White
        
        if ($Verbose) {
            Write-Host "`nSources:" -ForegroundColor Magenta
            foreach ($source in $response.sources) {
                Write-Host "- $($source.filename) (Similarity: $([math]::Round($source.similarity * 100, 2))%)" -ForegroundColor Gray
                Write-Host "  Content snippet: $($source.content.Substring(0, [Math]::Min(100, $source.content.Length)))..." -ForegroundColor Gray
            }
            
            Write-Host "`nModel: $($response.model)" -ForegroundColor Magenta
            if ($response.usage) {
                Write-Host "Tokens: $($response.usage.prompt_tokens) prompt, $($response.usage.completion_tokens) completion, $($response.usage.total_tokens) total" -ForegroundColor Magenta
            }
        }
        
        return $true
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        return $false
    }
}

# Run tests
$testsPassed = 0
$testsTotal = 0

Write-Host "`nRunning chat API tests..." -ForegroundColor Yellow

# Test 1: Basic information query
$testsTotal++
if (Test-ChatAPI -QueryText "Розкажи про вміст документів" -TestName "Basic Information Query") {
    $testsPassed++
}

# Test 2: Specific document query (requires documents in the system)
$testsTotal++
if (Test-ChatAPI -QueryText "Знайди інформацію про податкову звітність" -TestName "Specific Information Search") {
    $testsPassed++
}

# Test 3: Latest document summary
$testsTotal++
if (Test-ChatAPI -QueryText "Узагальни останній документ" -TestName "Latest Document Summary") {
    $testsPassed++
}

# Test 4: Error handling (intentionally complex or unsupported query)
$testsTotal++
if (Test-ChatAPI -QueryText "Напиши мені складний SQL запит для аналізу документів" -TestName "Complex/Unsupported Query") {
    $testsPassed++
}

# Display test results
Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "Chat API Test Results: $testsPassed/$testsTotal passed" -ForegroundColor ([int]$testsPassed -eq [int]$testsTotal ? 'Green' : 'Yellow')
Write-Host "=====================================" -ForegroundColor Cyan

# Helper information
Write-Host "`nUseful commands:" -ForegroundColor Magenta
Write-Host "- Start service: .\scripts\start-document-scanner.ps1" -ForegroundColor White
Write-Host "- Open chat interface: Start-Process 'http://localhost:3000'" -ForegroundColor White
Write-Host "- Test with verbose output: .\scripts\test-chat-api.ps1 -Verbose" -ForegroundColor White

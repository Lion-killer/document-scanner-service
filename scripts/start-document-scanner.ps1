# Document Scanner Launch Script
# This PowerShell script launches the Document Scanner service and opens the chat interface

$ErrorActionPreference = "Stop"

Write-Host "Document Scanner Service - Launcher" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

# Set paths
$appPath = "C:\Users\Administrator\source\repos\document-scanner-service"
$logPath = "$appPath\logs"

# Ensure log directory exists
if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory | Out-Null
    Write-Host "Created logs directory" -ForegroundColor Yellow
}

# Check if the service is already running
$isRunning = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*document-scanner*" }

if ($isRunning) {
    Write-Host "Document Scanner service is already running" -ForegroundColor Green
} else {
    Write-Host "Starting Document Scanner service..." -ForegroundColor Yellow
    
    # Navigate to the app directory
    Set-Location -Path $appPath
    
    # Check for npm install needed
    if (-not (Test-Path "$appPath\node_modules")) {
        Write-Host "Installing dependencies..." -ForegroundColor Yellow
        npm install
    }
    
    # Build if needed
    if (-not (Test-Path "$appPath\dist\app.js")) {
        Write-Host "Building application..." -ForegroundColor Yellow
        npm run build
    }
    
    # Start the application in the background
    Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", "Set-Location '$appPath'; npm start > '$logPath\app_console.log' 2>&1" -WindowStyle Hidden
    
    # Wait for service to start
    $maxWaitSeconds = 30
    $waitInterval = 1
    $waitTime = 0
    $serviceStarted = $false
    
    Write-Host "Waiting for service to start..." -ForegroundColor Yellow
    
    while ($waitTime -lt $maxWaitSeconds -and -not $serviceStarted) {
        Start-Sleep -Seconds $waitInterval
        $waitTime += $waitInterval
        
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:3000/api/status" -Method GET -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                $serviceStarted = $true
                Write-Host "Service started successfully!" -ForegroundColor Green
            }
        } catch {
            # Still waiting
            Write-Host "." -NoNewline -ForegroundColor Yellow
        }
    }
    
    if (-not $serviceStarted) {
        Write-Host "`nService failed to start in the expected time" -ForegroundColor Red
        Write-Host "Check logs at $logPath\app_console.log for details" -ForegroundColor Yellow
        
        $viewLogs = Read-Host "Would you like to view the logs now? (y/n)"
        if ($viewLogs -eq 'y') {
            Get-Content "$logPath\app_console.log" -Tail 20
        }
        
        exit 1
    }
}

# Open browser
$openBrowser = Read-Host "Would you like to open the Document Scanner in your browser? (y/n)"
if ($openBrowser -eq 'y') {
    Start-Process "http://localhost:3000"
}

Write-Host "Document Scanner chat interface is ready to use!" -ForegroundColor Green
Write-Host "Access it at: http://localhost:3000" -ForegroundColor Cyan

# Show service management options
Write-Host "`nService Management:" -ForegroundColor Cyan
Write-Host "1. View service logs" -ForegroundColor White
Write-Host "2. Restart service" -ForegroundColor White 
Write-Host "3. Stop service" -ForegroundColor White
Write-Host "4. Exit" -ForegroundColor White

$option = Read-Host "Enter option (1-4)"

switch ($option) {
    "1" {
        if (Test-Path "$logPath\app_console.log") {
            Get-Content "$logPath\app_console.log" -Tail 50
        } else {
            Write-Host "No log file found" -ForegroundColor Red
        }
    }
    "2" {
        Write-Host "Restarting service..." -ForegroundColor Yellow
        Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*document-scanner*" } | Stop-Process -Force
        Start-Sleep -Seconds 2
        & "$PSScriptRoot\start-document-scanner.ps1"
    }
    "3" {
        Write-Host "Stopping service..." -ForegroundColor Yellow
        Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*document-scanner*" } | Stop-Process -Force
        Write-Host "Service stopped" -ForegroundColor Green
    }
    "4" {
        # Exit
    }
    default {
        Write-Host "Invalid option" -ForegroundColor Red
    }
}

Write-Host "Script completed" -ForegroundColor Cyan

# Chat Interface Update Script
# This PowerShell script updates the Document Scanner chat interface

Write-Host "Document Scanner - Chat Interface Update Script" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# Check if the application is running
$appProcess = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*document-scanner*" }

if ($appProcess) {
    Write-Host "Stopping existing Document Scanner service..." -ForegroundColor Yellow
    Stop-Process -Id $appProcess.Id -Force
    Start-Sleep -Seconds 2
}

# Navigate to the application directory
$appPath = "C:\Users\Administrator\source\repos\document-scanner-service"
Set-Location -Path $appPath

# Update npm packages if needed
Write-Host "Checking for package updates..." -ForegroundColor Yellow
npm install

# Build the application
Write-Host "Building application..." -ForegroundColor Yellow
npm run build

# Start the application
Write-Host "Starting Document Scanner service..." -ForegroundColor Green
Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", "Set-Location '$appPath'; npm start"

# Wait for the application to start
Start-Sleep -Seconds 3

# Open the browser
Write-Host "Opening web browser..." -ForegroundColor Green
Start-Process "http://localhost:3000"

Write-Host "Chat interface update complete!" -ForegroundColor Cyan

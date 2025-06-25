# Collect System Logs Script
# This PowerShell script collects logs from all system components for diagnostics

param(
    [int]$DaysBack = 2,                # How many days of logs to collect
    [string]$OutputDir = "",           # Where to save the log archive
    [switch]$IncludeVectorDBDump = $false   # Include dump of the vector database
)

Write-Host "Document Scanner - System Log Collector" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Set paths
$appPath = "C:\Users\Administrator\source\repos\document-scanner-service"
$envPath = "$appPath\.env"
$logsPath = "$appPath\logs"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Determine output directory
if (-not $OutputDir) {
    $OutputDir = "$appPath\diagnostics"
}

if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    Write-Host "Created output directory at $OutputDir" -ForegroundColor Yellow
}

# Create temp directory for logs
$tempDir = "$env:TEMP\docscanner_logs_$timestamp"
New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

Write-Host "Collecting logs from the past $DaysBack days..." -ForegroundColor Yellow

# Function to get environment variables
function Get-EnvironmentConfig {
    if (Test-Path $envPath) {
        $envContent = Get-Content -Path $envPath -Raw
        $config = @{}
        
        # Extract SMB_HOST
        if ($envContent -match 'SMB_HOST=(.+)') {
            $smbConfig = $matches[1].Trim()
            
            # Parse SMB host and share
            if ($smbConfig -match '//([^/]+)/(.+)') {
                $config.SmbHost = $matches[1]
                $config.SmbShare = $matches[2]
            }
        }
        
        # Extract Ollama URL
        if ($envContent -match 'OLLAMA_URL=(.+)') {
            $config.OllamaUrl = $matches[1].Trim()
        } else {
            $config.OllamaUrl = "http://localhost:11434"
        }
        
        # Extract Qdrant URL
        if ($envContent -match 'QDRANT_URL=(.+)') {
            $config.QdrantUrl = $matches[1].Trim()
        } else {
            $config.QdrantUrl = "http://localhost:6333"
        }
        
        # Extract LOG_FILE
        if ($envContent -match 'LOG_FILE=(.+)') {
            $config.LogFile = $matches[1].Trim()
        } else {
            $config.LogFile = "logs/app.log"
        }
        
        return $config
    } else {
        Write-Host "Warning: .env file not found" -ForegroundColor Yellow
        return @{
            SmbHost = "localhost"
            SmbShare = "share"
            OllamaUrl = "http://localhost:11434"
            QdrantUrl = "http://localhost:6333"
            LogFile = "logs/app.log"
        }
    }
}

# Function to collect application logs
function Collect-ApplicationLogs {
    Write-Host "Collecting application logs..." -ForegroundColor Yellow
    
    $config = Get-EnvironmentConfig
    $logFile = Join-Path -Path $appPath -ChildPath $config.LogFile
    
    # Create log directory in temp
    $appLogDir = "$tempDir\application_logs"
    New-Item -Path $appLogDir -ItemType Directory -Force | Out-Null
    
    # Copy log file if it exists
    if (Test-Path $logFile) {
        Copy-Item -Path $logFile -Destination "$appLogDir\app.log"
        Write-Host "  √ Copied main application log" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Main application log not found at $logFile" -ForegroundColor Red
    }
    
    # Copy all logs from the logs directory
    if (Test-Path $logsPath) {
        $logFiles = Get-ChildItem -Path $logsPath -Filter "*.log" -Recurse
        
        if ($logFiles.Count -gt 0) {
            foreach ($log in $logFiles) {
                # Check if the log file is within the date range
                $logDate = $log.LastWriteTime
                $daysOld = (New-TimeSpan -Start $logDate -End (Get-Date)).Days
                
                if ($daysOld -le $DaysBack) {
                    Copy-Item -Path $log.FullName -Destination "$appLogDir\$($log.Name)"
                }
            }
            Write-Host "  √ Copied $($logFiles.Count) log files from logs directory" -ForegroundColor Green
        } else {
            Write-Host "  - No log files found in logs directory" -ForegroundColor Yellow
        }
    }
    
    # Get npm and node versions
    try {
        $nodeVersion = node --version
        $npmVersion = npm --version
        
        @"
Node.js version: $nodeVersion
npm version: $npmVersion
"@ | Out-File -FilePath "$appLogDir\versions.txt" -Encoding utf8
        
        Write-Host "  √ Collected version information" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Failed to collect version information" -ForegroundColor Red
    }
    
    # Collect package.json info
    if (Test-Path "$appPath\package.json") {
        Copy-Item -Path "$appPath\package.json" -Destination "$appLogDir\package.json"
        Write-Host "  √ Copied package.json" -ForegroundColor Green
    }
}

# Function to collect system event logs
function Collect-WindowsEventLogs {
    Write-Host "Collecting Windows event logs..." -ForegroundColor Yellow
    
    $eventLogDir = "$tempDir\windows_event_logs"
    New-Item -Path $eventLogDir -ItemType Directory -Force | Out-Null
    
    # Get Application and System event logs
    $cutoffDate = (Get-Date).AddDays(-$DaysBack)
    
    # Application log
    $applicationEvents = Get-WinEvent -LogName Application -MaxEvents 1000 | Where-Object { $_.TimeCreated -ge $cutoffDate }
    $applicationEvents | Export-Clixml -Path "$eventLogDir\application_events.xml"
    Write-Host "  √ Collected Application event logs" -ForegroundColor Green
    
    # System log
    $systemEvents = Get-WinEvent -LogName System -MaxEvents 1000 | Where-Object { $_.TimeCreated -ge $cutoffDate }
    $systemEvents | Export-Clixml -Path "$eventLogDir\system_events.xml"
    Write-Host "  √ Collected System event logs" -ForegroundColor Green
    
    # Filter for Node.js events
    $nodeEvents = $applicationEvents | Where-Object { $_.ProviderName -like "*Node*" -or $_.Message -like "*node*" }
    if ($nodeEvents) {
        $nodeEvents | Export-Clixml -Path "$eventLogDir\node_events.xml"
        Write-Host "  √ Collected Node.js-specific events" -ForegroundColor Green
    }
}

# Function to collect service status
function Collect-ServiceStatus {
    Write-Host "Collecting service status..." -ForegroundColor Yellow
    
    $statusDir = "$tempDir\service_status"
    New-Item -Path $statusDir -ItemType Directory -Force | Out-Null
    
    $config = Get-EnvironmentConfig
    
    # Document Scanner service status
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3000/api/status" -Method GET -TimeoutSec 3 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $response.Content | Out-File -FilePath "$statusDir\document_scanner_status.json" -Encoding utf8
            Write-Host "  √ Collected Document Scanner status" -ForegroundColor Green
        }
    } catch {
        "Service unavailable: $($_.Exception.Message)" | Out-File -FilePath "$statusDir\document_scanner_status.txt" -Encoding utf8
        Write-Host "  ✗ Document Scanner service not available" -ForegroundColor Red
    }
    
    # Ollama status
    try {
        $response = Invoke-WebRequest -Uri "$($config.OllamaUrl)/api/tags" -Method GET -TimeoutSec 3 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $response.Content | Out-File -FilePath "$statusDir\ollama_status.json" -Encoding utf8
            Write-Host "  √ Collected Ollama status" -ForegroundColor Green
        }
    } catch {
        "Service unavailable: $($_.Exception.Message)" | Out-File -FilePath "$statusDir\ollama_status.txt" -Encoding utf8
        Write-Host "  ✗ Ollama service not available" -ForegroundColor Red
    }
    
    # Qdrant status
    try {
        $response = Invoke-WebRequest -Uri "$($config.QdrantUrl)/collections" -Method GET -TimeoutSec 3 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $response.Content | Out-File -FilePath "$statusDir\qdrant_status.json" -Encoding utf8
            Write-Host "  √ Collected Qdrant status" -ForegroundColor Green
        }
    } catch {
        "Service unavailable: $($_.Exception.Message)" | Out-File -FilePath "$statusDir\qdrant_status.txt" -Encoding utf8
        Write-Host "  ✗ Qdrant service not available" -ForegroundColor Red
    }
    
    # Running processes
    Get-Process | Where-Object { $_.ProcessName -in @("node", "npm", "ollama", "qdrant") -or $_.CommandLine -like "*document-scanner*" } | 
        Format-List | Out-File -FilePath "$statusDir\relevant_processes.txt" -Encoding utf8
    Write-Host "  √ Collected process information" -ForegroundColor Green
}

# Function to collect network information
function Collect-NetworkInfo {
    Write-Host "Collecting network information..." -ForegroundColor Yellow
    
    $networkDir = "$tempDir\network_info"
    New-Item -Path $networkDir -ItemType Directory -Force | Out-Null
    
    # Network connections
    netstat -ano | Out-File -FilePath "$networkDir\netstat.txt" -Encoding utf8
    Write-Host "  √ Collected network connections" -ForegroundColor Green
    
    # Network interface information
    ipconfig /all | Out-File -FilePath "$networkDir\ipconfig.txt" -Encoding utf8
    Write-Host "  √ Collected network interface information" -ForegroundColor Green
    
    # Ping tests
    $config = Get-EnvironmentConfig
    
    @"
Ping test results:

"@ | Out-File -FilePath "$networkDir\ping_tests.txt" -Encoding utf8
    
    try {
        "Testing localhost:" | Out-File -FilePath "$networkDir\ping_tests.txt" -Append -Encoding utf8
        ping localhost | Out-File -FilePath "$networkDir\ping_tests.txt" -Append -Encoding utf8
        
        "Testing Ollama host:" | Out-File -FilePath "$networkDir\ping_tests.txt" -Append -Encoding utf8
        $ollamaHost = $config.OllamaUrl -replace "http[s]?://", "" -replace "/.*", "" -replace ":[0-9]+", ""
        ping $ollamaHost | Out-File -FilePath "$networkDir\ping_tests.txt" -Append -Encoding utf8
        
        "Testing Qdrant host:" | Out-File -FilePath "$networkDir\ping_tests.txt" -Append -Encoding utf8
        $qdrantHost = $config.QdrantUrl -replace "http[s]?://", "" -replace "/.*", "" -replace ":[0-9]+", ""
        ping $qdrantHost | Out-File -FilePath "$networkDir\ping_tests.txt" -Append -Encoding utf8
        
        "Testing SMB host:" | Out-File -FilePath "$networkDir\ping_tests.txt" -Append -Encoding utf8
        ping $config.SmbHost | Out-File -FilePath "$networkDir\ping_tests.txt" -Append -Encoding utf8
        
        Write-Host "  √ Collected ping test results" -ForegroundColor Green
    } catch {
        "Error performing ping tests: $($_.Exception.Message)" | Out-File -FilePath "$networkDir\ping_tests.txt" -Append -Encoding utf8
        Write-Host "  ✗ Error in ping tests" -ForegroundColor Red
    }
    
    # SMB connection test
    try {
        @"
SMB Connection Test:

"@ | Out-File -FilePath "$networkDir\smb_connection.txt" -Encoding utf8
        
        "Testing connection to SMB share:" | Out-File -FilePath "$networkDir\smb_connection.txt" -Append -Encoding utf8
        net view "\\$($config.SmbHost)" 2>&1 | Out-File -FilePath "$networkDir\smb_connection.txt" -Append -Encoding utf8
        
        "Available shares:" | Out-File -FilePath "$networkDir\smb_connection.txt" -Append -Encoding utf8
        net view "\\$($config.SmbHost)" 2>&1 | Out-File -FilePath "$networkDir\smb_connection.txt" -Append -Encoding utf8
        
        Write-Host "  √ Collected SMB connection information" -ForegroundColor Green
    } catch {
        "Error testing SMB connection: $($_.Exception.Message)" | Out-File -FilePath "$networkDir\smb_connection.txt" -Append -Encoding utf8
        Write-Host "  ✗ Error in SMB connection tests" -ForegroundColor Red
    }
}

# Function to collect vector database information
function Collect-VectorDBInfo {
    if (-not $IncludeVectorDBDump) {
        Write-Host "Skipping vector database dump (use -IncludeVectorDBDump to enable)" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Collecting vector database information..." -ForegroundColor Yellow
    
    $vectorDbDir = "$tempDir\vector_db"
    New-Item -Path $vectorDbDir -ItemType Directory -Force | Out-Null
    
    $config = Get-EnvironmentConfig
    
    # Collections overview
    try {
        $response = Invoke-WebRequest -Uri "$($config.QdrantUrl)/collections" -Method GET -TimeoutSec 5 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $response.Content | Out-File -FilePath "$vectorDbDir\collections.json" -Encoding utf8
            Write-Host "  √ Collected Qdrant collections list" -ForegroundColor Green
            
            # Try to extract collection name from .env
            $collectionName = "documents"
            if (Test-Path $envPath) {
                $envContent = Get-Content -Path $envPath -Raw
                if ($envContent -match 'QDRANT_COLLECTION=(.+)') {
                    $collectionName = $matches[1].Trim()
                }
            }
            
            # Get collection info
            try {
                $response = Invoke-WebRequest -Uri "$($config.QdrantUrl)/collections/$collectionName" -Method GET -TimeoutSec 5 -ErrorAction Stop
                if ($response.StatusCode -eq 200) {
                    $response.Content | Out-File -FilePath "$vectorDbDir\collection_info.json" -Encoding utf8
                    Write-Host "  √ Collected $collectionName collection info" -ForegroundColor Green
                }
            } catch {
                "Error getting collection info: $($_.Exception.Message)" | Out-File -FilePath "$vectorDbDir\collection_info_error.txt" -Encoding utf8
                Write-Host "  ✗ Failed to get collection info" -ForegroundColor Red
            }
            
            # Get points
            try {
                # Limit to 100 points to avoid huge dumps
                $body = @{
                    limit = 100
                    with_payload = $true
                    with_vector = $false
                } | ConvertTo-Json
                
                $response = Invoke-WebRequest -Uri "$($config.QdrantUrl)/collections/$collectionName/points/scroll" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 10 -ErrorAction Stop
                if ($response.StatusCode -eq 200) {
                    $response.Content | Out-File -FilePath "$vectorDbDir\vector_points_sample.json" -Encoding utf8
                    Write-Host "  √ Collected vector points sample (100 points)" -ForegroundColor Green
                }
            } catch {
                "Error getting vector points: $($_.Exception.Message)" | Out-File -FilePath "$vectorDbDir\vector_points_error.txt" -Encoding utf8
                Write-Host "  ✗ Failed to get vector points" -ForegroundColor Red
            }
        }
    } catch {
        "Error connecting to Qdrant: $($_.Exception.Message)" | Out-File -FilePath "$vectorDbDir\qdrant_error.txt" -Encoding utf8
        Write-Host "  ✗ Failed to connect to Qdrant" -ForegroundColor Red
    }
}

# Function to collect system information
function Collect-SystemInfo {
    Write-Host "Collecting system information..." -ForegroundColor Yellow
    
    $sysInfoDir = "$tempDir\system_info"
    New-Item -Path $sysInfoDir -ItemType Directory -Force | Out-Null
    
    # System info
    systeminfo | Out-File -FilePath "$sysInfoDir\system_info.txt" -Encoding utf8
    Write-Host "  √ Collected system information" -ForegroundColor Green
    
    # Disk space
    Get-PSDrive -PSProvider 'FileSystem' | Out-File -FilePath "$sysInfoDir\disk_space.txt" -Encoding utf8
    Write-Host "  √ Collected disk space information" -ForegroundColor Green
    
    # Installed programs
    Get-WmiObject -Class Win32_Product | Select-Object Name, Version, Vendor | 
        Sort-Object -Property Name | Out-File -FilePath "$sysInfoDir\installed_programs.txt" -Encoding utf8
    Write-Host "  √ Collected installed programs list" -ForegroundColor Green
    
    # .env file (with passwords masked)
    if (Test-Path $envPath) {
        $envContent = Get-Content -Path $envPath -Raw
        
        # Mask sensitive information
        $maskedContent = $envContent -replace '(PASSWORD|SECRET|KEY)=([^"\r\n]+)', '$1=********'
        
        $maskedContent | Out-File -FilePath "$sysInfoDir\env_settings_masked.txt" -Encoding utf8
        Write-Host "  √ Collected masked environment settings" -ForegroundColor Green
    }
}

# Collect information
Collect-ApplicationLogs
Collect-WindowsEventLogs
Collect-ServiceStatus
Collect-NetworkInfo
Collect-VectorDBInfo
Collect-SystemInfo

# Create diagnostic archive
$archiveName = "document_scanner_logs_$timestamp.zip"
$archivePath = Join-Path -Path $OutputDir -ChildPath $archiveName

Write-Host "`nCreating diagnostic archive..." -ForegroundColor Yellow

try {
    Compress-Archive -Path "$tempDir\*" -DestinationPath $archivePath -Force
    Write-Host "Diagnostic information collected and saved to: $archivePath" -ForegroundColor Green
} catch {
    Write-Host "Error creating archive: $_" -ForegroundColor Red
    Write-Host "Logs are available in the temp directory: $tempDir" -ForegroundColor Yellow
    exit 1
}

# Clean up temp directory
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`nDiagnostic collection complete!" -ForegroundColor Cyan
Write-Host "Archive created at: $archivePath" -ForegroundColor Green

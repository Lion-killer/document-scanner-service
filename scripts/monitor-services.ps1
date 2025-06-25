# Monitor Document Scanner Components
# This PowerShell script monitors the Document Scanner service and its dependencies

param(
    [int]$RefreshInterval = 5,  # seconds
    [int]$MaxRefreshes = 100    # maximum number of refreshes
)

function Show-Header {
    Clear-Host
    Write-Host "Document Scanner Service - System Monitor" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to exit" -ForegroundColor Yellow
    Write-Host "Last update: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
}

function Check-ServiceStatus {
    param (
        [string]$ServiceName,
        [string]$Url
    )
    
    try {
        $response = Invoke-WebRequest -Uri $Url -Method GET -TimeoutSec 3 -ErrorAction Stop
        return @{
            Status = "Running"
            StatusCode = $response.StatusCode
            Success = $true
        }
    } catch [System.Net.WebException] {
        $ex = $_.Exception
        if ($null -ne $ex.Response) {
            return @{
                Status = "Error"
                StatusCode = [int]$ex.Response.StatusCode
                Success = $false
                Message = $ex.Message
            }
        } else {
            return @{
                Status = "Offline"
                StatusCode = 0
                Success = $false
                Message = $ex.Message
            }
        }
    } catch {
        return @{
            Status = "Error"
            StatusCode = 0
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Format-SizeValue {
    param (
        [double]$Size
    )
    
    if ($Size -gt 1GB) {
        return "{0:N2} GB" -f ($Size / 1GB)
    } elseif ($Size -gt 1MB) {
        return "{0:N2} MB" -f ($Size / 1MB)
    } elseif ($Size -gt 1KB) {
        return "{0:N2} KB" -f ($Size / 1KB)
    } else {
        return "{0:N0} bytes" -f $Size
    }
}

# Main monitoring loop
$refreshCount = 0
$startTime = Get-Date

try {
    while (($refreshCount -lt $MaxRefreshes) -or ($MaxRefreshes -eq 0)) {
        Show-Header
        
        # Check system metrics
        $cpuUsage = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
        $memoryUsage = Get-Counter '\Memory\Available MBytes' -ErrorAction SilentlyContinue
        $diskInfo = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        
        Write-Host "System Resources:" -ForegroundColor White
        if ($cpuUsage) {
            $cpuValue = [math]::Round($cpuUsage.CounterSamples[0].CookedValue, 1)
            $cpuColor = if ($cpuValue -gt 80) { "Red" } elseif ($cpuValue -gt 50) { "Yellow" } else { "Green" }
            Write-Host "  CPU Usage: " -NoNewline
            Write-Host "$cpuValue%" -ForegroundColor $cpuColor
        }
        
        if ($memoryUsage) {
            $memValue = [math]::Round($memoryUsage.CounterSamples[0].CookedValue, 0)
            $memColor = if ($memValue -lt 500) { "Red" } elseif ($memValue -lt 1000) { "Yellow" } else { "Green" }
            Write-Host "  Memory Available: " -NoNewline
            Write-Host "$memValue MB" -ForegroundColor $memColor
        }
        
        if ($diskInfo) {
            $freeSpace = [math]::Round($diskInfo.FreeSpace / 1GB, 2)
            $totalSpace = [math]::Round($diskInfo.Size / 1GB, 2)
            $percentFree = [math]::Round(($diskInfo.FreeSpace / $diskInfo.Size) * 100, 1)
            $diskColor = if ($percentFree -lt 10) { "Red" } elseif ($percentFree -lt 20) { "Yellow" } else { "Green" }
            
            Write-Host "  Disk Space (C:): " -NoNewline
            Write-Host "$freeSpace GB free of $totalSpace GB ($percentFree%)" -ForegroundColor $diskColor
        }
        
        # Check Node.js processes
        Write-Host "`nProcesses:" -ForegroundColor White
        $nodeProcess = Get-Process -Name "node" -ErrorAction SilentlyContinue | 
                      Where-Object { $_.CommandLine -match "document-scanner" }
        
        if ($nodeProcess) {
            $nodeColor = "Green"
            $uptime = (Get-Date) - $nodeProcess.StartTime
            $uptimeStr = "{0:D2}h:{1:D2}m:{2:D2}s" -f $uptime.Hours, $uptime.Minutes, $uptime.Seconds
            $memUsage = Format-SizeValue $nodeProcess.WorkingSet64
            
            Write-Host "  Document Scanner: " -NoNewline
            Write-Host "Running (PID: $($nodeProcess.Id), Memory: $memUsage, Uptime: $uptimeStr)" -ForegroundColor $nodeColor
        } else {
            Write-Host "  Document Scanner: " -NoNewline
            Write-Host "Not running" -ForegroundColor "Red"
        }
        
        # Check services
        Write-Host "`nServices:" -ForegroundColor White
        
        # Document Scanner API
        $scannerStatus = Check-ServiceStatus -ServiceName "Document Scanner" -Url "http://localhost:3000/api/status"
        Write-Host "  Document Scanner API: " -NoNewline
        if ($scannerStatus.Success) {
            $statusJson = (Invoke-RestMethod -Uri "http://localhost:3000/api/status" -ErrorAction SilentlyContinue)
            Write-Host "Online" -ForegroundColor "Green" -NoNewline
            Write-Host " (Docs: $($statusJson.documentsCount), Last scan: $($statusJson.lastScan))"
        } else {
            Write-Host $scannerStatus.Status -ForegroundColor "Red"
        }
        
        # Ollama
        $ollamaStatus = Check-ServiceStatus -ServiceName "Ollama" -Url "http://localhost:11434/api/tags"
        Write-Host "  Ollama: " -NoNewline
        if ($ollamaStatus.Success) {
            $models = (Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -ErrorAction SilentlyContinue).models
            Write-Host "Online" -ForegroundColor "Green" -NoNewline
            Write-Host " (Models: $($models.Count))"
        } else {
            Write-Host $ollamaStatus.Status -ForegroundColor "Red"
        }
        
        # Qdrant
        $qdrantStatus = Check-ServiceStatus -ServiceName "Qdrant" -Url "http://localhost:6333/collections"
        Write-Host "  Qdrant: " -NoNewline
        if ($qdrantStatus.Success) {
            $collections = (Invoke-RestMethod -Uri "http://localhost:6333/collections" -ErrorAction SilentlyContinue).result.collections
            Write-Host "Online" -ForegroundColor "Green" -NoNewline
            Write-Host " (Collections: $($collections.Count))"
        } else {
            Write-Host $qdrantStatus.Status -ForegroundColor "Red"
        }
        
        # OpenWebUI (optional)
        $openwebStatus = Check-ServiceStatus -ServiceName "OpenWebUI" -Url "http://localhost:8080"
        Write-Host "  OpenWebUI: " -NoNewline
        if ($openwebStatus.Success) {
            Write-Host "Online" -ForegroundColor "Green"
        } else {
            Write-Host $openwebStatus.Status -ForegroundColor "Yellow" -NoNewline
            Write-Host " (Optional)" -ForegroundColor "Gray"
        }
        
        # Show instructions and stats
        $runTime = (Get-Date) - $startTime
        $runTimeStr = "{0:D2}h:{1:D2}m:{2:D2}s" -f $runTime.Hours, $runTime.Minutes, $runTime.Seconds
        
        Write-Host "`nMonitor running for: $runTimeStr" -ForegroundColor DarkGray
        Write-Host "Next refresh in $RefreshInterval seconds..." -ForegroundColor DarkGray
        
        $refreshCount++
        Start-Sleep -Seconds $RefreshInterval
    }
} catch {
    Write-Host "`nMonitoring stopped: $_" -ForegroundColor Red
} finally {
    Write-Host "`nMonitoring completed after $refreshCount refreshes" -ForegroundColor Cyan
}

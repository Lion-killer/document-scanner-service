# Batch Document Processor Script
# This script helps to process multiple documents for testing the document scanner functionality

param(
    [string]$SourceDirectory = "",  # Source directory containing documents
    [string]$DestinationShare = "", # SMB share destination
    [switch]$CopyOnly = $false,     # Only copy files, don't process
    [switch]$ProcessOnly = $false,  # Only process existing files, don't copy
    [switch]$AutoScan = $true,      # Trigger scan after processing
    [string]$FileTypes = ".pdf,.doc,.docx,.txt,.rtf,.odt,.xls,.xlsx"  # File types to process
)

Write-Host "Document Scanner - Batch Document Processor" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Set paths
$appPath = "C:\Users\Administrator\source\repos\document-scanner-service"
$envPath = "$appPath\.env"
$tempDir = "$env:TEMP\docscanner_batch"

# Read SMB configuration from .env
$smbHost = ""
$smbShare = ""
$smbUsername = ""
$smbPassword = ""

if (Test-Path $envPath) {
    Write-Host "Reading SMB configuration from .env file..." -ForegroundColor Yellow
    
    $envContent = Get-Content -Path $envPath -Raw
    
    # Extract SMB_HOST
    if ($envContent -match 'SMB_HOST=(.+)') {
        $smbConfig = $matches[1].Trim()
        
        # Parse SMB host and share
        if ($smbConfig -match '//([^/]+)/(.+)') {
            $smbHost = $matches[1]
            $smbShare = $matches[2]
        }
    }
    
    # Extract SMB_USERNAME
    if ($envContent -match 'SMB_USERNAME=(.+)') {
        $smbUsername = $matches[1].Trim()
    }
    
    # Extract SMB_PASSWORD
    if ($envContent -match 'SMB_PASSWORD=(.+)') {
        $smbPassword = $matches[1].Trim()
    }
}

# Prompt for missing values
if ($SourceDirectory -eq "") {
    $SourceDirectory = Read-Host "Enter source directory path containing documents"
}

if (-not (Test-Path $SourceDirectory)) {
    Write-Host "Source directory does not exist: $SourceDirectory" -ForegroundColor Red
    exit 1
}

if ($DestinationShare -eq "" -and -not $ProcessOnly) {
    if ($smbHost -and $smbShare) {
        $defaultShare = "\\$smbHost\$smbShare"
        $useDefault = Read-Host "Use default SMB share from .env? ($defaultShare) (y/n)"
        
        if ($useDefault -eq 'y') {
            $DestinationShare = $defaultShare
        } else {
            $DestinationShare = Read-Host "Enter destination SMB share path (e.g. \\server\share)"
        }
    } else {
        $DestinationShare = Read-Host "Enter destination SMB share path (e.g. \\server\share)"
    }
}

# Ensure temp directory exists
if (-not (Test-Path $tempDir)) {
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    Write-Host "Created temporary directory at $tempDir" -ForegroundColor Yellow
}

# Convert file types to array
$fileExtensions = $FileTypes -split ',' | ForEach-Object { $_.Trim() }

# Function to connect to SMB share
function Connect-ToSmbShare {
    param (
        [string]$SharePath,
        [string]$Username = "",
        [string]$Password = ""
    )
    
    # Check if already connected
    $existingConnections = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | 
                           Where-Object { $_.Root -eq $SharePath }
    
    if ($existingConnections) {
        Write-Host "Already connected to $SharePath" -ForegroundColor Green
        return $true
    }
    
    try {
        # Try to connect
        Write-Host "Connecting to $SharePath..." -ForegroundColor Yellow
        
        if ($Username -and $Password) {
            # Connect with credentials
            net use $SharePath /user:$Username $Password 2>&1 | Out-Null
        } else {
            # Connect with current credentials
            net use $SharePath 2>&1 | Out-Null
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Connected to $SharePath" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Failed to connect to $SharePath" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Error connecting to share: $_" -ForegroundColor Red
        return $false
    }
}

# Function to process documents
function Process-Documents {
    param (
        [string]$SourceDir,
        [string]$DestDir,
        [array]$Extensions
    )
    
    # Get all files with specified extensions
    $files = Get-ChildItem -Path $SourceDir -Recurse -File | 
             Where-Object { $Extensions -contains $_.Extension.ToLower() }
    
    if ($files.Count -eq 0) {
        Write-Host "No matching documents found in $SourceDir" -ForegroundColor Yellow
        return 0
    }
    
    Write-Host "Found $($files.Count) documents to process" -ForegroundColor Green
    
    $processedFiles = 0
    $failedFiles = 0
    
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
        $destFilePath = Join-Path -Path $DestDir -ChildPath $relativePath
        $destFileDir = Split-Path -Path $destFilePath -Parent
        
        # Create destination directory if it doesn't exist
        if (-not (Test-Path $destFileDir)) {
            New-Item -Path $destFileDir -ItemType Directory -Force | Out-Null
        }
        
        # Copy the file
        try {
            Write-Host "Processing: $($file.Name)" -ForegroundColor Yellow
            Copy-Item -Path $file.FullName -Destination $destFilePath -Force
            $processedFiles++
            Write-Host "  ✓ Copied to $destFilePath" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Failed to copy: $_" -ForegroundColor Red
            $failedFiles++
        }
    }
    
    Write-Host "`nDocument processing complete!" -ForegroundColor Cyan
    Write-Host "Processed: $processedFiles" -ForegroundColor Green
    
    if ($failedFiles -gt 0) {
        Write-Host "Failed: $failedFiles" -ForegroundColor Red
    }
    
    return $processedFiles
}

# Function to trigger document scan
function Trigger-DocumentScan {
    try {
        Write-Host "Triggering document scan..." -ForegroundColor Yellow
        $response = Invoke-RestMethod -Uri "http://localhost:3000/api/scan/manual" -Method Post
        
        if ($response.success) {
            Write-Host "Scan triggered successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Scan trigger failed: $($response.error)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Error triggering scan: $_" -ForegroundColor Red
        return $false
    }
}

# Main processing logic
try {
    if (-not $ProcessOnly) {
        # Connect to SMB share
        if ($smbUsername -and $smbPassword) {
            $connected = Connect-ToSmbShare -SharePath $DestinationShare -Username $smbUsername -Password $smbPassword
        } else {
            $connected = Connect-ToSmbShare -SharePath $DestinationShare
        }
        
        if (-not $connected) {
            Write-Host "Failed to connect to destination share. Please check credentials and try again." -ForegroundColor Red
            exit 1
        }
        
        # Process documents
        $processedCount = Process-Documents -SourceDir $SourceDirectory -DestDir $DestinationShare -Extensions $fileExtensions
    }
    
    # Auto-scan if enabled and documents were processed
    if ($AutoScan -and $processedCount -gt 0 -and -not $CopyOnly) {
        $scanResult = Trigger-DocumentScan
        
        if ($scanResult) {
            # Wait for scan to complete
            Write-Host "Waiting for scan to complete..." -ForegroundColor Yellow
            
            $scanCompleted = $false
            $attempts = 0
            $maxAttempts = 60  # 5 minutes max (60 * 5 seconds)
            
            while (-not $scanCompleted -and $attempts -lt $maxAttempts) {
                $attempts++
                Start-Sleep -Seconds 5
                
                try {
                    $status = Invoke-RestMethod -Uri "http://localhost:3000/api/status" -Method Get
                    
                    if (-not $status.scanInProgress) {
                        $scanCompleted = $true
                        Write-Host "Scan completed successfully!" -ForegroundColor Green
                    } else {
                        Write-Host "." -NoNewline -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "Error checking scan status: $_" -ForegroundColor Red
                    break
                }
            }
            
            if (-not $scanCompleted) {
                Write-Host "`nScan did not complete in the expected time" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host "`nBatch document processing completed!" -ForegroundColor Cyan
    
} catch {
    Write-Host "Error during batch processing: $_" -ForegroundColor Red
    exit 1
} finally {
    # Clean up temp directory
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

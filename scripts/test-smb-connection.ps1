# Test SMB Connection
# This PowerShell script tests SMB connection for Document Scanner Service

param(
    [string]$SmbHost = $null,
    [string]$SmbShare = $null,
    [string]$Username = $null,
    [string]$Password = $null
)

Write-Host "Document Scanner - SMB Connection Test" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Set paths
$appPath = "C:\Users\Administrator\source\repos\document-scanner-service"
$envPath = "$appPath\.env"

# Read SMB settings from .env if not provided as parameters
if ((Test-Path $envPath) -and (!$SmbHost -or !$SmbShare -or !$Username -or !$Password)) {
    Write-Host "Reading SMB configuration from .env file..." -ForegroundColor Yellow
    
    $envContent = Get-Content -Path $envPath -Raw
    
    # Extract SMB_HOST
    if ($envContent -match 'SMB_HOST=(.+)') {
        $smbConfig = $matches[1].Trim()
        
        # Parse SMB host and share
        if ($smbConfig -match '//([^/]+)/(.+)') {
            $SmbHost = $matches[1]
            $SmbShare = $matches[2]
        }
    }
    
    # Extract SMB_USERNAME
    if ($envContent -match 'SMB_USERNAME=(.+)') {
        $Username = $matches[1].Trim()
    }
    
    # Extract SMB_PASSWORD
    if ($envContent -match 'SMB_PASSWORD=(.+)') {
        $Password = $matches[1].Trim()
    }
}

# Prompt for missing values
if (!$SmbHost) {
    $SmbHost = Read-Host "Enter SMB server hostname/IP"
}

if (!$SmbShare) {
    $SmbShare = Read-Host "Enter SMB share name"
}

if (!$Username) {
    $Username = Read-Host "Enter username"
}

if (!$Password) {
    $Password = Read-Host "Enter password" -AsSecureString
    $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    )
}

# Test net use connection (Windows style)
Write-Host "`nTesting SMB connection to \\$SmbHost\$SmbShare..." -ForegroundColor Yellow

# Create a temporary mount
$driveLetter = "Z:"
$tempConnection = $false

try {
    # Check if drive letter is already in use
    $existingDrive = Get-PSDrive -Name Z -ErrorAction SilentlyContinue
    if ($existingDrive) {
        Write-Host "Drive Z: is already in use. Will disconnect after test." -ForegroundColor Yellow
    }
    
    # Try to connect
    Write-Host "Connecting to \\$SmbHost\$SmbShare..." -ForegroundColor Yellow
    
    # Disconnect any existing connection first
    net use $driveLetter /delete /y 2>$null
    
    # Connect to the SMB share
    $result = net use $driveLetter "\\$SmbHost\$SmbShare" $Password /user:$Username 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $tempConnection = $true
        Write-Host "Connection successful!" -ForegroundColor Green
        
        # List files in the share
        Write-Host "`nListing files in SMB share:" -ForegroundColor Yellow
        $files = Get-ChildItem -Path $driveLetter -ErrorAction Stop
        
        if ($files.Count -eq 0) {
            Write-Host "No files found in the share." -ForegroundColor Yellow
        } else {
            foreach ($file in $files) {
                $extension = [System.IO.Path]::GetExtension($file.Name).ToLower()
                $isDocument = $extension -in ".pdf", ".doc", ".docx", ".txt"
                $color = if ($isDocument) { "Green" } else { "White" }
                
                Write-Host "$($file.Name) ($($file.Length) bytes)" -ForegroundColor $color
            }
            
            # Count document files
            $docFiles = $files | Where-Object { 
                $extension = [System.IO.Path]::GetExtension($_.Name).ToLower()
                $extension -in ".pdf", ".doc", ".docx", ".txt"
            }
            
            Write-Host "`nFound $($docFiles.Count) document files that can be processed." -ForegroundColor Cyan
        }
    } else {
        Write-Host "Connection failed: $result" -ForegroundColor Red
    }
} catch {
    Write-Host "Error testing connection: $_" -ForegroundColor Red
} finally {
    # Disconnect the temporary connection
    if ($tempConnection) {
        Write-Host "`nDisconnecting from \\$SmbHost\$SmbShare..." -ForegroundColor Yellow
        net use $driveLetter /delete /y
        Write-Host "Disconnected." -ForegroundColor Green
    }
}

Write-Host "`nSMB connection test completed." -ForegroundColor Cyan
Write-Host "When deploying on Linux, use the following connection string in .env:" -ForegroundColor Yellow
Write-Host "SMB_HOST=//$SmbHost/$SmbShare" -ForegroundColor White
Write-Host "SMB_USERNAME=$Username" -ForegroundColor White
Write-Host "SMB_PASSWORD=********" -ForegroundColor White
Write-Host "SMB_MOUNT_POINT=/mnt/smb_docs" -ForegroundColor White

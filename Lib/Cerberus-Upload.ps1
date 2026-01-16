# =============================================================================
# CERBERUS-UPLOAD.PS1 - Upload evidence to MinIO server
# =============================================================================
#
# WHAT IS THIS FILE?
# This file contains functions for uploading evidence to MinIO:
#   - Test-MinIOConnection: Check if we can reach the server
#   - Send-ToMinIO: Upload a file or folder
#
# WHAT IS MINIO?
# MinIO is like a private Dropbox or Google Drive. It stores files so
# analysts can download evidence from a central location without needing
# access to each endpoint.
#
# =============================================================================

function Test-MinIOConnection {
    <#
    .SYNOPSIS
        Tests if we can reach the MinIO server
    
    .DESCRIPTION
        Before uploading, we check if the network can reach the server.
        This prevents waiting a long time only to get a connection error.
    
    .PARAMETER Server
        The MinIO server address (e.g., "10.1.15.173:8443")
    
    .EXAMPLE
        if (Test-MinIOConnection -Server "10.1.15.173:8443") {
            # Upload the file
        }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server
    )
    
    # Split server into host and port
    # Example: "10.1.15.173:8443" becomes host="10.1.15.173" port="8443"
    $parts = $Server -split ':'
    $hostName = $parts[0]
    $port = if ($parts.Count -gt 1) { $parts[1] } else { 443 }
    
    Write-Host "[NETWORK] Testing connection to $hostName`:$port..."
    
    try {
        $result = Test-NetConnection -ComputerName $hostName -Port $port -WarningAction SilentlyContinue -ErrorAction Stop
        
        if ($result.TcpTestSucceeded) {
            Write-Host "[NETWORK] Connection successful" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[NETWORK] Cannot reach server" -ForegroundColor Red
            Write-Host "[NETWORK] Check firewall and network connectivity" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "[NETWORK] Connection test failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}


function Send-ToMinIO {
    <#
    .SYNOPSIS
        Uploads a file to MinIO server
    
    .DESCRIPTION
        This function:
        1. Checks if the MinIO client (mc.exe) exists
        2. Checks if the file to upload exists
        3. Tests network connectivity
        4. Uploads the file using mc.exe
        5. Returns $true if successful, $false if failed
    
    .PARAMETER FilePath
        The file or folder to upload
    
    .PARAMETER Config
        The config object containing MinIO credentials
    
    .PARAMETER ScriptRoot
        The folder containing the Cerberus scripts
    
    .EXAMPLE
        $success = Send-ToMinIO -FilePath "C:\Evidence\scan.zip" -Config $Config -ScriptRoot $PSScriptRoot
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        $Config,
        
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot
    )
    
    # Get MinIO client path
    $MinioExe = "$ScriptRoot\Bin\MinIO\mc.exe"
    
    # -------------------------------------------------------------------------
    # CHECK 1: Does mc.exe exist?
    # -------------------------------------------------------------------------
    if (-not (Test-Path $MinioExe)) {
        Write-Host "[ERROR] MinIO client not found: $MinioExe" -ForegroundColor Red
        return $false
    }
    
    # -------------------------------------------------------------------------
    # CHECK 2: Does the file/folder exist?
    # -------------------------------------------------------------------------
    if (-not (Test-Path $FilePath)) {
        Write-Host "[ERROR] File not found: $FilePath" -ForegroundColor Red
        return $false
    }
    
    # -------------------------------------------------------------------------
    # CHECK 3: Can we reach the server?
    # -------------------------------------------------------------------------
    if (-not (Test-MinIOConnection -Server $Config.MinIO.Server)) {
        Write-Host "[UPLOAD] Skipping upload - cannot reach server" -ForegroundColor Yellow
        Write-Host "[LOCAL] Evidence saved locally at: $FilePath" -ForegroundColor Yellow
        return $false
    }
    
    # -------------------------------------------------------------------------
    # UPLOAD: Send the file
    # -------------------------------------------------------------------------
    
    # Get file size for logging
    if (Test-Path $FilePath -PathType Container) {
        $size = (Get-ChildItem $FilePath -Recurse | Measure-Object -Property Length -Sum).Sum
    } else {
        $size = (Get-Item $FilePath).Length
    }
    $sizeMB = [math]::Round($size / 1MB, 2)
    
    Write-Host "[UPLOAD] Uploading: $FilePath ($sizeMB MB)" -ForegroundColor Cyan
    
    # Configure MinIO credentials via environment variable
    $env:MC_HOST_minio = "https://$($Config.MinIO.AccessKey):$($Config.MinIO.SecretKey)@$($Config.MinIO.Server)"
    
    # Run the upload command
    $bucket = $Config.MinIO.Bucket
    
    if (Test-Path $FilePath -PathType Container) {
        # It's a folder - use -r for recursive
        & $MinioExe put -r "$FilePath" "minio\$bucket" --insecure
    } else {
        # It's a file
        & $MinioExe put "$FilePath" "minio\$bucket" --insecure
    }
    
    # Check if upload succeeded
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[UPLOAD] Success! ($sizeMB MB)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "[UPLOAD] Failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "[LOCAL] Evidence saved locally at: $FilePath" -ForegroundColor Yellow
        return $false
    }
}

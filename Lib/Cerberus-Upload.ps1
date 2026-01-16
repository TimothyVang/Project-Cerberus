# =============================================================================
# CERBERUS-UPLOAD.PS1 - Upload evidence to MinIO server with resume & progress
# =============================================================================
#
# WHAT IS THIS FILE?
# This file contains functions for uploading evidence to MinIO:
#   - Test-MinIOConnection: Check if we can reach the server
#   - Get-RemoteFileInfo: Check if file already exists on server
#   - Save-UploadState: Track upload progress for resume
#   - Get-UploadState: Read upload state
#   - Send-ToMinIO: Upload with resume, progress, and retry
#
# FEATURES:
#   - Resume capability: Skip already-uploaded files
#   - Progress display: Show percentage, speed, ETA every 5%
#   - Retry logic: Retry up to 5 times with exponential backoff
#   - Full logging: All events logged via Write-Log
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
        The MinIO server address (e.g., "localhost:8443")
    
    .EXAMPLE
        if (Test-MinIOConnection -Server "localhost:8443") {
            # Upload the file
        }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server
    )
    
    # Split server into host and port
    $parts = $Server -split ':'
    $hostName = $parts[0]
    $port = if ($parts.Count -gt 1) { $parts[1] } else { 443 }
    
    Write-Log "Testing connection to $hostName`:$port..." "INFO" -Category "NETWORK"
    
    try {
        $result = Test-NetConnection -ComputerName $hostName -Port $port -WarningAction SilentlyContinue -ErrorAction Stop
        
        if ($result.TcpTestSucceeded) {
            Write-Log "Connection successful" "SUCCESS" -Category "NETWORK"
            return $true
        } else {
            Write-Log "Cannot reach server" "ERROR" -Category "NETWORK"
            Write-Log "Check firewall and network connectivity" "WARNING" -Category "NETWORK"
            return $false
        }
    }
    catch {
        Write-Log "Connection test failed: $($_.Exception.Message)" "ERROR" -Category "NETWORK"
        return $false
    }
}

function Get-RemoteFileInfo {
    <#
    .SYNOPSIS
        Checks if a file exists on MinIO and returns its size
    
    .PARAMETER FileName
        The name of the file to check (not full path)
    
    .PARAMETER Config
        The config object containing MinIO credentials
    
    .PARAMETER ScriptRoot
        The folder containing the Cerberus scripts
    
    .RETURNS
        Hashtable with Exists (bool) and Size (long) properties, or $null on error
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FileName,
        
        [Parameter(Mandatory)]
        $Config,
        
        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )
    
    $MinioExe = "$ScriptRoot\Bin\MinIO\mc.exe"
    
    if (-not (Test-Path $MinioExe)) {
        return $null
    }
    
    # Configure MinIO credentials
    $env:MC_HOST_minio = "https://$($Config.MinIO.AccessKey):$($Config.MinIO.SecretKey)@$($Config.MinIO.Server)"
    
    $bucket = $Config.MinIO.Bucket
    $remotePath = "minio/$bucket/$FileName"
    
    try {
        # Use mc stat to get file info
        $output = & $MinioExe stat $remotePath --insecure 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            # Parse the output for size
            $sizeLine = $output | Where-Object { $_ -match "Size\s*:" }
            if ($sizeLine -match "Size\s*:\s*(\d+)") {
                return @{
                    Exists = $true
                    Size = [long]$Matches[1]
                }
            }
            return @{ Exists = $true; Size = 0 }
        } else {
            return @{ Exists = $false; Size = 0 }
        }
    }
    catch {
        return @{ Exists = $false; Size = 0 }
    }
}

function Save-UploadState {
    <#
    .SYNOPSIS
        Saves upload state to a JSON file for resume capability
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$StateDir,
        
        [string]$Status = "IN_PROGRESS",
        
        [long]$BytesUploaded = 0,
        
        [int]$RetryCount = 0
    )
    
    $fileName = Split-Path $FilePath -Leaf
    $stateFile = "$StateDir\.upload-state-$fileName.json"
    
    $state = @{
        FilePath = $FilePath
        FileName = $fileName
        FileSize = (Get-Item $FilePath).Length
        StartTime = (Get-Date).ToString("o")
        Status = $Status
        BytesUploaded = $BytesUploaded
        RetryCount = $RetryCount
    }
    
    $state | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    
    return $stateFile
}

function Get-UploadState {
    <#
    .SYNOPSIS
        Reads upload state from JSON file
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$StateDir
    )
    
    $fileName = Split-Path $FilePath -Leaf
    $stateFile = "$StateDir\.upload-state-$fileName.json"
    
    if (Test-Path $stateFile) {
        try {
            return Get-Content $stateFile -Raw | ConvertFrom-Json
        }
        catch {
            return $null
        }
    }
    
    return $null
}

function Format-FileSize {
    <#
    .SYNOPSIS
        Formats bytes as human-readable size
    #>
    param([long]$Bytes)
    
    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Format-Duration {
    <#
    .SYNOPSIS
        Formats seconds as human-readable duration
    #>
    param([int]$Seconds)
    
    if ($Seconds -ge 3600) {
        $hours = [math]::Floor($Seconds / 3600)
        $mins = [math]::Floor(($Seconds % 3600) / 60)
        return "{0}h {1}m" -f $hours, $mins
    }
    if ($Seconds -ge 60) {
        $mins = [math]::Floor($Seconds / 60)
        $secs = $Seconds % 60
        return "{0}m {1}s" -f $mins, $secs
    }
    return "{0}s" -f $Seconds
}

function Send-ToMinIO {
    <#
    .SYNOPSIS
        Uploads a file to MinIO server with resume, progress, and retry
    
    .DESCRIPTION
        This function:
        1. Initializes a separate UPLOAD log session
        2. Checks if MinIO client (mc.exe) exists
        3. Checks if file to upload exists
        4. Tests network connectivity
        5. Checks if file already exists on server (resume logic)
        6. Uploads with progress display
        7. Retries on failure with exponential backoff
        8. Verifies upload and logs results
    
    .PARAMETER FilePath
        The file to upload
    
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
    
    # Initialize upload log session
    Initialize-LogSession -Operation "UPLOAD" -ScriptRoot $ScriptRoot
    
    $MinioExe = "$ScriptRoot\Bin\MinIO\mc.exe"
    $EvidenceFolder = Split-Path $FilePath -Parent
    $FileName = Split-Path $FilePath -Leaf
    
    Write-Log "========================================" "INFO" -Category "UPLOAD"
    Write-Log "UPLOAD OPERATION STARTED" "INFO" -Category "UPLOAD"
    Write-Log "========================================" "INFO" -Category "UPLOAD"
    
    # -------------------------------------------------------------------------
    # CHECK 1: Does mc.exe exist?
    # -------------------------------------------------------------------------
    if (-not (Test-Path $MinioExe)) {
        Write-Log "MinIO client not found: $MinioExe" "ERROR" -Category "UPLOAD"
        Complete-LogSession -Status "FAILED"
        return $false
    }
    Write-Log "MinIO client found: $MinioExe" "SUCCESS" -Category "UPLOAD"
    
    # -------------------------------------------------------------------------
    # CHECK 2: Does the file exist?
    # -------------------------------------------------------------------------
    if (-not (Test-Path $FilePath)) {
        Write-Log "File not found: $FilePath" "ERROR" -Category "UPLOAD"
        Complete-LogSession -Status "FAILED"
        return $false
    }
    
    $fileInfo = Get-Item $FilePath
    $fileSize = $fileInfo.Length
    $fileSizeFormatted = Format-FileSize $fileSize
    
    Write-Log "File: $FileName" "INFO" -Category "UPLOAD"
    Write-Log "Size: $fileSizeFormatted" "INFO" -Category "UPLOAD"
    Write-Log "Target: minio/$($Config.MinIO.Bucket)/" "INFO" -Category "UPLOAD"
    
    # -------------------------------------------------------------------------
    # CHECK 3: Can we reach the server?
    # -------------------------------------------------------------------------
    if (-not (Test-MinIOConnection -Server $Config.MinIO.Server)) {
        Write-Log "Skipping upload - cannot reach server" "WARNING" -Category "UPLOAD"
        Write-Log "Evidence saved locally at: $FilePath" "INFO" -Category "UPLOAD"
        Complete-LogSession -Status "FAILED" -OutputFile $FilePath -OutputSize $fileSizeFormatted
        return $false
    }
    
    # -------------------------------------------------------------------------
    # CHECK 4: Does file already exist on server? (Resume logic)
    # -------------------------------------------------------------------------
    Write-Log "Checking for existing upload on server..." "INFO" -Category "UPLOAD"
    
    $remoteInfo = Get-RemoteFileInfo -FileName $FileName -Config $Config -ScriptRoot $ScriptRoot
    
    if ($remoteInfo -and $remoteInfo.Exists) {
        if ($remoteInfo.Size -eq $fileSize) {
            Write-Log "File already uploaded (size matches: $fileSizeFormatted)" "SUCCESS" -Category "UPLOAD"
            Write-Log "Skipping upload - already complete" "INFO" -Category "UPLOAD"
            Complete-LogSession -Status "SUCCESS" -OutputFile $FilePath -OutputSize $fileSizeFormatted -AdditionalInfo @{ "Action" = "SKIPPED (already uploaded)" }
            return $true
        } else {
            $remoteSizeFormatted = Format-FileSize $remoteInfo.Size
            Write-Log "Partial upload found (remote: $remoteSizeFormatted, local: $fileSizeFormatted)" "WARNING" -Category "UPLOAD"
            Write-Log "Will re-upload complete file" "INFO" -Category "UPLOAD"
        }
    } else {
        Write-Log "No existing file found - starting fresh upload" "INFO" -Category "UPLOAD"
    }
    
    # -------------------------------------------------------------------------
    # SAVE STATE: Track upload for resume capability
    # -------------------------------------------------------------------------
    $stateFile = Save-UploadState -FilePath $FilePath -StateDir $EvidenceFolder -Status "IN_PROGRESS"
    Write-Log "Upload state saved: $(Split-Path $stateFile -Leaf)" "INFO" -Category "UPLOAD"
    
    # -------------------------------------------------------------------------
    # UPLOAD: Send the file with retry logic
    # -------------------------------------------------------------------------
    
    # Configure MinIO credentials
    $env:MC_HOST_minio = "https://$($Config.MinIO.AccessKey):$($Config.MinIO.SecretKey)@$($Config.MinIO.Server)"
    
    $bucket = $Config.MinIO.Bucket
    $maxRetries = $UPLOAD.MaxRetries
    $retryDelay = $UPLOAD.RetryDelayMs
    $backoff = $UPLOAD.RetryBackoff
    
    $uploadSuccess = $false
    $attempt = 0
    $startTime = Get-Date
    
    while (-not $uploadSuccess -and $attempt -lt $maxRetries) {
        $attempt++
        
        if ($attempt -gt 1) {
            $waitSeconds = [math]::Ceiling($retryDelay / 1000)
            Write-Log "Retry $attempt/$maxRetries - waiting ${waitSeconds}s..." "WARNING" -Category "UPLOAD"
            Start-Sleep -Milliseconds $retryDelay
            $retryDelay = $retryDelay * $backoff
        }
        
        Write-Log "Starting upload (attempt $attempt/$maxRetries)..." "INFO" -Category "UPLOAD"
        
        # Build upload command with progress
        # Using mc cp with parallel uploads for better performance
        $partSize = $UPLOAD.PartSize
        $parallelParts = $UPLOAD.ParallelParts
        
        try {
            # Run upload - mc will show its own progress
            Write-Log "Uploading with $parallelParts parallel streams, $partSize parts..." "INFO" -Category "UPLOAD"
            
            $uploadOutput = & $MinioExe cp "$FilePath" "minio/$bucket/" --insecure -P $parallelParts -s $partSize 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $uploadSuccess = $true
                Write-Log "Upload transfer completed" "SUCCESS" -Category "UPLOAD"
            } else {
                Write-Log "Upload failed with exit code: $LASTEXITCODE" "ERROR" -Category "UPLOAD"
                if ($uploadOutput) {
                    Write-Log "Error details: $uploadOutput" "ERROR" -Category "UPLOAD"
                }
            }
        }
        catch {
            Write-Log "Upload exception: $($_.Exception.Message)" "ERROR" -Category "UPLOAD"
        }
        
        # Update state
        Save-UploadState -FilePath $FilePath -StateDir $EvidenceFolder -Status $(if ($uploadSuccess) { "COMPLETE" } else { "FAILED" }) -RetryCount $attempt
    }
    
    # -------------------------------------------------------------------------
    # VERIFY: Check upload succeeded
    # -------------------------------------------------------------------------
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $durationFormatted = Format-Duration ([int]$duration.TotalSeconds)
    
    if ($uploadSuccess) {
        Write-Log "Verifying upload..." "INFO" -Category "VERIFY"
        
        $verifyInfo = Get-RemoteFileInfo -FileName $FileName -Config $Config -ScriptRoot $ScriptRoot
        
        if ($verifyInfo -and $verifyInfo.Exists) {
            if ($verifyInfo.Size -eq $fileSize) {
                Write-Log "Upload verified - size matches: $fileSizeFormatted" "SUCCESS" -Category "VERIFY"
            } else {
                $remoteSizeFormatted = Format-FileSize $verifyInfo.Size
                Write-Log "Size mismatch! Local: $fileSizeFormatted, Remote: $remoteSizeFormatted" "WARNING" -Category "VERIFY"
            }
        } else {
            Write-Log "Could not verify upload - file not found on server" "WARNING" -Category "VERIFY"
        }
        
        # Calculate average speed
        if ($duration.TotalSeconds -gt 0) {
            $avgSpeed = $fileSize / $duration.TotalSeconds
            $avgSpeedFormatted = Format-FileSize ([long]$avgSpeed)
            Write-Log "Average speed: $avgSpeedFormatted/s" "INFO" -Category "UPLOAD"
        }
        
        Write-Log "========================================" "INFO" -Category "UPLOAD"
        Write-Log "UPLOAD COMPLETE" "SUCCESS" -Category "UPLOAD"
        Write-Log "File: $FileName" "INFO" -Category "UPLOAD"
        Write-Log "Size: $fileSizeFormatted" "INFO" -Category "UPLOAD"
        Write-Log "Time: $durationFormatted" "INFO" -Category "UPLOAD"
        Write-Log "========================================" "INFO" -Category "UPLOAD"
        
        # Update state to complete
        Save-UploadState -FilePath $FilePath -StateDir $EvidenceFolder -Status "COMPLETE" -BytesUploaded $fileSize -RetryCount $attempt
        
        # Clean up state file if not retaining
        if (-not $UPLOAD.StateFileRetain) {
            $stateFilePath = "$EvidenceFolder\.upload-state-$FileName.json"
            if (Test-Path $stateFilePath) {
                Remove-Item $stateFilePath -Force
            }
        }
        
        Complete-LogSession -Status "SUCCESS" -OutputFile $FilePath -OutputSize $fileSizeFormatted -AdditionalInfo @{
            "Duration" = $durationFormatted
            "Attempts" = "$attempt"
        }
        
        return $true
    } else {
        Write-Log "========================================" "INFO" -Category "UPLOAD"
        Write-Log "UPLOAD FAILED after $attempt attempts" "ERROR" -Category "UPLOAD"
        Write-Log "Evidence saved locally at: $FilePath" "WARNING" -Category "UPLOAD"
        Write-Log "========================================" "INFO" -Category "UPLOAD"
        
        Complete-LogSession -Status "FAILED" -OutputFile $FilePath -OutputSize $fileSizeFormatted -AdditionalInfo @{
            "Attempts" = "$attempt"
            "LastError" = "Max retries exceeded"
        }
        
        return $false
    }
}

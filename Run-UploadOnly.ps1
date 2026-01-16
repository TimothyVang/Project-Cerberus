# =============================================================================
# RUN-UPLOADONLY.PS1 - Upload existing evidence without running scans
# =============================================================================
#
# USAGE: .\Run-UploadOnly.ps1
#
# WHAT THIS SCRIPT DOES:
#   1. Load configuration from Cerberus_Config.json
#   2. Scan the Evidence folder for files matching this computer's name
#   3. Upload each file to MinIO server
#
# WHEN TO USE THIS:
#   - A previous scan completed but the upload failed
#   - You want to re-upload evidence that's already collected
#   - Network was down during original scan, now it's back
#
# NOTE: This does NOT run any forensic tools - it just uploads what's there.
#
# LOG FILE:
#   Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-UPLOAD-ONLY_{TIMESTAMP}.log
#
# =============================================================================


# =============================================================================
# STEP 1: Load shared libraries
# =============================================================================

. "$PSScriptRoot\Lib\Write-Log.ps1"
. "$PSScriptRoot\Lib\Cerberus-Constants.ps1"
. "$PSScriptRoot\Lib\Cerberus-Config.ps1"
. "$PSScriptRoot\Lib\Cerberus-Upload.ps1"


# =============================================================================
# STEP 2: Initialize log session
# =============================================================================

Initialize-LogSession -Operation "UPLOAD-ONLY" -ScriptRoot $PSScriptRoot


# =============================================================================
# STEP 3: Load configuration
# =============================================================================

Write-Log "Loading configuration..." "INFO" -Category "CONFIG"

$Config = Get-CerberusConfig -ScriptRoot $PSScriptRoot

if (-not $Config) {
    Write-Log "Failed to load configuration" "ERROR" -Category "CONFIG"
    Complete-LogSession -Status "FAILED"
    exit 1
}

Write-Log "Configuration loaded successfully" "SUCCESS" -Category "CONFIG"


# =============================================================================
# STEP 4: Find evidence files
# =============================================================================
# Look for files that match this computer's name

$EvidenceFolder = "$PSScriptRoot\Evidence"

Write-Log "Scanning for evidence in: $EvidenceFolder" "INFO" -Category "SCAN"
Write-Log "Looking for files matching: $env:COMPUTERNAME" "INFO" -Category "SCAN"

if (-not (Test-Path $EvidenceFolder)) {
    Write-Log "Evidence folder not found!" "ERROR" -Category "SCAN"
    Write-Log "No evidence to upload - run a scan first" "ERROR" -Category "SCAN"
    Complete-LogSession -Status "FAILED"
    exit 1
}

# Find all files that contain this computer's name
$files = Get-ChildItem -Path $EvidenceFolder -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $env:COMPUTERNAME }

if (-not $files -or $files.Count -eq 0) {
    Write-Log "No evidence files found for: $env:COMPUTERNAME" "WARNING" -Category "SCAN"
    Write-Log "Run a scan first (Run-Thor.ps1, Run-KapeDisk.ps1, etc.)" "WARNING" -Category "SCAN"
    Complete-LogSession -Status "FAILED" -AdditionalInfo @{ "Reason" = "No files found" }
    exit 0
}

Write-Log "Found $($files.Count) file(s) to upload" "SUCCESS" -Category "SCAN"

# List found files
foreach ($file in $files) {
    $sizeStr = if ($file.Length -ge 1GB) {
        "{0:N2} GB" -f ($file.Length / 1GB)
    } else {
        "{0:N2} MB" -f ($file.Length / 1MB)
    }
    Write-Log "  - $($file.Name) ($sizeStr)" "INFO" -Category "SCAN"
}


# =============================================================================
# STEP 5: Complete scan log session
# =============================================================================

Complete-LogSession -Status "SUCCESS" -AdditionalInfo @{ "FilesFound" = "$($files.Count)" }


# =============================================================================
# STEP 6: Upload each file (each creates its own log session)
# =============================================================================

$uploadedCount = 0
$failedCount = 0

foreach ($file in $files) {
    Write-Log "" "INFO"
    Write-Log "Processing: $($file.Name)" "INFO" -Category "UPLOAD"
    
    # Compress large files before upload
    if ($file.Extension -ne ".zip" -and $file.Length -gt $THRESHOLDS.LargeFileBytes) {
        Write-Log "Large file detected - compressing first..." "INFO" -Category "COMPRESS"
        
        $zipPath = "$($file.FullName).zip"
        
        try {
            Compress-Archive -Path $file.FullName -DestinationPath $zipPath -Force
            $file = Get-Item $zipPath
            Write-Log "Compressed to: $($file.Name)" "SUCCESS" -Category "COMPRESS"
        }
        catch {
            Write-Log "Failed to compress: $($_.Exception.Message)" "ERROR" -Category "COMPRESS"
            $failedCount++
            continue
        }
    }
    
    # Upload the file (Send-ToMinIO creates its own log session)
    $success = Send-ToMinIO -FilePath $file.FullName -Config $Config -ScriptRoot $PSScriptRoot
    
    if ($success) {
        $uploadedCount++
    } else {
        $failedCount++
    }
}


# =============================================================================
# STEP 7: Report results
# =============================================================================

Write-Log "" "INFO"
Write-Log "==========================================" "INFO"

if ($failedCount -eq 0) {
    Write-Log "SUCCESS: Uploaded $uploadedCount file(s)" "SUCCESS"
    Write-Log "==========================================" "INFO"
    exit 0
} elseif ($uploadedCount -gt 0) {
    Write-Log "PARTIAL: $uploadedCount uploaded, $failedCount failed" "WARNING"
    Write-Log "==========================================" "INFO"
    exit 1
} else {
    Write-Log "FAILED: All $failedCount upload(s) failed" "ERROR"
    Write-Log "==========================================" "INFO"
    exit 1
}

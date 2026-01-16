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
# =============================================================================


# =============================================================================
# STEP 1: Load shared libraries
# =============================================================================

. "$PSScriptRoot\Lib\Write-Log.ps1"
. "$PSScriptRoot\Lib\Cerberus-Constants.ps1"
. "$PSScriptRoot\Lib\Cerberus-Config.ps1"
. "$PSScriptRoot\Lib\Cerberus-Upload.ps1"


# =============================================================================
# STEP 2: Load configuration
# =============================================================================

Write-Log "Loading configuration..."

$Config = Get-CerberusConfig -ScriptRoot $PSScriptRoot

if (-not $Config) {
    Write-Log "Failed to load configuration" "ERROR"
    exit 1
}


# =============================================================================
# STEP 3: Find evidence files
# =============================================================================
# Look for files that match this computer's name

$EvidenceFolder = "$PSScriptRoot\Evidence"

Write-Log "Scanning for evidence in: $EvidenceFolder"
Write-Log "Looking for files matching: $env:COMPUTERNAME"

if (-not (Test-Path $EvidenceFolder)) {
    Write-Log "Evidence folder not found!" "ERROR"
    Write-Log "No evidence to upload - run a scan first" "ERROR"
    exit 1
}

# Find all files that contain this computer's name
$files = Get-ChildItem -Path $EvidenceFolder -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $env:COMPUTERNAME }

if (-not $files -or $files.Count -eq 0) {
    Write-Log "No evidence files found for: $env:COMPUTERNAME" "WARNING"
    Write-Log "Run a scan first (Run-Thor.ps1, Run-KapeDisk.ps1, etc.)" "WARNING"
    exit 0
}

Write-Log "Found $($files.Count) file(s) to upload" "SUCCESS"


# =============================================================================
# STEP 4: Upload each file
# =============================================================================

$uploadedCount = 0
$failedCount = 0

foreach ($file in $files) {
    Write-Log ""
    Write-Log "Processing: $($file.Name)"
    
    # Compress large files before upload
    if ($file.Extension -ne ".zip" -and $file.Length -gt $THRESHOLDS.LargeFileBytes) {
        Write-Log "Large file detected - compressing first..."
        
        $zipPath = "$($file.FullName).zip"
        
        try {
            Compress-Archive -Path $file.FullName -DestinationPath $zipPath -Force
            $file = Get-Item $zipPath
            Write-Log "Compressed to: $($file.Name)"
        }
        catch {
            Write-Log "Failed to compress: $($_.Exception.Message)" "ERROR"
            $failedCount++
            continue
        }
    }
    
    # Upload the file
    $success = Send-ToMinIO -FilePath $file.FullName -Config $Config -ScriptRoot $PSScriptRoot
    
    if ($success) {
        $uploadedCount++
    } else {
        $failedCount++
    }
}


# =============================================================================
# STEP 5: Report results
# =============================================================================

Write-Log ""
Write-Log "=========================================="

if ($failedCount -eq 0) {
    Write-Log "SUCCESS: Uploaded $uploadedCount file(s)" "SUCCESS"
    Write-Log "=========================================="
    exit 0
} elseif ($uploadedCount -gt 0) {
    Write-Log "PARTIAL: $uploadedCount uploaded, $failedCount failed" "WARNING"
    Write-Log "=========================================="
    exit 1
} else {
    Write-Log "FAILED: All $failedCount upload(s) failed" "ERROR"
    Write-Log "=========================================="
    exit 1
}

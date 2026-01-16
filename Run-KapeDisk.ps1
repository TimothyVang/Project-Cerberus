# =============================================================================
# RUN-KAPEDISK.PS1 - Collects forensic artifacts with KAPE
# =============================================================================
#
# USAGE: .\Run-KapeDisk.ps1
#
# WHAT THIS SCRIPT DOES:
#   1. Load configuration from Cerberus_Config.json
#   2. Show pre-flight check with system info
#   3. Check disk space (need 25+ GB free)
#   4. Run KAPE to collect forensic artifacts
#   5. Compress the results into a .zip file
#   6. Upload the .zip to MinIO server
#
# WHAT IS KAPE?
#   KAPE (Kroll Artifact Parser and Extractor) collects important files:
#   - Windows Registry hives
#   - Event logs
#   - Prefetch files
#   - Browser history
#   - MFT (file system metadata)
#   - And more...
#
# NOTE: This is NOT a full disk image! For that, use Run-Ftk.ps1
#
# HOW LONG DOES IT TAKE?
#   Usually 15-30 minutes depending on disk size.
#
# OUTPUT FILE NAMING:
#   HOSTNAME-DOMAIN-KAPE-Disk.zip (e.g., DESKTOP-PC1-WORKGROUP-KAPE-Disk.zip)
#
# LOG FILE:
#   Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-KAPE-Disk_{TIMESTAMP}.log
#
# =============================================================================


# =============================================================================
# STEP 1: Load shared libraries
# =============================================================================

. "$PSScriptRoot\Lib\Write-Log.ps1"
. "$PSScriptRoot\Lib\Cerberus-Constants.ps1"
. "$PSScriptRoot\Lib\Cerberus-Config.ps1"
. "$PSScriptRoot\Lib\Cerberus-Upload.ps1"
. "$PSScriptRoot\Lib\Cerberus-RunTool.ps1"


# =============================================================================
# STEP 2: Initialize log session
# =============================================================================

Initialize-LogSession -Operation "KAPE-Disk" -ScriptRoot $PSScriptRoot


# =============================================================================
# HELPER FUNCTION: Generate zip filename with HOSTNAME-DOMAIN-TOOL.zip format
# =============================================================================

function Get-ZipFileName {
    param(
        [string]$Tool,
        [string]$Directory
    )
    
    $hostname = $env:COMPUTERNAME
    $domain = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "WORKGROUP" }
    $zipName = "$hostname-$domain-$Tool.zip"
    
    return Join-Path $Directory $zipName
}


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
# STEP 4: Setup paths
# =============================================================================

$KapeExe = "$PSScriptRoot\$($PATHS.Kape)"
$EvidenceFolder = "$PSScriptRoot\Evidence"
$OutputFolder = "$EvidenceFolder\$env:COMPUTERNAME-KAPE-Disk"
$ZipFile = Get-ZipFileName -Tool "KAPE-Disk" -Directory $EvidenceFolder


# =============================================================================
# STEP 5: Check KAPE exists
# =============================================================================

if (-not (Test-Path $KapeExe)) {
    Write-Log "KAPE not found at: $KapeExe" "ERROR" -Category "TOOL"
    Write-Log "Make sure KAPE is installed in the Bin\KAPE folder" "ERROR" -Category "TOOL"
    Complete-LogSession -Status "FAILED"
    exit 1
}

Write-Log "Found KAPE at: $KapeExe" "SUCCESS" -Category "TOOL"


# =============================================================================
# STEP 6: Check disk space
# =============================================================================
# KAPE can collect several GB of data, so we need enough free space.

if (-not (Test-Path $EvidenceFolder)) {
    New-Item -ItemType Directory -Path $EvidenceFolder -Force | Out-Null
}

# =============================================================================
# STEP 7: Pre-flight check and user confirmation
# =============================================================================

# Get system information for pre-flight display
$sourceDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$totalGB = [math]::Round($sourceDrive.Size / 1GB, 2)
$usedGB = [math]::Round(($sourceDrive.Size - $sourceDrive.FreeSpace) / 1GB, 2)
$freeGB = [math]::Round($sourceDrive.FreeSpace / 1GB, 2)

$targetDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$((Get-Item $EvidenceFolder).PSDrive.Name):'"
$targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 2)

$domain = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "WORKGROUP" }
$requiredGB = 25  # KAPE disk collection typically needs up to 25GB

Write-Log "" "INFO"
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "KAPE DISK COLLECTION - PRE-FLIGHT CHECK" "INFO" -Category "PREFLIGHT"
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "COLLECTION SOURCE" "INFO" -Category "PREFLIGHT"
Write-Log "  Drive:             C:\" "INFO" -Category "PREFLIGHT"
Write-Log "  Total Size:        $totalGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  Used Space:        $usedGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "TARGETS TO COLLECT" "INFO" -Category "PREFLIGHT"
Write-Log "  - Registry Hives (SYSTEM, SAM, SOFTWARE, NTUSER.DAT)" "INFO" -Category "PREFLIGHT"
Write-Log "  - Event Logs (Security, System, Application)" "INFO" -Category "PREFLIGHT"
Write-Log "  - Prefetch Files" "INFO" -Category "PREFLIGHT"
Write-Log "  - Browser History" "INFO" -Category "PREFLIGHT"
Write-Log "  - `$MFT, `$UsnJrnl" "INFO" -Category "PREFLIGHT"
Write-Log "  - BITS Database" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "OUTPUT LOCATION" "INFO" -Category "PREFLIGHT"
Write-Log "  Path:              $EvidenceFolder" "INFO" -Category "PREFLIGHT"
Write-Log "  Free Space:        $targetFreeGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "SPACE CALCULATION" "INFO" -Category "PREFLIGHT"
Write-Log "  Typical Size:      2 - 20 GB" "INFO" -Category "PREFLIGHT"
Write-Log "  Space Required:    $requiredGB GB (with buffer)" "INFO" -Category "PREFLIGHT"
Write-Log "  Available:         $targetFreeGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "ESTIMATED RUN TIME" "INFO" -Category "PREFLIGHT"
Write-Log "  Duration:          15 - 45 minutes" "INFO" -Category "PREFLIGHT"
Write-Log "  Timeout:           24 hours" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "OUTPUT FILE" "INFO" -Category "PREFLIGHT"
Write-Log "  $(Split-Path $ZipFile -Leaf)" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"

# Check if we have enough space
if ($targetFreeGB -lt $requiredGB) {
    Write-Log "STATUS: FAILED - Not enough disk space!" "ERROR" -Category "PREFLIGHT"
    Write-Log "Need $requiredGB GB, only $targetFreeGB GB available." "ERROR" -Category "PREFLIGHT"
    Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
    Complete-LogSession -Status "FAILED"
    exit 1
} else {
    Write-Log "STATUS: OK - Ready to collect" "SUCCESS" -Category "PREFLIGHT"
}
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "Press any key to start KAPE Disk collection, or Ctrl+C to cancel..." "INFO" -Category "PREFLIGHT"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Log "" "INFO"


# =============================================================================
# STEP 8: Build command arguments
# =============================================================================
# KAPE arguments come from the config file.
# We replace ${Output} with the actual output folder path.

$Arguments = $Config.Tools.Kape.DiskArgs -replace '\$\{Output\}', "`"$OutputFolder`""

Write-Log "KAPE arguments: $Arguments" "INFO" -Category "TOOL"


# =============================================================================
# STEP 9: Run KAPE with heartbeat monitoring
# =============================================================================

Write-Log "Starting KAPE artifact collection (15-30 minutes)..." "INFO" -Category "TOOL"
Write-Log "==========================================" "INFO" -Category "TOOL"

$result = Start-ToolWithMonitoring `
    -ExePath $KapeExe `
    -Arguments $Arguments `
    -ToolName "KAPE" `
    -TimeoutMs $TIMEOUTS.Kape

Write-Log "==========================================" "INFO" -Category "TOOL"

if (-not $result.Success) {
    Write-Log "KAPE failed: $($result.Error)" "ERROR" -Category "TOOL"
    # Continue anyway to upload partial results
}


# =============================================================================
# STEP 10: Compress results
# =============================================================================

Write-Log "Compressing results..." "INFO" -Category "COMPRESS"

if (Test-Path $OutputFolder) {
    try {
        if (Test-Path $ZipFile) {
            Remove-Item $ZipFile -Force
        }
        
        Compress-Archive -Path "$OutputFolder\*" -DestinationPath $ZipFile -Force
        
        $zipSize = [math]::Round((Get-Item $ZipFile).Length / 1MB, 2)
        Write-Log "Created: $ZipFile ($zipSize MB)" "SUCCESS" -Category "COMPRESS"
    }
    catch {
        Write-Log "Failed to compress: $($_.Exception.Message)" "ERROR" -Category "COMPRESS"
        Complete-LogSession -Status "FAILED"
        exit 1
    }
} else {
    Write-Log "No output folder found - nothing to compress" "WARNING" -Category "COMPRESS"
    Complete-LogSession -Status "FAILED"
    exit 1
}


# =============================================================================
# STEP 11: Complete KAPE log session before upload
# =============================================================================

$zipSizeFormatted = "$zipSize MB"
Complete-LogSession -Status "SUCCESS" -OutputFile $ZipFile -OutputSize $zipSizeFormatted


# =============================================================================
# STEP 12: Upload to MinIO (creates its own log session)
# =============================================================================

Write-Log "Initiating upload to MinIO..." "INFO" -Category "UPLOAD"

$uploaded = Send-ToMinIO -FilePath $ZipFile -Config $Config -ScriptRoot $PSScriptRoot

if ($uploaded) {
    Write-Log "==========================================" "INFO"
    Write-Log "SUCCESS: Evidence uploaded to MinIO" "SUCCESS"
    Write-Log "==========================================" "INFO"
    exit 0
} else {
    Write-Log "==========================================" "INFO"
    Write-Log "Upload failed - evidence saved locally" "WARNING"
    Write-Log "Local file: $ZipFile" "WARNING"
    Write-Log "==========================================" "INFO"
    exit 1
}

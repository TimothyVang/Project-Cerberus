# =============================================================================
# RUN-KAPEDISK.PS1 - Collects forensic artifacts with KAPE
# =============================================================================
#
# USAGE: .\Run-KapeDisk.ps1
#
# Collects Registry hives, Event logs, Prefetch, Browser history, MFT, etc.
# NOTE: This is NOT a full disk image! For that, use Run-Ftk.ps1
#
# OUTPUT: HOSTNAME-DOMAIN-KAPE-Disk.zip
# LOG:    Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-KAPE-Disk_{TIMESTAMP}.log
#
# =============================================================================


# =============================================================================
# STEP 1: Bootstrap - load libraries, init logging, load config
# =============================================================================

. "$PSScriptRoot\Lib\Cerberus-Bootstrap.ps1"
Import-CerberusLibraries -ScriptRoot $PSScriptRoot

$run = Initialize-CerberusRun -Operation "KAPE-Disk" -ScriptRoot $PSScriptRoot
$Config = $run.Config
$EvidenceFolder = $run.EvidenceFolder


# =============================================================================
# STEP 2: Setup paths and check KAPE exists
# =============================================================================

$KapeExe = "$PSScriptRoot\$($PATHS.Kape)"
$OutputFolder = "$EvidenceFolder\$env:COMPUTERNAME-KAPE-Disk"
$ZipFile = Get-ZipFileName -Tool "KAPE-Disk" -Directory $EvidenceFolder

if (-not (Test-Path $KapeExe)) {
    Write-Log "KAPE not found at: $KapeExe" "ERROR" -Category "TOOL"
    Write-Log "Make sure KAPE is installed in the Bin\KAPE folder" "ERROR" -Category "TOOL"
    Complete-LogSession -Status "FAILED"
    exit 1
}

Write-Log "Found KAPE at: $KapeExe" "SUCCESS" -Category "TOOL"


# =============================================================================
# STEP 3: Pre-flight check and user confirmation
# =============================================================================

$sourceDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$totalGB = [math]::Round($sourceDrive.Size / 1GB, 2)
$usedGB = [math]::Round(($sourceDrive.Size - $sourceDrive.FreeSpace) / 1GB, 2)

$targetDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$((Get-Item $EvidenceFolder).PSDrive.Name):'"
$targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 2)

$requiredGB = $SPACE_REQUIREMENTS.KapeDiskGB

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
if ([Environment]::UserInteractive) {
    Write-Log "Press any key to start KAPE Disk collection, or Ctrl+C to cancel..." "INFO" -Category "PREFLIGHT"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Log "" "INFO"
}


# =============================================================================
# STEP 4: Build arguments and run KAPE
# =============================================================================

$Arguments = $Config.Tools.Kape.DiskArgs -replace '\$\{Output\}', "`"$OutputFolder`""

Write-Log "KAPE arguments: $Arguments" "INFO" -Category "TOOL"
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
# STEP 5: Compress and upload
# =============================================================================

$zipSizeFormatted = Compress-Evidence -SourcePath $OutputFolder -ZipFile $ZipFile

Complete-CerberusRun -ZipFile $ZipFile -ZipSizeFormatted $zipSizeFormatted -Config $Config -ScriptRoot $PSScriptRoot

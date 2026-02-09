# =============================================================================
# RUN-KAPERAM.PS1 - Captures system memory (RAM) with KAPE
# =============================================================================
#
# USAGE: .\Run-KapeRam.ps1
#
# Captures everything currently in memory: running processes, open files,
# network connections, encryption keys, memory-resident malware.
# Output file will be roughly the same size as installed RAM.
#
# OUTPUT: HOSTNAME-DOMAIN-KAPE-Ram.zip
# LOG:    Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-KAPE-Ram_{TIMESTAMP}.log
#
# =============================================================================


# =============================================================================
# STEP 1: Bootstrap - load libraries, init logging, load config
# =============================================================================

. "$PSScriptRoot\Lib\Cerberus-Bootstrap.ps1"
Import-CerberusLibraries -ScriptRoot $PSScriptRoot

$run = Initialize-CerberusRun -Operation "KAPE-Ram" -ScriptRoot $PSScriptRoot
$Config = $run.Config
$EvidenceFolder = $run.EvidenceFolder


# =============================================================================
# STEP 2: Setup paths and check KAPE exists
# =============================================================================

$KapeExe = "$PSScriptRoot\$($PATHS.Kape)"
$OutputFolder = "$EvidenceFolder\$env:COMPUTERNAME-KAPE-Ram"
$ZipFile = Get-ZipFileName -Tool "KAPE-Ram" -Directory $EvidenceFolder

if (-not (Test-Path $KapeExe)) {
    Write-Log "KAPE not found at: $KapeExe" "ERROR" -Category "TOOL"
    Write-Log "Make sure KAPE is installed in the Bin\KAPE folder" "ERROR" -Category "TOOL"
    Complete-LogSession -Status "FAILED"
    exit 1
}

Write-Log "Found KAPE at: $KapeExe" "SUCCESS" -Category "TOOL"


# =============================================================================
# STEP 3: Check available RAM and disk space
# =============================================================================

$totalRamGB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$requiredGB = [math]::Ceiling($totalRamGB * $SPACE_REQUIREMENTS.RamOverhead)


# =============================================================================
# STEP 4: Pre-flight check and user confirmation
# =============================================================================

$targetDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$((Get-Item $EvidenceFolder).PSDrive.Name):'"
$targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 2)

$overheadGB = [math]::Round($totalRamGB * 0.1, 2)

Write-Log "" "INFO"
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "KAPE MEMORY CAPTURE - PRE-FLIGHT CHECK" "INFO" -Category "PREFLIGHT"
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "SYSTEM MEMORY" "INFO" -Category "PREFLIGHT"
Write-Log "  Installed RAM:     $totalRamGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "WHAT GETS CAPTURED" "INFO" -Category "PREFLIGHT"
Write-Log "  - Full physical memory dump" "INFO" -Category "PREFLIGHT"
Write-Log "  - Running processes" "INFO" -Category "PREFLIGHT"
Write-Log "  - Network connections" "INFO" -Category "PREFLIGHT"
Write-Log "  - Encryption keys (if in memory)" "INFO" -Category "PREFLIGHT"
Write-Log "  - Memory-resident malware" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "OUTPUT LOCATION" "INFO" -Category "PREFLIGHT"
Write-Log "  Path:              $EvidenceFolder" "INFO" -Category "PREFLIGHT"
Write-Log "  Free Space:        $targetFreeGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "SPACE CALCULATION" "INFO" -Category "PREFLIGHT"
Write-Log "  Memory Dump:       $totalRamGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  Overhead (10%):    $overheadGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  --------------------------------" "INFO" -Category "PREFLIGHT"
Write-Log "  Total Required:    $requiredGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  Available:         $targetFreeGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "ESTIMATED RUN TIME" "INFO" -Category "PREFLIGHT"
Write-Log "  Duration:          5 - 15 minutes" "INFO" -Category "PREFLIGHT"
Write-Log "  Timeout:           2 hours" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "OUTPUT FILE" "INFO" -Category "PREFLIGHT"
Write-Log "  $(Split-Path $ZipFile -Leaf)" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"

if ($targetFreeGB -lt $requiredGB) {
    Write-Log "STATUS: FAILED - Not enough disk space!" "ERROR" -Category "PREFLIGHT"
    Write-Log "" "INFO"
    Write-Log "Need $requiredGB GB for RAM dump, only $targetFreeGB GB available." "ERROR" -Category "PREFLIGHT"
    Write-Log "" "INFO"
    Write-Log "HOW TO FIX:" "INFO" -Category "PREFLIGHT"
    Write-Log "  1. Free up at least $([math]::Ceiling($requiredGB - $targetFreeGB)) GB on the drive" "INFO" -Category "PREFLIGHT"
    Write-Log "  2. Or use an external drive by setting Paths.EvidenceRoot in config" "INFO" -Category "PREFLIGHT"
    Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
    Complete-LogSession -Status "FAILED"
    exit 1
} else {
    Write-Log "STATUS: OK - Ready to capture" "SUCCESS" -Category "PREFLIGHT"
}
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
if ([Environment]::UserInteractive) {
    Write-Log "Press any key to start memory capture, or Ctrl+C to cancel..." "INFO" -Category "PREFLIGHT"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Log "" "INFO"
}


# =============================================================================
# STEP 5: Create output folder, build arguments, and run KAPE
# =============================================================================

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Log "Created output folder: $OutputFolder" "INFO" -Category "CONFIG"
}

$Arguments = $Config.Tools.Kape.RamArgs -replace '\$\{Output\}', "`"$OutputFolder`""

Write-Log "KAPE arguments: $Arguments" "INFO" -Category "TOOL"
Write-Log "Starting RAM capture (5-15 minutes)..." "INFO" -Category "TOOL"
Write-Log "==========================================" "INFO" -Category "TOOL"

$result = Start-ToolWithMonitoring `
    -ExePath $KapeExe `
    -Arguments $Arguments `
    -ToolName "KAPE-RAM" `
    -TimeoutMs $TIMEOUTS.KapeRam

Write-Log "==========================================" "INFO" -Category "TOOL"

# RAM capture hard-fails on tool error - no partial results to salvage
if (-not $result.Success) {
    Write-Log "RAM capture failed: $($result.Error)" "ERROR" -Category "TOOL"
    Complete-LogSession -Status "FAILED"
    exit 1
}

Write-Log "RAM capture complete!" "SUCCESS" -Category "TOOL"


# =============================================================================
# STEP 6: Compress and upload
# =============================================================================

$zipSizeFormatted = Compress-Evidence -SourcePath $OutputFolder -ZipFile $ZipFile

Complete-CerberusRun -ZipFile $ZipFile -ZipSizeFormatted $zipSizeFormatted -Config $Config -ScriptRoot $PSScriptRoot

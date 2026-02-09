# =============================================================================
# RUN-THOR.PS1 - Runs THOR malware scanner and uploads results
# =============================================================================
#
# USAGE: .\Run-Thor.ps1
#
# Scans for viruses, malware, hacking tools, and signs of compromise (IOCs).
# Usually takes 1-4 hours depending on disk size and file count.
#
# OUTPUT: HOSTNAME-DOMAIN-THOR.zip
# LOG:    Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-THOR_{TIMESTAMP}.log
#
# =============================================================================


# =============================================================================
# STEP 1: Bootstrap - load libraries, init logging, load config
# =============================================================================

. "$PSScriptRoot\Lib\Cerberus-Bootstrap.ps1"
Import-CerberusLibraries -ScriptRoot $PSScriptRoot

$run = Initialize-CerberusRun -Operation "THOR" -ScriptRoot $PSScriptRoot
$Config = $run.Config
$EvidenceFolder = $run.EvidenceFolder


# =============================================================================
# STEP 2: Setup paths and check THOR exists
# =============================================================================

$ThorExe = "$PSScriptRoot\$($PATHS.Thor)"
$OutputFolder = "$EvidenceFolder\$env:COMPUTERNAME-THOR"
$ZipFile = Get-ZipFileName -Tool "THOR" -Directory $EvidenceFolder

if (-not (Test-Path $ThorExe)) {
    Write-Log "THOR not found at: $ThorExe" "ERROR" -Category "TOOL"
    Write-Log "Make sure THOR is installed in the Bin\THOR folder" "ERROR" -Category "TOOL"
    Complete-LogSession -Status "FAILED"
    exit 1
}

Write-Log "Found THOR at: $ThorExe" "SUCCESS" -Category "TOOL"

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Log "Created output folder: $OutputFolder" "INFO" -Category "CONFIG"
}


# =============================================================================
# STEP 3: Build command arguments
# =============================================================================
# THOR does NOT support --output. Use --logfile and --htmlfile instead.

$LogFile = "$OutputFolder\$env:COMPUTERNAME.txt"
$HtmlFile = "$OutputFolder\$env:COMPUTERNAME.html"
$Arguments = "--logfile `"$LogFile`" --htmlfile `"$HtmlFile`" $($Config.Tools.Thor.Args)"

Write-Log "THOR arguments: $Arguments" "INFO" -Category "TOOL"


# =============================================================================
# STEP 4: Pre-flight check and user confirmation
# =============================================================================

$sourceDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$totalGB = [math]::Round($sourceDrive.Size / 1GB, 2)
$usedGB = [math]::Round(($sourceDrive.Size - $sourceDrive.FreeSpace) / 1GB, 2)

$targetDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$((Get-Item $EvidenceFolder).PSDrive.Name):'"
$targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 2)

Write-Log "" "INFO"
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "THOR MALWARE SCAN - PRE-FLIGHT CHECK" "INFO" -Category "PREFLIGHT"
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "SCAN TARGET" "INFO" -Category "PREFLIGHT"
Write-Log "  Drive:             C:\" "INFO" -Category "PREFLIGHT"
Write-Log "  Total Size:        $totalGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  Used Space:        $usedGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "OUTPUT LOCATION" "INFO" -Category "PREFLIGHT"
Write-Log "  Path:              $EvidenceFolder" "INFO" -Category "PREFLIGHT"
Write-Log "  Free Space:        $targetFreeGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "EXPECTED OUTPUT" "INFO" -Category "PREFLIGHT"
Write-Log "  Log Files:         ~500 MB maximum" "INFO" -Category "PREFLIGHT"
Write-Log "  Space Required:    1 GB (with buffer)" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "ESTIMATED RUN TIME" "INFO" -Category "PREFLIGHT"
Write-Log "  Duration:          1 - 4 hours" "INFO" -Category "PREFLIGHT"
Write-Log "  Timeout:           48 hours" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "OUTPUT FILE" "INFO" -Category "PREFLIGHT"
Write-Log "  $(Split-Path $ZipFile -Leaf)" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"

if ($targetFreeGB -lt $SPACE_REQUIREMENTS.ThorGB) {
    Write-Log "STATUS: FAILED - Not enough disk space!" "ERROR" -Category "PREFLIGHT"
    Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
    Complete-LogSession -Status "FAILED"
    exit 1
} else {
    Write-Log "STATUS: OK - Ready to scan" "SUCCESS" -Category "PREFLIGHT"
}
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
if ([Environment]::UserInteractive) {
    Write-Log "Press any key to start THOR scan, or Ctrl+C to cancel..." "INFO" -Category "PREFLIGHT"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Log "" "INFO"
}


# =============================================================================
# STEP 5: Run THOR with heartbeat monitoring
# =============================================================================
# Thor uses -ProgressFile to show log file growth as a progress indicator

Write-Log "Starting THOR scan (this may take 1-4 hours)..." "INFO" -Category "TOOL"
Write-Log "==========================================" "INFO" -Category "TOOL"

$result = Start-ToolWithMonitoring `
    -ExePath $ThorExe `
    -Arguments $Arguments `
    -ToolName "THOR" `
    -TimeoutMs $TIMEOUTS.Thor `
    -ProgressFile $LogFile

Write-Log "==========================================" "INFO" -Category "TOOL"

# THOR exit codes: 0=clean, 1=warnings, 2=alerts, 3=notices, 4+=error
if ($result.ExitCode -ge 4) {
    Write-Log "THOR failed with exit code: $($result.ExitCode)" "ERROR" -Category "TOOL"
    # Continue anyway to upload partial results
} elseif ($result.ExitCode -eq 0) {
    Write-Log "THOR completed: No threats detected" "SUCCESS" -Category "TOOL"
} else {
    Write-Log "THOR completed: Findings detected (exit code $($result.ExitCode))" "WARNING" -Category "TOOL"
}


# =============================================================================
# STEP 6: Compress and upload
# =============================================================================

$zipSizeFormatted = Compress-Evidence -SourcePath $OutputFolder -ZipFile $ZipFile

Complete-CerberusRun -ZipFile $ZipFile -ZipSizeFormatted $zipSizeFormatted -Config $Config -ScriptRoot $PSScriptRoot

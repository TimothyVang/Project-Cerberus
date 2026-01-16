# =============================================================================
# RUN-THOR.PS1 - Runs THOR malware scanner and uploads results
# =============================================================================
#
# USAGE: .\Run-Thor.ps1
#
# WHAT THIS SCRIPT DOES:
#   1. Load configuration from Cerberus_Config.json
#   2. Show pre-flight check with system info
#   3. Run THOR malware scanner (with heartbeat monitoring)
#   4. Compress the results into a .zip file
#   5. Upload the .zip to MinIO server
#
# WHAT IS THOR?
#   THOR is a malware scanner that looks for:
#   - Viruses and malware
#   - Hacking tools
#   - Signs of compromise (IOCs)
#   - Suspicious files and registry entries
#
# HOW LONG DOES IT TAKE?
#   Usually 1-4 hours depending on disk size and file count.
#
# OUTPUT FILE NAMING:
#   HOSTNAME-DOMAIN-THOR.zip (e.g., DESKTOP-PC1-WORKGROUP-THOR.zip)
#
# LOG FILE:
#   Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-THOR_{TIMESTAMP}.log
#
# =============================================================================


# =============================================================================
# STEP 1: Load shared libraries
# =============================================================================
# The dot (.) tells PowerShell to run these scripts in the current session,
# making their functions available for us to use.

. "$PSScriptRoot\Lib\Write-Log.ps1"
. "$PSScriptRoot\Lib\Cerberus-Constants.ps1"
. "$PSScriptRoot\Lib\Cerberus-Config.ps1"
. "$PSScriptRoot\Lib\Cerberus-Upload.ps1"
. "$PSScriptRoot\Lib\Cerberus-RunTool.ps1"


# =============================================================================
# STEP 2: Initialize log session
# =============================================================================

Initialize-LogSession -Operation "THOR" -ScriptRoot $PSScriptRoot


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
# This reads Cerberus_Config.json and validates it has all required fields.
# If anything is wrong, it prints an error and returns $null.

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
# Define where THOR is located and where to save output.

$ThorExe = "$PSScriptRoot\$($PATHS.Thor)"
$EvidenceFolder = "$PSScriptRoot\Evidence"
$OutputFolder = "$EvidenceFolder\$env:COMPUTERNAME-THOR"
$ZipFile = Get-ZipFileName -Tool "THOR" -Directory $EvidenceFolder


# =============================================================================
# STEP 5: Check THOR exists
# =============================================================================

if (-not (Test-Path $ThorExe)) {
    Write-Log "THOR not found at: $ThorExe" "ERROR" -Category "TOOL"
    Write-Log "Make sure THOR is installed in the Bin\THOR folder" "ERROR" -Category "TOOL"
    Complete-LogSession -Status "FAILED"
    exit 1
}

Write-Log "Found THOR at: $ThorExe" "SUCCESS" -Category "TOOL"


# =============================================================================
# STEP 6: Create output folder
# =============================================================================
# New-Item creates the folder. -Force means "don't error if it exists".
# | Out-Null hides the output (we don't need to see it).

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Log "Created output folder: $OutputFolder" "INFO" -Category "CONFIG"
}


# =============================================================================
# STEP 7: Build command arguments
# =============================================================================
# THOR needs to know where to save its log files.
# --logfile = text log, --htmlfile = HTML report

$LogFile = "$OutputFolder\$env:COMPUTERNAME.txt"
$HtmlFile = "$OutputFolder\$env:COMPUTERNAME.html"
$Arguments = "--logfile `"$LogFile`" --htmlfile `"$HtmlFile`" $($Config.Tools.Thor.Args)"

Write-Log "THOR arguments: $Arguments" "INFO" -Category "TOOL"


# =============================================================================
# STEP 8: Pre-flight check and user confirmation
# =============================================================================

# Get system information for pre-flight display
$sourceDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$totalGB = [math]::Round($sourceDrive.Size / 1GB, 2)
$usedGB = [math]::Round(($sourceDrive.Size - $sourceDrive.FreeSpace) / 1GB, 2)
$freeGB = [math]::Round($sourceDrive.FreeSpace / 1GB, 2)

$targetDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$((Get-Item $EvidenceFolder).PSDrive.Name):'"
$targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 2)

$domain = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "WORKGROUP" }

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

# Check if we have enough space
if ($targetFreeGB -lt 1) {
    Write-Log "STATUS: FAILED - Not enough disk space!" "ERROR" -Category "PREFLIGHT"
    Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
    Complete-LogSession -Status "FAILED"
    exit 1
} else {
    Write-Log "STATUS: OK - Ready to scan" "SUCCESS" -Category "PREFLIGHT"
}
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "Press any key to start THOR scan, or Ctrl+C to cancel..." "INFO" -Category "PREFLIGHT"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Log "" "INFO"

# =============================================================================
# STEP 9: Run THOR with heartbeat monitoring
# =============================================================================
# This runs THOR and prints "still running" every 60 seconds.
# It will kill THOR if it runs longer than the timeout (48 hours).

Write-Log "Starting THOR scan (this may take 1-4 hours)..." "INFO" -Category "TOOL"
Write-Log "==========================================" "INFO" -Category "TOOL"

$result = Start-ToolWithMonitoring `
    -ExePath $ThorExe `
    -Arguments $Arguments `
    -ToolName "THOR" `
    -TimeoutMs $TIMEOUTS.Thor `
    -ProgressFile $LogFile

Write-Log "==========================================" "INFO" -Category "TOOL"

# Check if THOR succeeded
# Exit codes: 0=clean, 1=warnings, 2=alerts, 3=notices, 4+=error
if ($result.ExitCode -ge 4) {
    Write-Log "THOR failed with exit code: $($result.ExitCode)" "ERROR" -Category "TOOL"
    # Continue anyway to upload partial results
} elseif ($result.ExitCode -eq 0) {
    Write-Log "THOR completed: No threats detected" "SUCCESS" -Category "TOOL"
} else {
    Write-Log "THOR completed: Findings detected (exit code $($result.ExitCode))" "WARNING" -Category "TOOL"
}


# =============================================================================
# STEP 10: Compress results
# =============================================================================
# Zip up all the output files for easier upload.

Write-Log "Compressing results..." "INFO" -Category "COMPRESS"

if (Test-Path $OutputFolder) {
    try {
        # Remove old zip if exists
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
# STEP 11: Complete THOR log session before upload
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

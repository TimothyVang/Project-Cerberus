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
# STEP 2: Load configuration
# =============================================================================
# This reads Cerberus_Config.json and validates it has all required fields.
# If anything is wrong, it prints an error and returns $null.

Write-Log "Loading configuration..."

$Config = Get-CerberusConfig -ScriptRoot $PSScriptRoot

if (-not $Config) {
    Write-Log "Failed to load configuration" "ERROR"
    exit 1
}


# =============================================================================
# STEP 3: Setup paths
# =============================================================================
# Define where THOR is located and where to save output.

$ThorExe = "$PSScriptRoot\$($PATHS.Thor)"
$EvidenceFolder = "$PSScriptRoot\Evidence"
$OutputFolder = "$EvidenceFolder\$env:COMPUTERNAME-THOR"
$ZipFile = Get-ZipFileName -Tool "THOR" -Directory $EvidenceFolder


# =============================================================================
# STEP 4: Check THOR exists
# =============================================================================

if (-not (Test-Path $ThorExe)) {
    Write-Log "THOR not found at: $ThorExe" "ERROR"
    Write-Log "Make sure THOR is installed in the Bin\THOR folder" "ERROR"
    exit 1
}

Write-Log "Found THOR at: $ThorExe" "SUCCESS"


# =============================================================================
# STEP 5: Create output folder
# =============================================================================
# New-Item creates the folder. -Force means "don't error if it exists".
# | Out-Null hides the output (we don't need to see it).

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Log "Created output folder: $OutputFolder"
}


# =============================================================================
# STEP 6: Build command arguments
# =============================================================================
# THOR needs to know where to save its log files.
# --logfile = text log, --htmlfile = HTML report

$LogFile = "$OutputFolder\$env:COMPUTERNAME.txt"
$HtmlFile = "$OutputFolder\$env:COMPUTERNAME.html"
$Arguments = "--logfile `"$LogFile`" --htmlfile `"$HtmlFile`" $($Config.Tools.Thor.Args)"

Write-Log "THOR arguments: $Arguments"


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

Write-Host ""
Write-Host "==========================================="
Write-Host "THOR MALWARE SCAN - PRE-FLIGHT CHECK"
Write-Host "==========================================="
Write-Host ""
Write-Host "SCAN TARGET" -ForegroundColor Yellow
Write-Host "  Drive:             C:\"
Write-Host "  Total Size:        $totalGB GB"
Write-Host "  Used Space:        $usedGB GB"
Write-Host ""
Write-Host "OUTPUT LOCATION" -ForegroundColor Yellow
Write-Host "  Path:              $EvidenceFolder"
Write-Host "  Free Space:        $targetFreeGB GB"
Write-Host ""
Write-Host "EXPECTED OUTPUT" -ForegroundColor Yellow
Write-Host "  Log Files:         ~500 MB maximum"
Write-Host "  Space Required:    1 GB (with buffer)"
Write-Host ""
Write-Host "ESTIMATED RUN TIME" -ForegroundColor Yellow
Write-Host "  Duration:          1 - 4 hours"
Write-Host "  Timeout:           48 hours"
Write-Host ""
Write-Host "OUTPUT FILE" -ForegroundColor Yellow
Write-Host "  $(Split-Path $ZipFile -Leaf)"
Write-Host ""

# Check if we have enough space
if ($targetFreeGB -lt 1) {
    Write-Host "STATUS: " -NoNewline
    Write-Host "FAILED - Not enough disk space!" -ForegroundColor Red
    Write-Host "==========================================="
    exit 1
} else {
    Write-Host "STATUS: " -NoNewline
    Write-Host "OK - Ready to scan" -ForegroundColor Green
}
Write-Host "==========================================="
Write-Host ""
Write-Host "Press any key to start THOR scan, or Ctrl+C to cancel..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""

# =============================================================================
# STEP 8: Run THOR with heartbeat monitoring
# =============================================================================
# This runs THOR and prints "still running" every 60 seconds.
# It will kill THOR if it runs longer than the timeout (48 hours).

Write-Log "Starting THOR scan (this may take 1-4 hours)..."
Write-Log "=========================================="

$result = Start-ToolWithMonitoring `
    -ExePath $ThorExe `
    -Arguments $Arguments `
    -ToolName "THOR" `
    -TimeoutMs $TIMEOUTS.Thor `
    -ProgressFile $LogFile

Write-Log "=========================================="

# Check if THOR succeeded
# Exit codes: 0=clean, 1=warnings, 2=alerts, 3=notices, 4+=error
if ($result.ExitCode -ge 4) {
    Write-Log "THOR failed with exit code: $($result.ExitCode)" "ERROR"
    # Continue anyway to upload partial results
} elseif ($result.ExitCode -eq 0) {
    Write-Log "THOR completed: No threats detected" "SUCCESS"
} else {
    Write-Log "THOR completed: Findings detected (exit code $($result.ExitCode))" "WARNING"
}


# =============================================================================
# STEP 9: Compress results
# =============================================================================
# Zip up all the output files for easier upload.

Write-Log "Compressing results..."

if (Test-Path $OutputFolder) {
    try {
        # Remove old zip if exists
        if (Test-Path $ZipFile) {
            Remove-Item $ZipFile -Force
        }
        
        Compress-Archive -Path "$OutputFolder\*" -DestinationPath $ZipFile -Force
        
        $zipSize = [math]::Round((Get-Item $ZipFile).Length / 1MB, 2)
        Write-Log "Created: $ZipFile ($zipSize MB)" "SUCCESS"
    }
    catch {
        Write-Log "Failed to compress: $($_.Exception.Message)" "ERROR"
        exit 1
    }
} else {
    Write-Log "No output folder found - nothing to compress" "WARNING"
    exit 1
}


# =============================================================================
# STEP 10: Upload to MinIO
# =============================================================================

Write-Log "Uploading to MinIO..."

$uploaded = Send-ToMinIO -FilePath $ZipFile -Config $Config -ScriptRoot $PSScriptRoot

if ($uploaded) {
    Write-Log "=========================================="
    Write-Log "SUCCESS: Evidence uploaded to MinIO" "SUCCESS"
    Write-Log "=========================================="
    exit 0
} else {
    Write-Log "=========================================="
    Write-Log "Upload failed - evidence saved locally" "WARNING"
    Write-Log "Local file: $ZipFile" "WARNING"
    Write-Log "=========================================="
    exit 1
}

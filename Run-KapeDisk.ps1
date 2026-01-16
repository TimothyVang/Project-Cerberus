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

Write-Log "Loading configuration..."

$Config = Get-CerberusConfig -ScriptRoot $PSScriptRoot

if (-not $Config) {
    Write-Log "Failed to load configuration" "ERROR"
    exit 1
}


# =============================================================================
# STEP 3: Setup paths
# =============================================================================

$KapeExe = "$PSScriptRoot\$($PATHS.Kape)"
$EvidenceFolder = "$PSScriptRoot\Evidence"
$OutputFolder = "$EvidenceFolder\$env:COMPUTERNAME-KAPE-Disk"
$ZipFile = Get-ZipFileName -Tool "KAPE-Disk" -Directory $EvidenceFolder

# Get compression level from config (default to Optimal)
$CompressionLevel = if ($Config.Compression -and $Config.Compression.Level) { 
    $Config.Compression.Level 
} else { 
    "Optimal" 
}


# =============================================================================
# STEP 4: Check KAPE exists
# =============================================================================

if (-not (Test-Path $KapeExe)) {
    Write-Log "KAPE not found at: $KapeExe" "ERROR"
    Write-Log "Make sure KAPE is installed in the Bin\KAPE folder" "ERROR"
    exit 1
}

Write-Log "Found KAPE at: $KapeExe" "SUCCESS"


# =============================================================================
# STEP 5: Check disk space
# =============================================================================
# KAPE can collect several GB of data, so we need enough free space.

if (-not (Test-Path $EvidenceFolder)) {
    New-Item -ItemType Directory -Path $EvidenceFolder -Force | Out-Null
}

# =============================================================================
# STEP 6: Pre-flight check and user confirmation
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

Write-Host ""
Write-Host "==========================================="
Write-Host "KAPE DISK COLLECTION - PRE-FLIGHT CHECK"
Write-Host "==========================================="
Write-Host ""
Write-Host "COLLECTION SOURCE" -ForegroundColor Yellow
Write-Host "  Drive:             C:\"
Write-Host "  Total Size:        $totalGB GB"
Write-Host "  Used Space:        $usedGB GB"
Write-Host ""
Write-Host "TARGETS TO COLLECT" -ForegroundColor Yellow
Write-Host "  - Registry Hives (SYSTEM, SAM, SOFTWARE, NTUSER.DAT)"
Write-Host "  - Event Logs (Security, System, Application)"
Write-Host "  - Prefetch Files"
Write-Host "  - Browser History"
Write-Host "  - `$MFT, `$UsnJrnl"
Write-Host "  - BITS Database"
Write-Host ""
Write-Host "OUTPUT LOCATION" -ForegroundColor Yellow
Write-Host "  Path:              $EvidenceFolder"
Write-Host "  Free Space:        $targetFreeGB GB"
Write-Host ""
Write-Host "SPACE CALCULATION" -ForegroundColor Yellow
Write-Host "  Typical Size:      2 - 20 GB"
Write-Host "  Space Required:    $requiredGB GB (with buffer)"
Write-Host "  Available:         $targetFreeGB GB"
Write-Host ""
Write-Host "ESTIMATED RUN TIME" -ForegroundColor Yellow
Write-Host "  Duration:          15 - 45 minutes"
Write-Host "  Timeout:           24 hours"
Write-Host ""
Write-Host "COMPRESSION" -ForegroundColor Yellow
Write-Host "  Level:             $CompressionLevel"
Write-Host ""
Write-Host "OUTPUT FILE" -ForegroundColor Yellow
Write-Host "  $(Split-Path $ZipFile -Leaf)"
Write-Host ""

# Check if we have enough space
if ($targetFreeGB -lt $requiredGB) {
    Write-Host "STATUS: " -NoNewline
    Write-Host "FAILED - Not enough disk space!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Need $requiredGB GB, only $targetFreeGB GB available." -ForegroundColor Red
    Write-Host "==========================================="
    exit 1
} else {
    Write-Host "STATUS: " -NoNewline
    Write-Host "OK - Ready to collect" -ForegroundColor Green
}
Write-Host "==========================================="
Write-Host ""
Write-Host "Press any key to start KAPE Disk collection, or Ctrl+C to cancel..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""


# =============================================================================
# STEP 7: Build command arguments
# =============================================================================
# KAPE arguments come from the config file.
# We replace ${Output} with the actual output folder path.

$Arguments = $Config.Tools.Kape.DiskArgs -replace '\$\{Output\}', "`"$OutputFolder`""

Write-Log "KAPE arguments: $Arguments"


# =============================================================================
# STEP 8: Run KAPE with heartbeat monitoring
# =============================================================================

Write-Log "Starting KAPE artifact collection (15-30 minutes)..."
Write-Log "=========================================="

$result = Start-ToolWithMonitoring `
    -ExePath $KapeExe `
    -Arguments $Arguments `
    -ToolName "KAPE" `
    -TimeoutMs $TIMEOUTS.Kape

Write-Log "=========================================="

if (-not $result.Success) {
    Write-Log "KAPE failed: $($result.Error)" "ERROR"
    # Continue anyway to upload partial results
}


# =============================================================================
# STEP 9: Compress results
# =============================================================================

Write-Log "Compressing results..."

if (Test-Path $OutputFolder) {
    try {
        if (Test-Path $ZipFile) {
            Remove-Item $ZipFile -Force
        }
        
        Compress-Archive -Path "$OutputFolder\*" -DestinationPath $ZipFile -CompressionLevel $CompressionLevel -Force
        
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

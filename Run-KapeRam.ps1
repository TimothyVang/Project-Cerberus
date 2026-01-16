# =============================================================================
# RUN-KAPERAM.PS1 - Captures system memory (RAM) with KAPE
# =============================================================================
#
# USAGE: .\Run-KapeRam.ps1
#
# WHAT THIS SCRIPT DOES:
#   1. Load configuration from Cerberus_Config.json
#   2. Show pre-flight check with RAM and disk space info
#   3. Check disk space (need RAM size + 10% buffer)
#   4. Run KAPE to capture system memory
#   5. Compress the memory dump into a .zip file
#   6. Upload the .zip to MinIO server
#
# WHAT IS RAM CAPTURE?
#   This captures everything currently in the computer's memory:
#   - Running processes
#   - Open files
#   - Network connections
#   - Encryption keys
#   - Malware that only exists in memory
#
# WHY IS THIS USEFUL?
#   Some malware never touches the disk - it only lives in memory.
#   By capturing RAM, we can find things that would be invisible otherwise.
#
# HOW LONG DOES IT TAKE?
#   Usually 5-15 minutes depending on how much RAM the system has.
#   The output file will be roughly the same size as installed RAM.
#
# OUTPUT FILE NAMING:
#   HOSTNAME-DOMAIN-KAPE-Mem.zip (e.g., DESKTOP-PC1-WORKGROUP-KAPE-Mem.zip)
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
$OutputFolder = "$EvidenceFolder\$env:COMPUTERNAME-KAPE-Mem"
$ZipFile = Get-ZipFileName -Tool "KAPE-Mem" -Directory $EvidenceFolder

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
# STEP 5: Check available RAM and disk space
# =============================================================================

$totalRamGB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$requiredGB = [math]::Ceiling($totalRamGB * 1.1)  # RAM + 10% overhead

# Create evidence folder if needed
if (-not (Test-Path $EvidenceFolder)) {
    New-Item -ItemType Directory -Path $EvidenceFolder -Force | Out-Null
}

# =============================================================================
# STEP 6: Pre-flight check and user confirmation
# =============================================================================

# Get system information for pre-flight display
$targetDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$((Get-Item $EvidenceFolder).PSDrive.Name):'"
$targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 2)
$targetTotalGB = [math]::Round($targetDrive.Size / 1GB, 2)

$domain = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "WORKGROUP" }
$overheadGB = [math]::Round($totalRamGB * 0.1, 2)
$estimatedZipGB = [math]::Round($totalRamGB * 0.4, 1)  # Memory compresses well (~50-70%)

Write-Host ""
Write-Host "==========================================="
Write-Host "KAPE MEMORY CAPTURE - PRE-FLIGHT CHECK"
Write-Host "==========================================="
Write-Host ""
Write-Host "SYSTEM MEMORY" -ForegroundColor Yellow
Write-Host "  Installed RAM:     $totalRamGB GB"
Write-Host ""
Write-Host "WHAT GETS CAPTURED" -ForegroundColor Yellow
Write-Host "  - Full physical memory dump"
Write-Host "  - Running processes"
Write-Host "  - Network connections"
Write-Host "  - Encryption keys (if in memory)"
Write-Host "  - Memory-resident malware"
Write-Host ""
Write-Host "OUTPUT LOCATION" -ForegroundColor Yellow
Write-Host "  Path:              $EvidenceFolder"
Write-Host "  Free Space:        $targetFreeGB GB"
Write-Host ""
Write-Host "SPACE CALCULATION" -ForegroundColor Yellow
Write-Host "  Memory Dump:       $totalRamGB GB"
Write-Host "  Overhead (10%):    $overheadGB GB"
Write-Host "  --------------------------------"
Write-Host "  Total Required:    $requiredGB GB"
Write-Host "  Available:         $targetFreeGB GB"
Write-Host ""
Write-Host "ESTIMATED RUN TIME" -ForegroundColor Yellow
Write-Host "  Duration:          5 - 15 minutes"
Write-Host "  Timeout:           2 hours"
Write-Host ""
Write-Host "COMPRESSION" -ForegroundColor Yellow
Write-Host "  Level:             $CompressionLevel"
Write-Host "  Expected Ratio:    50-70% reduction"
Write-Host "  Estimated Zip:     ~$estimatedZipGB GB"
Write-Host ""
Write-Host "OUTPUT FILE" -ForegroundColor Yellow
Write-Host "  $(Split-Path $ZipFile -Leaf)"
Write-Host ""

# Check if we have enough space
if ($targetFreeGB -lt $requiredGB) {
    Write-Host "STATUS: " -NoNewline
    Write-Host "FAILED - Not enough disk space!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Need $requiredGB GB for RAM dump, only $targetFreeGB GB available." -ForegroundColor Red
    Write-Host ""
    Write-Host "HOW TO FIX:" -ForegroundColor Cyan
    Write-Host "  1. Free up at least $([math]::Ceiling($requiredGB - $targetFreeGB)) GB on the drive"
    Write-Host "  2. Or use an external drive by setting Paths.EvidenceRoot in config"
    Write-Host "==========================================="
    exit 1
} else {
    Write-Host "STATUS: " -NoNewline
    Write-Host "OK - Ready to capture" -ForegroundColor Green
}
Write-Host "==========================================="
Write-Host ""
Write-Host "Press any key to start memory capture, or Ctrl+C to cancel..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""

# =============================================================================
# STEP 7: Create output folder
# =============================================================================

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Log "Created output folder: $OutputFolder"
}


# =============================================================================
# STEP 8: Build command arguments
# =============================================================================

$Arguments = $Config.Tools.Kape.RamArgs -replace '\$\{Output\}', "`"$OutputFolder`""

Write-Log "KAPE arguments: $Arguments"


# =============================================================================
# STEP 9: Run KAPE RAM capture with heartbeat monitoring
# =============================================================================

Write-Log "Starting RAM capture (5-15 minutes)..."
Write-Log "=========================================="

$result = Start-ToolWithMonitoring `
    -ExePath $KapeExe `
    -Arguments $Arguments `
    -ToolName "KAPE-RAM" `
    -TimeoutMs $TIMEOUTS.KapeRam

Write-Log "=========================================="

if (-not $result.Success) {
    Write-Log "RAM capture failed: $($result.Error)" "ERROR"
    exit 1
}

Write-Log "RAM capture complete!" "SUCCESS"


# =============================================================================
# STEP 10: Compress results
# =============================================================================

Write-Log "Compressing RAM dump (this may take a while)..."

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
# STEP 11: Upload to MinIO
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

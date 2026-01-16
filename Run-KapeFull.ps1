# =============================================================================
# RUN-KAPEFULL.PS1 - Collects BOTH disk artifacts AND memory with KAPE
# =============================================================================
#
# USAGE: .\Run-KapeFull.ps1
#
# WHAT THIS SCRIPT DOES:
#   1. Load configuration from Cerberus_Config.json
#   2. Show pre-flight check with disk and RAM space requirements
#   3. Run KAPE to collect disk artifacts AND capture memory
#   4. Create TWO separate zip files (one for disk, one for memory)
#   5. Upload both zips to MinIO server
#
# WHY USE THIS INSTEAD OF SEPARATE SCRIPTS?
#   - Runs both collections in a single KAPE execution
#   - More efficient than running Run-KapeDisk.ps1 and Run-KapeRam.ps1 separately
#   - Creates separate zip files for easier analysis
#
# WHAT GETS COLLECTED?
#   DISK ARTIFACTS:
#   - Windows Registry hives
#   - Event logs
#   - Prefetch files
#   - Browser history
#   - MFT (file system metadata)
#   - And more...
#
#   MEMORY:
#   - Full physical memory dump
#   - Running processes
#   - Network connections
#   - Encryption keys (if in memory)
#   - Memory-resident malware
#
# HOW LONG DOES IT TAKE?
#   Usually 20-60 minutes total.
#
# OUTPUT FILE NAMING:
#   HOSTNAME-DOMAIN-KAPE-Disk.zip
#   HOSTNAME-DOMAIN-KAPE-Mem.zip
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

# Separate output folders for disk and memory
$DiskOutputFolder = "$EvidenceFolder\$env:COMPUTERNAME-KAPE-Disk"
$MemOutputFolder = "$EvidenceFolder\$env:COMPUTERNAME-KAPE-Mem"

# Separate zip files
$DiskZipFile = Get-ZipFileName -Tool "KAPE-Disk" -Directory $EvidenceFolder
$MemZipFile = Get-ZipFileName -Tool "KAPE-Mem" -Directory $EvidenceFolder

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
# STEP 5: Calculate space requirements
# =============================================================================

# Get RAM size
$totalRamGB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$ramOverheadGB = [math]::Round($totalRamGB * 0.1, 2)

# Disk artifacts estimate
$diskArtifactsGB = 25  # Max estimate for disk artifacts

# Total required
$totalRequiredGB = [math]::Ceiling($totalRamGB + $diskArtifactsGB + ($totalRamGB * 0.1))

# Create evidence folder if needed
if (-not (Test-Path $EvidenceFolder)) {
    New-Item -ItemType Directory -Path $EvidenceFolder -Force | Out-Null
}


# =============================================================================
# STEP 6: Pre-flight check and user confirmation
# =============================================================================

# Get system information for pre-flight display
$sourceDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$sourceTotalGB = [math]::Round($sourceDrive.Size / 1GB, 2)
$sourceUsedGB = [math]::Round(($sourceDrive.Size - $sourceDrive.FreeSpace) / 1GB, 2)

$targetDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$((Get-Item $EvidenceFolder).PSDrive.Name):'"
$targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 2)

$domain = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "WORKGROUP" }

# Estimate compressed sizes
$estimatedDiskZipGB = [math]::Round($diskArtifactsGB * 0.5, 1)
$estimatedMemZipGB = [math]::Round($totalRamGB * 0.4, 1)

Write-Host ""
Write-Host "==========================================="
Write-Host "KAPE FULL COLLECTION - PRE-FLIGHT CHECK"
Write-Host "==========================================="
Write-Host ""
Write-Host "This will collect BOTH disk artifacts AND memory."
Write-Host "Two separate zip files will be created."
Write-Host ""
Write-Host "SYSTEM INFO" -ForegroundColor Yellow
Write-Host "  Computer:          $env:COMPUTERNAME"
Write-Host "  Domain:            $domain"
Write-Host "  Installed RAM:     $totalRamGB GB"
Write-Host ""
Write-Host "SOURCE DRIVE (C:)" -ForegroundColor Yellow
Write-Host "  Total Size:        $sourceTotalGB GB"
Write-Host "  Used Space:        $sourceUsedGB GB"
Write-Host ""
Write-Host "OUTPUT LOCATION" -ForegroundColor Yellow
Write-Host "  Path:              $EvidenceFolder"
Write-Host "  Free Space:        $targetFreeGB GB"
Write-Host ""
Write-Host "SPACE CALCULATION" -ForegroundColor Yellow
Write-Host "  Disk Artifacts:    $diskArtifactsGB GB (max estimate)"
Write-Host "  Memory Dump:       $totalRamGB GB"
Write-Host "  Overhead (10%):    $ramOverheadGB GB"
Write-Host "  --------------------------------"
Write-Host "  Total Required:    $totalRequiredGB GB"
Write-Host "  Available:         $targetFreeGB GB"
Write-Host ""
Write-Host "ESTIMATED RUN TIME" -ForegroundColor Yellow
Write-Host "  Disk Collection:   15 - 45 minutes"
Write-Host "  Memory Capture:    5 - 15 minutes"
Write-Host "  Total:             20 - 60 minutes"
Write-Host "  Timeout:           24 hours"
Write-Host ""
Write-Host "COMPRESSION" -ForegroundColor Yellow
Write-Host "  Level:             $CompressionLevel"
Write-Host ""
Write-Host "OUTPUT FILES" -ForegroundColor Yellow
Write-Host "  1. $(Split-Path $DiskZipFile -Leaf) (~$estimatedDiskZipGB GB)"
Write-Host "  2. $(Split-Path $MemZipFile -Leaf) (~$estimatedMemZipGB GB)"
Write-Host ""

# Check if we have enough space
if ($targetFreeGB -lt $totalRequiredGB) {
    Write-Host "STATUS: " -NoNewline
    Write-Host "FAILED - Not enough disk space!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Need $totalRequiredGB GB, only $targetFreeGB GB available." -ForegroundColor Red
    Write-Host ""
    Write-Host "OPTIONS:" -ForegroundColor Cyan
    Write-Host "  1. Free up $([math]::Ceiling($totalRequiredGB - $targetFreeGB)) GB on the drive"
    Write-Host "  2. Run Run-KapeDisk.ps1 and Run-KapeRam.ps1 separately"
    Write-Host "  3. Use an external drive by setting Paths.EvidenceRoot in config"
    Write-Host "==========================================="
    exit 1
} else {
    Write-Host "STATUS: " -NoNewline
    Write-Host "OK - Ready to collect" -ForegroundColor Green
}
Write-Host "==========================================="
Write-Host ""
Write-Host "Press any key to start KAPE Full collection, or Ctrl+C to cancel..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""


# =============================================================================
# STEP 7: Create output folders
# =============================================================================

if (-not (Test-Path $DiskOutputFolder)) {
    New-Item -ItemType Directory -Path $DiskOutputFolder -Force | Out-Null
    Write-Log "Created disk output folder: $DiskOutputFolder"
}

if (-not (Test-Path $MemOutputFolder)) {
    New-Item -ItemType Directory -Path $MemOutputFolder -Force | Out-Null
    Write-Log "Created memory output folder: $MemOutputFolder"
}


# =============================================================================
# STEP 8: Build combined KAPE arguments
# =============================================================================
# KAPE can run both disk targets and memory modules in a single execution

$DiskArgs = $Config.Tools.Kape.DiskArgs -replace '\$\{Output\}', "`"$DiskOutputFolder`""
$RamArgs = $Config.Tools.Kape.RamArgs -replace '\$\{Output\}', "`"$MemOutputFolder`""

# Combine both argument sets
$CombinedArgs = "$DiskArgs $RamArgs"

Write-Log "KAPE Combined arguments: $CombinedArgs"


# =============================================================================
# STEP 9: Run KAPE with heartbeat monitoring
# =============================================================================

Write-Log "Starting KAPE Full collection (disk + memory)..."
Write-Log "=========================================="

$result = Start-ToolWithMonitoring `
    -ExePath $KapeExe `
    -Arguments $CombinedArgs `
    -ToolName "KAPE-FULL" `
    -TimeoutMs $TIMEOUTS.Kape

Write-Log "=========================================="

if (-not $result.Success) {
    Write-Log "KAPE Full collection had errors: $($result.Error)" "WARNING"
    # Continue anyway to upload partial results
}


# =============================================================================
# STEP 10: Compress disk artifacts
# =============================================================================

Write-Log "Compressing disk artifacts..."

$diskCompressSuccess = $false
if (Test-Path $DiskOutputFolder) {
    $diskFiles = Get-ChildItem $DiskOutputFolder -Recurse -File
    if ($diskFiles.Count -gt 0) {
        try {
            if (Test-Path $DiskZipFile) {
                Remove-Item $DiskZipFile -Force
            }
            
            Compress-Archive -Path "$DiskOutputFolder\*" -DestinationPath $DiskZipFile -CompressionLevel $CompressionLevel -Force
            
            $zipSize = [math]::Round((Get-Item $DiskZipFile).Length / 1MB, 2)
            Write-Log "Created: $DiskZipFile ($zipSize MB)" "SUCCESS"
            $diskCompressSuccess = $true
        }
        catch {
            Write-Log "Failed to compress disk artifacts: $($_.Exception.Message)" "ERROR"
        }
    } else {
        Write-Log "No disk artifacts collected" "WARNING"
    }
} else {
    Write-Log "Disk output folder not found" "WARNING"
}


# =============================================================================
# STEP 11: Compress memory dump
# =============================================================================

Write-Log "Compressing memory dump (this may take a while)..."

$memCompressSuccess = $false
if (Test-Path $MemOutputFolder) {
    $memFiles = Get-ChildItem $MemOutputFolder -Recurse -File
    if ($memFiles.Count -gt 0) {
        try {
            if (Test-Path $MemZipFile) {
                Remove-Item $MemZipFile -Force
            }
            
            Compress-Archive -Path "$MemOutputFolder\*" -DestinationPath $MemZipFile -CompressionLevel $CompressionLevel -Force
            
            $zipSize = [math]::Round((Get-Item $MemZipFile).Length / 1MB, 2)
            Write-Log "Created: $MemZipFile ($zipSize MB)" "SUCCESS"
            $memCompressSuccess = $true
        }
        catch {
            Write-Log "Failed to compress memory dump: $($_.Exception.Message)" "ERROR"
        }
    } else {
        Write-Log "No memory dump files found" "WARNING"
    }
} else {
    Write-Log "Memory output folder not found" "WARNING"
}


# =============================================================================
# STEP 12: Upload both zip files to MinIO
# =============================================================================

$uploadedCount = 0
$failedCount = 0

# Upload disk artifacts
if ($diskCompressSuccess) {
    Write-Log "Uploading disk artifacts to MinIO..."
    $uploaded = Send-ToMinIO -FilePath $DiskZipFile -Config $Config -ScriptRoot $PSScriptRoot
    if ($uploaded) { $uploadedCount++ } else { $failedCount++ }
}

# Upload memory dump
if ($memCompressSuccess) {
    Write-Log "Uploading memory dump to MinIO..."
    $uploaded = Send-ToMinIO -FilePath $MemZipFile -Config $Config -ScriptRoot $PSScriptRoot
    if ($uploaded) { $uploadedCount++ } else { $failedCount++ }
}


# =============================================================================
# STEP 13: Final status
# =============================================================================

Write-Log ""
Write-Log "=========================================="

if ($uploadedCount -eq 2 -and $failedCount -eq 0) {
    Write-Log "SUCCESS: Both evidence files uploaded to MinIO" "SUCCESS"
    Write-Log "  - $(Split-Path $DiskZipFile -Leaf)"
    Write-Log "  - $(Split-Path $MemZipFile -Leaf)"
    Write-Log "=========================================="
    exit 0
} elseif ($uploadedCount -gt 0) {
    Write-Log "PARTIAL: $uploadedCount uploaded, $failedCount failed" "WARNING"
    Write-Log "Evidence saved locally:" "WARNING"
    if ($diskCompressSuccess) { Write-Log "  - $DiskZipFile" "WARNING" }
    if ($memCompressSuccess) { Write-Log "  - $MemZipFile" "WARNING" }
    Write-Log "=========================================="
    exit 1
} else {
    Write-Log "FAILED: All uploads failed" "ERROR"
    Write-Log "Evidence saved locally:" "ERROR"
    if ($diskCompressSuccess) { Write-Log "  - $DiskZipFile" "ERROR" }
    if ($memCompressSuccess) { Write-Log "  - $MemZipFile" "ERROR" }
    Write-Log "=========================================="
    exit 1
}

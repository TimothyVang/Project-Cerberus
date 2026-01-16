# =============================================================================
# RUN-FTK.PS1 - Creates a full disk image with FTK Imager
# =============================================================================
#
# USAGE: .\Run-Ftk.ps1
#
# WHAT THIS SCRIPT DOES:
#   1. Load configuration from Cerberus_Config.json
#   2. Check disk space (need LOTS of free space!)
#   3. Run FTK Imager to create a bit-for-bit copy of the C: drive
#   4. Compress the disk image into a .zip file
#   5. Upload the .zip to MinIO server
#
# WHAT IS A DISK IMAGE?
#   A disk image is an exact copy of every byte on the hard drive.
#   This includes:
#   - All files (even deleted ones!)
#   - The operating system
#   - Hidden partitions
#   - Empty space (which may contain recoverable data)
#
# WHY IS THIS USEFUL?
#   A disk image preserves everything for forensic analysis.
#   Analysts can examine it without touching the original system.
#
# HOW LONG DOES IT TAKE?
#   Usually 2-8 hours depending on disk size.
#   A 500GB disk = ~500GB output file (before compression)
#
# WARNING: This creates VERY LARGE files! Make sure you have enough space.
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
# Try x64 version first, fall back to x86 for older systems

$FtkExe = "$PSScriptRoot\$($PATHS.FtkX64)"
if (-not (Test-Path $FtkExe)) {
    $FtkExe = "$PSScriptRoot\$($PATHS.FtkX86)"
}

# Use custom FTK path from config if specified
if ($Config.Paths.EnableCustomPaths -and $Config.Paths.FTK) {
    $OutputFolder = $Config.Paths.FTK -replace '\$\{ComputerName\}', $env:COMPUTERNAME
} else {
    $OutputFolder = "$PSScriptRoot\Evidence"
}

$ImageBase = "$OutputFolder\$env:COMPUTERNAME-Disk"
$ZipFile = "$OutputFolder\$env:COMPUTERNAME-FTK.zip"


# =============================================================================
# STEP 4: Check FTK exists
# =============================================================================

if (-not (Test-Path $FtkExe)) {
    Write-Log "FTK Imager not found!" "ERROR"
    Write-Log "Checked: $PSScriptRoot\$($PATHS.FtkX64)" "ERROR"
    Write-Log "Checked: $PSScriptRoot\$($PATHS.FtkX86)" "ERROR"
    exit 1
}

Write-Log "Found FTK at: $FtkExe" "SUCCESS"


# =============================================================================
# STEP 5: Check disk space
# =============================================================================
# FTK creates HUGE files - we need lots of space!

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

if (-not (Test-DiskSpace -Path $OutputFolder -RequiredGB $THRESHOLDS.MinSpaceGB)) {
    Write-Log "Not enough disk space for disk imaging!" "ERROR"
    Write-Log "Disk images can be 100+ GB. Free up space or use a different drive." "ERROR"
    exit 1
}


# =============================================================================
# STEP 6: Build command arguments
# =============================================================================
# FTK Imager command format: ftkimager.exe [source] [dest] [options]

$Arguments = "\\.\C: `"$ImageBase`" $($Config.Tools.FTK.Args)"

Write-Log "FTK arguments: $Arguments"
Write-Log "Output will be: $ImageBase.raw (may be split into multiple files)"


# =============================================================================
# STEP 7: Run FTK with heartbeat monitoring
# =============================================================================

Write-Log "Starting disk imaging (this will take 2-8 hours)..."
Write-Log "=========================================="

$result = Start-ToolWithMonitoring `
    -ExePath $FtkExe `
    -Arguments $Arguments `
    -ToolName "FTK" `
    -TimeoutMs $TIMEOUTS.Ftk

Write-Log "=========================================="

if (-not $result.Success) {
    Write-Log "FTK failed: $($result.Error)" "ERROR"
    # Continue anyway to upload partial results
}


# =============================================================================
# STEP 8: Find and compress disk image files
# =============================================================================
# FTK may create multiple files: .raw, .raw.001, .raw.002, etc.

Write-Log "Compressing disk image files..."

$imageFiles = Get-ChildItem -Path $OutputFolder -Filter "$env:COMPUTERNAME-Disk.*" -ErrorAction SilentlyContinue

if ($imageFiles) {
    try {
        if (Test-Path $ZipFile) {
            Remove-Item $ZipFile -Force
        }
        
        # Compress all disk image segments together
        Compress-Archive -Path $imageFiles.FullName -DestinationPath $ZipFile -Force
        
        $zipSize = [math]::Round((Get-Item $ZipFile).Length / 1GB, 2)
        Write-Log "Created: $ZipFile ($zipSize GB)" "SUCCESS"
    }
    catch {
        Write-Log "Failed to compress: $($_.Exception.Message)" "ERROR"
        exit 1
    }
} else {
    Write-Log "No disk image files found!" "WARNING"
    exit 1
}


# =============================================================================
# STEP 9: Upload to MinIO
# =============================================================================

Write-Log "Uploading to MinIO (this may take a while for large images)..."

$uploaded = Send-ToMinIO -FilePath $ZipFile -Config $Config -ScriptRoot $PSScriptRoot

if ($uploaded) {
    Write-Log "=========================================="
    Write-Log "SUCCESS: Disk image uploaded to MinIO" "SUCCESS"
    Write-Log "=========================================="
    exit 0
} else {
    Write-Log "=========================================="
    Write-Log "Upload failed - evidence saved locally" "WARNING"
    Write-Log "Local file: $ZipFile" "WARNING"
    Write-Log "=========================================="
    exit 1
}

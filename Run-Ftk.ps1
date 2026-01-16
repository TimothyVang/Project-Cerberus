# =============================================================================
# RUN-FTK.PS1 - Creates a full disk image with FTK Imager
# =============================================================================
#
# USAGE: 
#   .\Run-Ftk.ps1                    # Uses path from config
#   .\Run-Ftk.ps1 -OutputPath E:     # Saves to E:\Evidence
#   .\Run-Ftk.ps1 -OutputPath E:\Images  # Saves to E:\Images
#
# WHAT THIS SCRIPT DOES:

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath
)

#
#   1. Load configuration from Cerberus_Config.json
#   2. REQUIRE external drive (Paths.FTK must be configured!)
#   3. Show pre-flight check with source and target drive info
#   4. Run FTK Imager to create a bit-for-bit copy of the C: drive
#   5. Compress the disk image into a .zip file
#   6. Upload the .zip to MinIO server
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
# *** IMPORTANT ***
#   FTK creates disk images that can be 100GB - 2TB in size.
#   You MUST configure Paths.FTK in Cerberus_Config.json to point
#   to an external drive. Saving locally WILL crash your system!
#
# OUTPUT FILE NAMING:
#   HOSTNAME-DOMAIN-FTK.zip (e.g., DESKTOP-PC1-WORKGROUP-FTK.zip)
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
# Try x64 version first, fall back to x86 for older systems

$FtkExe = "$PSScriptRoot\$($PATHS.FtkX64)"
if (-not (Test-Path $FtkExe)) {
    $FtkExe = "$PSScriptRoot\$($PATHS.FtkX86)"
}

# =============================================================================
# STEP 4: Determine output path - command line > config > error
# =============================================================================
# Priority: 1) -OutputPath parameter  2) Config Paths.FTK  3) Error

# Get source drive info for space calculations
$sourceDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$sourceTotalGB = [math]::Round($sourceDrive.Size / 1GB, 2)
$sourceUsedGB = [math]::Round(($sourceDrive.Size - $sourceDrive.FreeSpace) / 1GB, 2)
$sourceFreeGB = [math]::Round($sourceDrive.FreeSpace / 1GB, 2)

# Determine output folder based on priority
if ($OutputPath) {
    # Command-line parameter provided
    # If just a drive letter (e.g., "E:" or "E"), append \Evidence
    if ($OutputPath -match '^[A-Za-z]:?$') {
        $driveLetter = $OutputPath.TrimEnd(':')
        $OutputFolder = "${driveLetter}:\Evidence"
    } else {
        $OutputFolder = $OutputPath
    }
    Write-Log "Using command-line output path: $OutputFolder"
} elseif ($Config.Paths.FTK -and $Config.Paths.FTK -ne "") {
    # Config path provided
    $OutputFolder = $Config.Paths.FTK -replace '\$\{ComputerName\}', $env:COMPUTERNAME
    Write-Log "Using config output path: $OutputFolder"
} else {
    # No path configured - show error
    Write-Host ""
    Write-Host "==========================================="  -ForegroundColor Red
    Write-Host "[ERROR] FTK OUTPUT PATH NOT CONFIGURED" -ForegroundColor Red
    Write-Host "==========================================="  -ForegroundColor Red
    Write-Host ""
    Write-Host "FTK creates disk images that can be 100GB - 2TB in size."
    Write-Host "Saving locally WILL crash your system due to disk exhaustion."
    Write-Host ""
    Write-Host "SOURCE DRIVE (C:)" -ForegroundColor Yellow
    Write-Host "  Total Size:        $sourceTotalGB GB"
    Write-Host "  Used Space:        $sourceUsedGB GB"
    Write-Host "  Free Space:        $sourceFreeGB GB"
    Write-Host ""
    Write-Host "ESTIMATED IMAGE SIZE" -ForegroundColor Yellow
    Write-Host "  Minimum:           $sourceUsedGB GB (used space)"
    Write-Host "  Maximum:           $sourceTotalGB GB (full disk)"
    Write-Host ""
    Write-Host "HOW TO FIX:" -ForegroundColor Cyan
    Write-Host "  Option 1: Pass output path as parameter:"
    Write-Host "    .\Run-Ftk.ps1 -OutputPath E:" -ForegroundColor Gray
    Write-Host "    .\Run-Ftk.ps1 -OutputPath E:\Evidence" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Option 2: Configure in Cerberus_Config.json:"
    Write-Host '     "Paths": {' -ForegroundColor Gray
    Write-Host '         "FTK": "E:\\Cerberus_Evidence"' -ForegroundColor Gray
    Write-Host '     }' -ForegroundColor Gray
    Write-Host ""
    Write-Host "==========================================="  -ForegroundColor Red
    exit 1
}

$ImageBase = "$OutputFolder\$env:COMPUTERNAME-Disk"
$ZipFile = Get-ZipFileName -Tool "FTK" -Directory $OutputFolder


# =============================================================================
# STEP 5: Check FTK exists
# =============================================================================

if (-not (Test-Path $FtkExe)) {
    Write-Log "FTK Imager not found!" "ERROR"
    Write-Log "Checked: $PSScriptRoot\$($PATHS.FtkX64)" "ERROR"
    Write-Log "Checked: $PSScriptRoot\$($PATHS.FtkX86)" "ERROR"
    exit 1
}

Write-Log "Found FTK at: $FtkExe" "SUCCESS"


# =============================================================================
# STEP 6: Check disk space and create output folder
# =============================================================================

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

# Get target drive info
$targetDriveLetter = (Split-Path $OutputFolder -Qualifier)
$targetDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$targetDriveLetter'"
$targetTotalGB = [math]::Round($targetDrive.Size / 1GB, 2)
$targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 2)

$domain = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "WORKGROUP" }

# =============================================================================
# STEP 7: Pre-flight check and user confirmation
# =============================================================================

Write-Host ""
Write-Host "==========================================="
Write-Host "FTK DISK IMAGING - PRE-FLIGHT CHECK"
Write-Host "==========================================="
Write-Host ""
Write-Host "              *** WARNING ***" -ForegroundColor Yellow
Write-Host "  FTK creates a bit-for-bit copy of the ENTIRE disk."
Write-Host "  This REQUIRES an external drive with sufficient space."
Write-Host ""
Write-Host "SOURCE DRIVE (C:)" -ForegroundColor Yellow
Write-Host "  Total Size:        $sourceTotalGB GB"
Write-Host "  Used Space:        $sourceUsedGB GB"
Write-Host "  Free Space:        $sourceFreeGB GB"
Write-Host ""
Write-Host "TARGET DRIVE ($targetDriveLetter)" -ForegroundColor Yellow
Write-Host "  Path:              $OutputFolder"
Write-Host "  Total Size:        $targetTotalGB GB"
Write-Host "  Free Space:        $targetFreeGB GB"
Write-Host ""
Write-Host "WHAT GETS CAPTURED" -ForegroundColor Yellow
Write-Host "  - Complete disk image (every sector)"
Write-Host "  - Deleted files (recoverable)"
Write-Host "  - Unallocated space"
Write-Host "  - File slack space"
Write-Host ""
Write-Host "SPACE CALCULATION" -ForegroundColor Yellow
Write-Host "  Image Size:        $sourceUsedGB - $sourceTotalGB GB"
Write-Host "  Available:         $targetFreeGB GB"

# Check if target has enough space
if ($targetFreeGB -lt $sourceUsedGB) {
    Write-Host ""
    Write-Host "STATUS: " -NoNewline
    Write-Host "FAILED - Not enough space on target drive!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Need at least $sourceUsedGB GB, only $targetFreeGB GB available." -ForegroundColor Red
    Write-Host "Connect a larger external drive and update Paths.FTK in config." -ForegroundColor Red
    Write-Host "==========================================="
    exit 1
} elseif ($targetFreeGB -lt $sourceTotalGB) {
    Write-Host "  Status:            " -NoNewline
    Write-Host "WARNING - May not fit full disk" -ForegroundColor Yellow
} else {
    Write-Host "  Status:            " -NoNewline
    Write-Host "SUFFICIENT" -ForegroundColor Green
}

Write-Host ""
Write-Host "ESTIMATED RUN TIME" -ForegroundColor Yellow
Write-Host "  Duration:          2 - 8 hours"
Write-Host "  Timeout:           72 hours"
Write-Host ""
Write-Host "OUTPUT FILE" -ForegroundColor Yellow
Write-Host "  $(Split-Path $ZipFile -Leaf)"
Write-Host ""
Write-Host "STATUS: " -NoNewline
Write-Host "OK - Ready to image" -ForegroundColor Green
Write-Host "==========================================="
Write-Host ""
Write-Host "Press any key to start FTK imaging, or Ctrl+C to cancel..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""


# =============================================================================
# STEP 8: Build command arguments
# =============================================================================
# FTK Imager command format: ftkimager.exe [source] [dest] [options]

$Arguments = "\\.\C: `"$ImageBase`" $($Config.Tools.FTK.Args)"

Write-Log "FTK arguments: $Arguments"
Write-Log "Output will be: $ImageBase.raw (may be split into multiple files)"


# =============================================================================
# STEP 9: Run FTK with heartbeat monitoring
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
# STEP 10: Find and compress disk image files
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
# STEP 11: Upload to MinIO
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

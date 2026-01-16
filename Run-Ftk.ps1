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
# LOG FILE:
#   Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-FTK_{TIMESTAMP}.log
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
# STEP 2: Initialize log session
# =============================================================================

Initialize-LogSession -Operation "FTK" -ScriptRoot $PSScriptRoot


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
# Try x64 version first, fall back to x86 for older systems

$FtkExe = "$PSScriptRoot\$($PATHS.FtkX64)"
if (-not (Test-Path $FtkExe)) {
    $FtkExe = "$PSScriptRoot\$($PATHS.FtkX86)"
}

# =============================================================================
# STEP 5: Determine output path - command line > config > error
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
    Write-Log "Using command-line output path: $OutputFolder" "INFO" -Category "CONFIG"
} elseif ($Config.Paths.FTK -and $Config.Paths.FTK -ne "") {
    # Config path provided
    $OutputFolder = $Config.Paths.FTK -replace '\$\{ComputerName\}', $env:COMPUTERNAME
    Write-Log "Using config output path: $OutputFolder" "INFO" -Category "CONFIG"
} else {
    # No path configured - show error
    Write-Log "" "INFO"
    Write-Log "===========================================" "ERROR" -Category "CONFIG"
    Write-Log "FTK OUTPUT PATH NOT CONFIGURED" "ERROR" -Category "CONFIG"
    Write-Log "===========================================" "ERROR" -Category "CONFIG"
    Write-Log "" "INFO"
    Write-Log "FTK creates disk images that can be 100GB - 2TB in size." "ERROR" -Category "CONFIG"
    Write-Log "Saving locally WILL crash your system due to disk exhaustion." "ERROR" -Category "CONFIG"
    Write-Log "" "INFO"
    Write-Log "SOURCE DRIVE (C:)" "INFO" -Category "CONFIG"
    Write-Log "  Total Size:        $sourceTotalGB GB" "INFO" -Category "CONFIG"
    Write-Log "  Used Space:        $sourceUsedGB GB" "INFO" -Category "CONFIG"
    Write-Log "  Free Space:        $sourceFreeGB GB" "INFO" -Category "CONFIG"
    Write-Log "" "INFO"
    Write-Log "ESTIMATED IMAGE SIZE" "INFO" -Category "CONFIG"
    Write-Log "  Minimum:           $sourceUsedGB GB (used space)" "INFO" -Category "CONFIG"
    Write-Log "  Maximum:           $sourceTotalGB GB (full disk)" "INFO" -Category "CONFIG"
    Write-Log "" "INFO"
    Write-Log "HOW TO FIX:" "INFO" -Category "CONFIG"
    Write-Log "  Option 1: Pass output path as parameter:" "INFO" -Category "CONFIG"
    Write-Log "    .\Run-Ftk.ps1 -OutputPath E:" "INFO" -Category "CONFIG"
    Write-Log "    .\Run-Ftk.ps1 -OutputPath E:\Evidence" "INFO" -Category "CONFIG"
    Write-Log "" "INFO"
    Write-Log "  Option 2: Configure in Cerberus_Config.json:" "INFO" -Category "CONFIG"
    Write-Log '     "Paths": { "FTK": "E:\\Cerberus_Evidence" }' "INFO" -Category "CONFIG"
    Write-Log "" "INFO"
    Write-Log "===========================================" "ERROR" -Category "CONFIG"
    Complete-LogSession -Status "FAILED"
    exit 1
}

$ImageBase = "$OutputFolder\$env:COMPUTERNAME-Disk"
$ZipFile = Get-ZipFileName -Tool "FTK" -Directory $OutputFolder


# =============================================================================
# STEP 6: Check FTK exists
# =============================================================================

if (-not (Test-Path $FtkExe)) {
    Write-Log "FTK Imager not found!" "ERROR" -Category "TOOL"
    Write-Log "Checked: $PSScriptRoot\$($PATHS.FtkX64)" "ERROR" -Category "TOOL"
    Write-Log "Checked: $PSScriptRoot\$($PATHS.FtkX86)" "ERROR" -Category "TOOL"
    Complete-LogSession -Status "FAILED"
    exit 1
}

Write-Log "Found FTK at: $FtkExe" "SUCCESS" -Category "TOOL"


# =============================================================================
# STEP 7: Check disk space and create output folder
# =============================================================================

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Log "Created output folder: $OutputFolder" "INFO" -Category "CONFIG"
}

# Get target drive info
$targetDriveLetter = (Split-Path $OutputFolder -Qualifier)
$targetDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$targetDriveLetter'"
$targetTotalGB = [math]::Round($targetDrive.Size / 1GB, 2)
$targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 2)

$domain = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "WORKGROUP" }

# =============================================================================
# STEP 8: Pre-flight check and user confirmation
# =============================================================================

Write-Log "" "INFO"
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "FTK DISK IMAGING - PRE-FLIGHT CHECK" "INFO" -Category "PREFLIGHT"
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "              *** WARNING ***" "WARNING" -Category "PREFLIGHT"
Write-Log "  FTK creates a bit-for-bit copy of the ENTIRE disk." "INFO" -Category "PREFLIGHT"
Write-Log "  This REQUIRES an external drive with sufficient space." "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "SOURCE DRIVE (C:)" "INFO" -Category "PREFLIGHT"
Write-Log "  Total Size:        $sourceTotalGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  Used Space:        $sourceUsedGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  Free Space:        $sourceFreeGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "TARGET DRIVE ($targetDriveLetter)" "INFO" -Category "PREFLIGHT"
Write-Log "  Path:              $OutputFolder" "INFO" -Category "PREFLIGHT"
Write-Log "  Total Size:        $targetTotalGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  Free Space:        $targetFreeGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "WHAT GETS CAPTURED" "INFO" -Category "PREFLIGHT"
Write-Log "  - Complete disk image (every sector)" "INFO" -Category "PREFLIGHT"
Write-Log "  - Deleted files (recoverable)" "INFO" -Category "PREFLIGHT"
Write-Log "  - Unallocated space" "INFO" -Category "PREFLIGHT"
Write-Log "  - File slack space" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "SPACE CALCULATION" "INFO" -Category "PREFLIGHT"
Write-Log "  Image Size:        $sourceUsedGB - $sourceTotalGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  Available:         $targetFreeGB GB" "INFO" -Category "PREFLIGHT"

# Check if target has enough space
if ($targetFreeGB -lt $sourceUsedGB) {
    Write-Log "" "INFO"
    Write-Log "STATUS: FAILED - Not enough space on target drive!" "ERROR" -Category "PREFLIGHT"
    Write-Log "" "INFO"
    Write-Log "Need at least $sourceUsedGB GB, only $targetFreeGB GB available." "ERROR" -Category "PREFLIGHT"
    Write-Log "Connect a larger external drive and update Paths.FTK in config." "ERROR" -Category "PREFLIGHT"
    Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
    Complete-LogSession -Status "FAILED"
    exit 1
} elseif ($targetFreeGB -lt $sourceTotalGB) {
    Write-Log "  Status:            WARNING - May not fit full disk" "WARNING" -Category "PREFLIGHT"
} else {
    Write-Log "  Status:            SUFFICIENT" "SUCCESS" -Category "PREFLIGHT"
}

Write-Log "" "INFO"
Write-Log "ESTIMATED RUN TIME" "INFO" -Category "PREFLIGHT"
Write-Log "  Duration:          2 - 8 hours" "INFO" -Category "PREFLIGHT"
Write-Log "  Timeout:           72 hours" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "OUTPUT FILE" "INFO" -Category "PREFLIGHT"
Write-Log "  $(Split-Path $ZipFile -Leaf)" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "STATUS: OK - Ready to image" "SUCCESS" -Category "PREFLIGHT"
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "Press any key to start FTK imaging, or Ctrl+C to cancel..." "INFO" -Category "PREFLIGHT"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Log "" "INFO"


# =============================================================================
# STEP 9: Build command arguments
# =============================================================================
# FTK Imager command format: ftkimager.exe [source] [dest] [options]

$Arguments = "\\.\C: `"$ImageBase`" $($Config.Tools.FTK.Args)"

Write-Log "FTK arguments: $Arguments" "INFO" -Category "TOOL"
Write-Log "Output will be: $ImageBase.raw (may be split into multiple files)" "INFO" -Category "TOOL"


# =============================================================================
# STEP 10: Run FTK with heartbeat monitoring
# =============================================================================

Write-Log "Starting disk imaging (this will take 2-8 hours)..." "INFO" -Category "TOOL"
Write-Log "==========================================" "INFO" -Category "TOOL"

$result = Start-ToolWithMonitoring `
    -ExePath $FtkExe `
    -Arguments $Arguments `
    -ToolName "FTK" `
    -TimeoutMs $TIMEOUTS.Ftk

Write-Log "==========================================" "INFO" -Category "TOOL"

if (-not $result.Success) {
    Write-Log "FTK failed: $($result.Error)" "ERROR" -Category "TOOL"
    # Continue anyway to upload partial results
}


# =============================================================================
# STEP 11: Find and compress disk image files
# =============================================================================
# FTK may create multiple files: .raw, .raw.001, .raw.002, etc.

Write-Log "Compressing disk image files..." "INFO" -Category "COMPRESS"

$imageFiles = Get-ChildItem -Path $OutputFolder -Filter "$env:COMPUTERNAME-Disk.*" -ErrorAction SilentlyContinue

if ($imageFiles) {
    try {
        if (Test-Path $ZipFile) {
            Remove-Item $ZipFile -Force
        }
        
        # Compress all disk image segments together
        Compress-Archive -Path $imageFiles.FullName -DestinationPath $ZipFile -Force
        
        $zipSize = [math]::Round((Get-Item $ZipFile).Length / 1GB, 2)
        Write-Log "Created: $ZipFile ($zipSize GB)" "SUCCESS" -Category "COMPRESS"
    }
    catch {
        Write-Log "Failed to compress: $($_.Exception.Message)" "ERROR" -Category "COMPRESS"
        Complete-LogSession -Status "FAILED"
        exit 1
    }
} else {
    Write-Log "No disk image files found!" "WARNING" -Category "COMPRESS"
    Complete-LogSession -Status "FAILED"
    exit 1
}


# =============================================================================
# STEP 12: Complete FTK log session before upload
# =============================================================================

$zipSizeFormatted = "$zipSize GB"
Complete-LogSession -Status "SUCCESS" -OutputFile $ZipFile -OutputSize $zipSizeFormatted


# =============================================================================
# STEP 13: Upload to MinIO (creates its own log session)
# =============================================================================

Write-Log "Initiating upload to MinIO (this may take a while for large images)..." "INFO" -Category "UPLOAD"

$uploaded = Send-ToMinIO -FilePath $ZipFile -Config $Config -ScriptRoot $PSScriptRoot

if ($uploaded) {
    Write-Log "==========================================" "INFO"
    Write-Log "SUCCESS: Disk image uploaded to MinIO" "SUCCESS"
    Write-Log "==========================================" "INFO"
    exit 0
} else {
    Write-Log "==========================================" "INFO"
    Write-Log "Upload failed - evidence saved locally" "WARNING"
    Write-Log "Local file: $ZipFile" "WARNING"
    Write-Log "==========================================" "INFO"
    exit 1
}

# =============================================================================
# RUN-FTK.PS1 - Creates a full disk image with FTK Imager
# =============================================================================
#
# USAGE:
#   .\Run-Ftk.ps1                    # Uses path from config
#   .\Run-Ftk.ps1 -OutputPath E:     # Saves to E:\Evidence
#   .\Run-Ftk.ps1 -OutputPath E:\Images  # Saves to E:\Images
#
# *** IMPORTANT ***
#   FTK creates disk images that can be 100GB - 2TB in size.
#   You MUST configure Paths.FTK in Cerberus_Config.json to point
#   to an external drive. Saving locally WILL crash your system!
#
# OUTPUT: HOSTNAME-DOMAIN-FTK.zip
# LOG:    Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-FTK_{TIMESTAMP}.log
#
# =============================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath
)


# =============================================================================
# STEP 1: Bootstrap - load libraries, init logging, load config
# =============================================================================

. "$PSScriptRoot\Lib\Cerberus-Bootstrap.ps1"
Import-CerberusLibraries -ScriptRoot $PSScriptRoot

$run = Initialize-CerberusRun -Operation "FTK" -ScriptRoot $PSScriptRoot
$Config = $run.Config
$EvidenceFolder = $run.EvidenceFolder


# =============================================================================
# STEP 2: Setup FTK executable path (x64 with x86 fallback)
# =============================================================================

$FtkExe = "$PSScriptRoot\$($PATHS.FtkX64)"
if (-not (Test-Path $FtkExe)) {
    $FtkExe = "$PSScriptRoot\$($PATHS.FtkX86)"
}


# =============================================================================
# STEP 3: Determine output path - command line > config > error
# =============================================================================

$sourceDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$sourceTotalGB = [math]::Round($sourceDrive.Size / 1GB, 2)
$sourceUsedGB = [math]::Round(($sourceDrive.Size - $sourceDrive.FreeSpace) / 1GB, 2)
$sourceFreeGB = [math]::Round($sourceDrive.FreeSpace / 1GB, 2)

if ($OutputPath) {
    # Command-line parameter provided
    if ($OutputPath -match '^[A-Za-z]:?$') {
        $driveLetter = $OutputPath.TrimEnd(':')
        $OutputFolder = "${driveLetter}:\Evidence"
    } else {
        $OutputFolder = $OutputPath
    }
    Write-Log "Using command-line output path: $OutputFolder" "INFO" -Category "CONFIG"
} elseif ($Config.Paths.FTK -and $Config.Paths.FTK -ne "") {
    $OutputFolder = $Config.Paths.FTK -replace '\$\{ComputerName\}', $env:COMPUTERNAME
    Write-Log "Using config output path: $OutputFolder" "INFO" -Category "CONFIG"
} else {
    # No path configured - show detailed error
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
# STEP 4: Check FTK exists
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
# STEP 5: Check disk space and create output folder
# =============================================================================

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Log "Created output folder: $OutputFolder" "INFO" -Category "CONFIG"
}

$targetDriveLetter = (Split-Path $OutputFolder -Qualifier)
$targetDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$targetDriveLetter'"
$targetTotalGB = [math]::Round($targetDrive.Size / 1GB, 2)
$targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 2)


# =============================================================================
# STEP 6: Pre-flight check and user confirmation
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
if ([Environment]::UserInteractive) {
    Write-Log "Press any key to start FTK imaging, or Ctrl+C to cancel..." "INFO" -Category "PREFLIGHT"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Log "" "INFO"
}


# =============================================================================
# STEP 7: Build arguments and run FTK
# =============================================================================

$Arguments = "\\.\C: `"$ImageBase`" $($Config.Tools.FTK.Args)"

Write-Log "FTK arguments: $Arguments" "INFO" -Category "TOOL"
Write-Log "Output will be: $ImageBase.raw (may be split into multiple files)" "INFO" -Category "TOOL"
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
# STEP 8: Compress disk image files and upload
# =============================================================================
# FTK may create multiple files: .raw, .raw.001, .raw.002, etc.

$imageFiles = Get-ChildItem -Path $OutputFolder -Filter "$env:COMPUTERNAME-Disk.*" -ErrorAction SilentlyContinue

$zipSizeFormatted = Compress-Evidence -SourcePath $OutputFolder -ZipFile $ZipFile `
    -SourceFiles $imageFiles.FullName -SizeUnit "GB"

Complete-CerberusRun -ZipFile $ZipFile -ZipSizeFormatted $zipSizeFormatted -Config $Config -ScriptRoot $PSScriptRoot

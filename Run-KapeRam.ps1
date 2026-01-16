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
# LOG FILE:
#   Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-KAPE-Ram_{TIMESTAMP}.log
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

Initialize-LogSession -Operation "KAPE-Ram" -ScriptRoot $PSScriptRoot


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

$KapeExe = "$PSScriptRoot\$($PATHS.Kape)"
$EvidenceFolder = "$PSScriptRoot\Evidence"
$OutputFolder = "$EvidenceFolder\$env:COMPUTERNAME-KAPE-Mem"
$ZipFile = Get-ZipFileName -Tool "KAPE-Mem" -Directory $EvidenceFolder


# =============================================================================
# STEP 5: Check KAPE exists
# =============================================================================

if (-not (Test-Path $KapeExe)) {
    Write-Log "KAPE not found at: $KapeExe" "ERROR" -Category "TOOL"
    Write-Log "Make sure KAPE is installed in the Bin\KAPE folder" "ERROR" -Category "TOOL"
    Complete-LogSession -Status "FAILED"
    exit 1
}

Write-Log "Found KAPE at: $KapeExe" "SUCCESS" -Category "TOOL"


# =============================================================================
# STEP 6: Check available RAM and disk space
# =============================================================================

$totalRamGB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$requiredGB = [math]::Ceiling($totalRamGB * 1.1)  # RAM + 10% overhead

# Create evidence folder if needed
if (-not (Test-Path $EvidenceFolder)) {
    New-Item -ItemType Directory -Path $EvidenceFolder -Force | Out-Null
}

# =============================================================================
# STEP 7: Pre-flight check and user confirmation
# =============================================================================

# Get system information for pre-flight display
$targetDrive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$((Get-Item $EvidenceFolder).PSDrive.Name):'"
$targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 2)
$targetTotalGB = [math]::Round($targetDrive.Size / 1GB, 2)

$domain = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "WORKGROUP" }
$overheadGB = [math]::Round($totalRamGB * 0.1, 2)
$estimatedZipGB = [math]::Round($totalRamGB * 0.4, 1)  # Memory compresses well (~50-70%)

Write-Log "" "INFO"
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "KAPE MEMORY CAPTURE - PRE-FLIGHT CHECK" "INFO" -Category "PREFLIGHT"
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "SYSTEM MEMORY" "INFO" -Category "PREFLIGHT"
Write-Log "  Installed RAM:     $totalRamGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "WHAT GETS CAPTURED" "INFO" -Category "PREFLIGHT"
Write-Log "  - Full physical memory dump" "INFO" -Category "PREFLIGHT"
Write-Log "  - Running processes" "INFO" -Category "PREFLIGHT"
Write-Log "  - Network connections" "INFO" -Category "PREFLIGHT"
Write-Log "  - Encryption keys (if in memory)" "INFO" -Category "PREFLIGHT"
Write-Log "  - Memory-resident malware" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "OUTPUT LOCATION" "INFO" -Category "PREFLIGHT"
Write-Log "  Path:              $EvidenceFolder" "INFO" -Category "PREFLIGHT"
Write-Log "  Free Space:        $targetFreeGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "SPACE CALCULATION" "INFO" -Category "PREFLIGHT"
Write-Log "  Memory Dump:       $totalRamGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  Overhead (10%):    $overheadGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  --------------------------------" "INFO" -Category "PREFLIGHT"
Write-Log "  Total Required:    $requiredGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "  Available:         $targetFreeGB GB" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "ESTIMATED RUN TIME" "INFO" -Category "PREFLIGHT"
Write-Log "  Duration:          5 - 15 minutes" "INFO" -Category "PREFLIGHT"
Write-Log "  Timeout:           2 hours" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "OUTPUT FILE" "INFO" -Category "PREFLIGHT"
Write-Log "  $(Split-Path $ZipFile -Leaf)" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"

# Check if we have enough space
if ($targetFreeGB -lt $requiredGB) {
    Write-Log "STATUS: FAILED - Not enough disk space!" "ERROR" -Category "PREFLIGHT"
    Write-Log "" "INFO"
    Write-Log "Need $requiredGB GB for RAM dump, only $targetFreeGB GB available." "ERROR" -Category "PREFLIGHT"
    Write-Log "" "INFO"
    Write-Log "HOW TO FIX:" "INFO" -Category "PREFLIGHT"
    Write-Log "  1. Free up at least $([math]::Ceiling($requiredGB - $targetFreeGB)) GB on the drive" "INFO" -Category "PREFLIGHT"
    Write-Log "  2. Or use an external drive by setting Paths.EvidenceRoot in config" "INFO" -Category "PREFLIGHT"
    Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
    Complete-LogSession -Status "FAILED"
    exit 1
} else {
    Write-Log "STATUS: OK - Ready to capture" "SUCCESS" -Category "PREFLIGHT"
}
Write-Log "===========================================" "INFO" -Category "PREFLIGHT"
Write-Log "" "INFO"
Write-Log "Press any key to start memory capture, or Ctrl+C to cancel..." "INFO" -Category "PREFLIGHT"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Log "" "INFO"

# =============================================================================
# STEP 8: Create output folder
# =============================================================================

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Log "Created output folder: $OutputFolder" "INFO" -Category "CONFIG"
}


# =============================================================================
# STEP 9: Build command arguments
# =============================================================================

$Arguments = $Config.Tools.Kape.RamArgs -replace '\$\{Output\}', "`"$OutputFolder`""

Write-Log "KAPE arguments: $Arguments" "INFO" -Category "TOOL"


# =============================================================================
# STEP 10: Run KAPE RAM capture with heartbeat monitoring
# =============================================================================

Write-Log "Starting RAM capture (5-15 minutes)..." "INFO" -Category "TOOL"
Write-Log "==========================================" "INFO" -Category "TOOL"

$result = Start-ToolWithMonitoring `
    -ExePath $KapeExe `
    -Arguments $Arguments `
    -ToolName "KAPE-RAM" `
    -TimeoutMs $TIMEOUTS.KapeRam

Write-Log "==========================================" "INFO" -Category "TOOL"

if (-not $result.Success) {
    Write-Log "RAM capture failed: $($result.Error)" "ERROR" -Category "TOOL"
    Complete-LogSession -Status "FAILED"
    exit 1
}

Write-Log "RAM capture complete!" "SUCCESS" -Category "TOOL"


# =============================================================================
# STEP 11: Compress results
# =============================================================================

Write-Log "Compressing RAM dump (this may take a while)..." "INFO" -Category "COMPRESS"

if (Test-Path $OutputFolder) {
    try {
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
# STEP 12: Complete KAPE-Ram log session before upload
# =============================================================================

$zipSizeFormatted = "$zipSize MB"
Complete-LogSession -Status "SUCCESS" -OutputFile $ZipFile -OutputSize $zipSizeFormatted


# =============================================================================
# STEP 13: Upload to MinIO (creates its own log session)
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

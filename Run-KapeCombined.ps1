# =============================================================================
# RUN-KAPECOMBINED.PS1 - Captures RAM first, then collects disk artifacts
# =============================================================================
#
# USAGE: .\Run-KapeCombined.ps1
#
# WHAT THIS SCRIPT DOES:
#   1. Capture RAM first (preserves memory state before disk activity)
#   2. Collect disk artifacts (Registry, Event Logs, etc.)
#   3. Upload both to MinIO
#
# WHY RAM FIRST?
#   When KAPE collects disk artifacts, it reads files and changes memory.
#   By capturing RAM first, we preserve what was in memory BEFORE our
#   forensic tools modified it. This is forensically correct.
#
# OUTPUT:
#   - HOSTNAME-DOMAIN-KAPE-Mem.zip   (memory dump)
#   - HOSTNAME-DOMAIN-KAPE-Disk.zip  (disk artifacts)
#
# LOG FILE:
#   This script doesn't create its own log - it calls Run-KapeRam.ps1 and 
#   Run-KapeDisk.ps1 which each create their own logs.
#
# =============================================================================


# =============================================================================
# STEP 1: Load shared libraries
# =============================================================================

. "$PSScriptRoot\Lib\Write-Log.ps1"
. "$PSScriptRoot\Lib\Cerberus-Constants.ps1"

# Note: We don't initialize a log session here because this script 
# just orchestrates the other scripts which have their own logs.
# We output to console only for user feedback.

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "KAPE-COMBINED: RAM + Disk Collection" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Order: RAM first (preserves memory state), then Disk" -ForegroundColor Yellow
Write-Host ""
Write-Host "This will create separate logs for each phase:" -ForegroundColor Gray
Write-Host "  - Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-KAPE-Ram_*.log" -ForegroundColor Gray
Write-Host "  - Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-KAPE-Disk_*.log" -ForegroundColor Gray
Write-Host "  - Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-UPLOAD_*.log (for each upload)" -ForegroundColor Gray
Write-Host ""


# =============================================================================
# STEP 2: Capture RAM first
# =============================================================================
# RAM must be captured BEFORE disk collection because:
# - Running KAPE-DISK will load files into memory
# - This changes the memory state we want to capture
# - Capturing RAM first preserves the original memory state

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "PHASE 1: RAM CAPTURE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$ramExitCode = 0
try {
    & "$PSScriptRoot\Run-KapeRam.ps1"
    $ramExitCode = $LASTEXITCODE
}
catch {
    Write-Host "[ERROR] RAM capture failed: $($_.Exception.Message)" -ForegroundColor Red
    $ramExitCode = 1
}

if ($ramExitCode -ne 0) {
    Write-Host "[WARNING] RAM capture had issues (exit code: $ramExitCode)" -ForegroundColor Yellow
    Write-Host "[WARNING] Continuing with disk collection..." -ForegroundColor Yellow
}

Write-Host ""


# =============================================================================
# STEP 3: Collect disk artifacts
# =============================================================================

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "PHASE 2: DISK ARTIFACTS" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$diskExitCode = 0
try {
    & "$PSScriptRoot\Run-KapeDisk.ps1"
    $diskExitCode = $LASTEXITCODE
}
catch {
    Write-Host "[ERROR] Disk collection failed: $($_.Exception.Message)" -ForegroundColor Red
    $diskExitCode = 1
}


# =============================================================================
# STEP 4: Report results
# =============================================================================

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "KAPE-COMBINED COMPLETE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$hostPrefix = "$env:COMPUTERNAME-$(if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { 'WORKGROUP' })"
Write-Host "Check logs in: Logs\$hostPrefix\" -ForegroundColor Gray
Write-Host ""

if ($ramExitCode -eq 0 -and $diskExitCode -eq 0) {
    Write-Host "[SUCCESS] Both RAM and Disk completed successfully" -ForegroundColor Green
    exit 0
} elseif ($ramExitCode -eq 0 -or $diskExitCode -eq 0) {
    Write-Host "[WARNING] Partial success - check logs for details" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "[ERROR] Both RAM and Disk had issues" -ForegroundColor Red
    exit 1
}

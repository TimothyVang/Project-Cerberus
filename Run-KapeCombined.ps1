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
#   - HOSTNAME-RAM.zip      (memory dump)
#   - HOSTNAME-KAPE-Disk.zip (disk artifacts)
#
# =============================================================================


# =============================================================================
# STEP 1: Load shared libraries
# =============================================================================

. "$PSScriptRoot\Lib\Write-Log.ps1"

Write-Log "=========================================="
Write-Log "KAPE-COMBINED: RAM + Disk Collection"
Write-Log "=========================================="
Write-Log ""
Write-Log "Order: RAM first (preserves memory state), then Disk"
Write-Log ""


# =============================================================================
# STEP 2: Capture RAM first
# =============================================================================
# RAM must be captured BEFORE disk collection because:
# - Running KAPE-DISK will load files into memory
# - This changes the memory state we want to capture
# - Capturing RAM first preserves the original memory state

Write-Log "=========================================="
Write-Log "PHASE 1: RAM CAPTURE"
Write-Log "=========================================="

$ramExitCode = 0
try {
    & "$PSScriptRoot\Run-KapeRam.ps1"
    $ramExitCode = $LASTEXITCODE
}
catch {
    Write-Log "RAM capture failed: $($_.Exception.Message)" "ERROR"
    $ramExitCode = 1
}

if ($ramExitCode -ne 0) {
    Write-Log "RAM capture had issues (exit code: $ramExitCode)" "WARNING"
    Write-Log "Continuing with disk collection..." "WARNING"
}

Write-Log ""


# =============================================================================
# STEP 3: Collect disk artifacts
# =============================================================================

Write-Log "=========================================="
Write-Log "PHASE 2: DISK ARTIFACTS"
Write-Log "=========================================="

$diskExitCode = 0
try {
    & "$PSScriptRoot\Run-KapeDisk.ps1"
    $diskExitCode = $LASTEXITCODE
}
catch {
    Write-Log "Disk collection failed: $($_.Exception.Message)" "ERROR"
    $diskExitCode = 1
}


# =============================================================================
# STEP 4: Report results
# =============================================================================

Write-Log ""
Write-Log "=========================================="
Write-Log "KAPE-COMBINED COMPLETE"
Write-Log "=========================================="

if ($ramExitCode -eq 0 -and $diskExitCode -eq 0) {
    Write-Log "Both RAM and Disk completed successfully" "SUCCESS"
    exit 0
} elseif ($ramExitCode -eq 0 -or $diskExitCode -eq 0) {
    Write-Log "Partial success - check logs for details" "WARNING"
    exit 1
} else {
    Write-Log "Both RAM and Disk had issues" "ERROR"
    exit 1
}

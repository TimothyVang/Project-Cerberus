# =============================================================================
# LAUNCH-SCANS.PS1 - Open multiple scans in separate terminal windows
# =============================================================================
#
# USAGE:
#   .\Launch-Scans.ps1 -All              # THOR + KAPE-DISK + FTK
#   .\Launch-Scans.ps1 -Thor -KapeDisk   # Just THOR and KAPE-DISK
#   .\Launch-Scans.ps1 -Thor             # Just THOR
#   .\Launch-Scans.ps1 -KapeDisk         # Just KAPE-DISK
#   .\Launch-Scans.ps1 -KapeRam          # Just KAPE-RAM
#   .\Launch-Scans.ps1 -Ftk              # Just FTK
#
# Each tool opens in its own PowerShell window so you can run multiple
# scans simultaneously and monitor each one.
#
# =============================================================================

param(
    [switch]$Thor,
    [switch]$KapeDisk,
    [switch]$KapeRam,
    [switch]$KapeCombined,
    [switch]$Ftk,
    [switch]$All
)

$ScriptRoot = $PSScriptRoot

# If -All specified, enable THOR + KAPE-DISK + FTK
if ($All) {
    $Thor = $true
    $KapeDisk = $true
    $Ftk = $true
}

# Check if at least one tool was selected
if (-not ($Thor -or $KapeDisk -or $KapeRam -or $KapeCombined -or $Ftk)) {
    Write-Host ""
    Write-Host "LAUNCH-SCANS - Run multiple forensic tools in parallel" -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  .\Launch-Scans.ps1 -All              # THOR + KAPE-DISK + FTK"
    Write-Host "  .\Launch-Scans.ps1 -Thor -KapeDisk   # Just THOR and KAPE-DISK"
    Write-Host "  .\Launch-Scans.ps1 -Thor             # Just THOR"
    Write-Host "  .\Launch-Scans.ps1 -KapeDisk         # Just KAPE-DISK"
    Write-Host "  .\Launch-Scans.ps1 -KapeRam          # Just KAPE-RAM"
    Write-Host "  .\Launch-Scans.ps1 -KapeCombined     # RAM first, then Disk"
    Write-Host "  .\Launch-Scans.ps1 -Ftk              # Just FTK (requires external drive)"
    Write-Host ""
    Write-Host "OPTIONS:" -ForegroundColor Yellow
    Write-Host "  -Thor          Malware/APT scanner"
    Write-Host "  -KapeDisk      Forensic artifacts (Registry, logs, etc.)"
    Write-Host "  -KapeRam       Memory capture"
    Write-Host "  -KapeCombined  RAM first, then Disk (single window)"
    Write-Host "  -Ftk           Full disk image (requires external drive!)"
    Write-Host "  -All           Run THOR + KAPE-DISK + FTK together"
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "Launching scans in separate windows..." -ForegroundColor Cyan
Write-Host ""

if ($Thor) {
    Write-Host "  [+] Starting THOR scan..." -ForegroundColor Green
    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptRoot\Run-Thor.ps1`""
}

if ($KapeDisk) {
    Write-Host "  [+] Starting KAPE Disk collection..." -ForegroundColor Green
    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptRoot\Run-KapeDisk.ps1`""
}

if ($KapeRam) {
    Write-Host "  [+] Starting KAPE RAM capture..." -ForegroundColor Green
    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptRoot\Run-KapeRam.ps1`""
}

if ($KapeCombined) {
    Write-Host "  [+] Starting KAPE Combined (RAM + Disk)..." -ForegroundColor Green
    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptRoot\Run-KapeCombined.ps1`""
}

if ($Ftk) {
    Write-Host "  [+] Starting FTK disk imaging..." -ForegroundColor Green
    Write-Host "      (Requires external drive configured in Cerberus_Config.json)" -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptRoot\Run-Ftk.ps1`""
}

Write-Host ""
Write-Host "All scans launched! Check each window for progress." -ForegroundColor Cyan
Write-Host ""

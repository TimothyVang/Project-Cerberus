# =============================================================================
# CERBERUS LOGGING MODULE
# =============================================================================
# Simple logging function with color-coded output and file persistence
# =============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogDir = "$PSScriptRoot\..\Logs"
    )

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogLine = "[$Time] [$Level] $Message"

    # Color coding for console
    $Color = "Cyan"
    if ($Level -eq "ERROR") { $Color = "Red" }
    if ($Level -eq "SUCCESS") { $Color = "Green" }
    if ($Level -eq "WARNING") { $Color = "Yellow" }

    Write-Host $LogLine -ForegroundColor $Color

    # Write to log file
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $LogFile = "$LogDir\cerberus-$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $LogFile -Value $LogLine
}

# Export function for use in other scripts
Export-ModuleMember -Function Write-Log

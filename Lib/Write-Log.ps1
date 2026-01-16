# =============================================================================
# CERBERUS LOGGING MODULE
# =============================================================================
# Simple logging function with color-coded output and file persistence.
#
# HOW TO USE THIS FILE:
# This file is "dot-sourced" by Cerberus_Agent.ps1, which means the Agent runs:
#     . "$PSScriptRoot\Lib\Write-Log.ps1"
# The dot (.) tells PowerShell to load this file into the current session,
# making the Write-Log function available to use.
#
# WHY NOT A .PSM1 MODULE?
# PowerShell modules (.psm1) require installation or Import-Module commands.
# Dot-sourcing a .ps1 file is simpler and works without any setup - perfect
# for a portable USB toolkit that runs on any machine.
# =============================================================================

function Write-Log {
    <#
    .SYNOPSIS
        Writes a message to console (with colors) and to a log file.
    
    .DESCRIPTION
        This function does TWO things:
        1. Prints a colored message to the console (Red=Error, Green=Success, etc.)
        2. Saves the same message to a daily log file (cerberus-YYYYMMDD.log)
        
        This way, you can see what's happening in real-time AND have a record
        of everything that happened for troubleshooting later.
    
    .PARAMETER Message
        The text you want to log (e.g., "Starting THOR scan...")
    
    .PARAMETER Level
        The severity level. Options: INFO, ERROR, SUCCESS, WARNING
        Default is INFO (cyan color)
    
    .PARAMETER LogDir
        Where to save log files. Default is the Logs folder next to this script.
    
    .EXAMPLE
        Write-Log "Starting scan..."
        # Output: [2026-01-15 10:30:45] [INFO] Starting scan...
    
    .EXAMPLE
        Write-Log "Upload failed!" "ERROR"
        # Output: [2026-01-15 10:30:45] [ERROR] Upload failed!  (in RED)
    #>
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogDir = "$PSScriptRoot\..\Logs"
    )

    # Build the log line with timestamp
    # Example: [2026-01-15 10:30:45] [INFO] Starting THOR scan...
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogLine = "[$Time] [$Level] $Message"

    # Pick a color based on the level
    # This makes it easy to spot errors (red) and successes (green) in the console
    $Color = switch ($Level) {
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default   { "Cyan" }
    }

    # Print to console with color
    Write-Host $LogLine -ForegroundColor $Color

    # Save to log file (create Logs folder if it doesn't exist)
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    
    # Log filename includes today's date, so each day gets its own file
    # Example: cerberus-20260115.log
    $LogFile = "$LogDir\cerberus-$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $LogFile -Value $LogLine
}

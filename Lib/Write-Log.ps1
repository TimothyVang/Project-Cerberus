# =============================================================================
# CERBERUS LOGGING MODULE - Enhanced with Per-Host, Per-Operation Logs
# =============================================================================
#
# HOW TO USE THIS FILE:
# This file is "dot-sourced" by Cerberus scripts:
#     . "$PSScriptRoot\Lib\Write-Log.ps1"
#
# LOGGING STRUCTURE:
#   Logs/
#     {HOSTNAME}-{DOMAIN}/
#       index.txt                                    <- Summary of all operations
#       {HOSTNAME}-{DOMAIN}-{OPERATION}_{TIMESTAMP}.log
#
# EXAMPLE:
#   Logs/
#     DESKTOP-PC1-WORKGROUP/
#       index.txt
#       DESKTOP-PC1-WORKGROUP-THOR_20260116_103045.log
#       DESKTOP-PC1-WORKGROUP-UPLOAD_20260116_110030.log
#
# =============================================================================

# Script-level variables to track current log session
$script:CurrentLogFile = $null
$script:CurrentOperation = $null
$script:SessionStartTime = $null
$script:LogDir = $null
$script:HostPrefix = $null

function Get-HostPrefix {
    <#
    .SYNOPSIS
        Returns the HOSTNAME-DOMAIN prefix used for log folders and files
    #>
    $hostname = $env:COMPUTERNAME
    $domain = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "WORKGROUP" }
    return "$hostname-$domain"
}

function Initialize-LogSession {
    <#
    .SYNOPSIS
        Initializes a new log session for an operation
    
    .DESCRIPTION
        Creates a new log file for the specified operation with format:
        Logs/{HOSTNAME}-{DOMAIN}/{HOSTNAME}-{DOMAIN}-{OPERATION}_{TIMESTAMP}.log
    
    .PARAMETER Operation
        The operation name: THOR, KAPE-Disk, KAPE-Ram, FTK, UPLOAD
    
    .PARAMETER ScriptRoot
        The root folder of the Cerberus scripts (where Logs folder will be created)
    
    .EXAMPLE
        Initialize-LogSession -Operation "THOR" -ScriptRoot $PSScriptRoot
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("THOR", "KAPE-Disk", "KAPE-Ram", "FTK", "UPLOAD", "UPLOAD-ONLY")]
        [string]$Operation,
        
        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )
    
    $script:HostPrefix = Get-HostPrefix
    $script:LogDir = "$ScriptRoot\Logs\$($script:HostPrefix)"
    $script:CurrentOperation = $Operation
    $script:SessionStartTime = Get-Date
    
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:CurrentLogFile = "$($script:LogDir)\$($script:HostPrefix)-${Operation}_${timestamp}.log"
    
    # Ensure directory exists
    if (-not (Test-Path $script:LogDir)) {
        New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    }
    
    # Write session header (hostname/domain from Get-HostPrefix logic)
    $header = @"
================================================================================
CERBERUS LOG - $Operation
================================================================================
Hostname:    $env:COMPUTERNAME
Domain:      $(if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "WORKGROUP" })
Started:     $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Log File:    $($script:CurrentLogFile)
================================================================================

"@
    Add-Content -Path $script:CurrentLogFile -Value $header -Encoding UTF8
    
    return $script:CurrentLogFile
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a message to console (with colors) and to the current log file.
    
    .DESCRIPTION
        This function does TWO things:
        1. Prints a colored message to the console
        2. Saves the same message to the current session's log file
        
        Log format: [TIMESTAMP] [LEVEL] [CATEGORY] Message
    
    .PARAMETER Message
        The text you want to log
    
    .PARAMETER Level
        The severity level: INFO, ERROR, SUCCESS, WARNING, DEBUG, PROGRESS
        Default is INFO
    
    .PARAMETER Category
        Optional category tag: CONFIG, PREFLIGHT, TOOL, NETWORK, UPLOAD, VERIFY, etc.
    
    .PARAMETER NoFile
        If set, only writes to console (useful for progress bars that update frequently)
    
    .PARAMETER NoConsole
        If set, only writes to file (useful for verbose debug logging)
    
    .PARAMETER NoNewLine
        If set, doesn't add newline (useful for progress indicators)
    
    .EXAMPLE
        Write-Log "Starting scan..." "INFO" -Category "TOOL"
        # Output: [2026-01-16 10:30:45] [INFO] [TOOL] Starting scan...
    
    .EXAMPLE
        Write-Log "Upload failed!" "ERROR" -Category "UPLOAD"
        # Output: [2026-01-16 10:30:45] [ERROR] [UPLOAD] Upload failed!
    #>
    param(
        [Parameter(Position=0)]
        [string]$Message,
        
        [Parameter(Position=1)]
        [ValidateSet("INFO", "ERROR", "SUCCESS", "WARNING", "DEBUG", "PROGRESS")]
        [string]$Level = "INFO",
        
        [string]$Category = "",
        
        [switch]$NoFile,
        
        [switch]$NoConsole,
        
        [switch]$NoNewLine
    )

    # Build the log line with timestamp
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $CategoryTag = if ($Category) { "[$Category] " } else { "" }
    $LogLine = "[$Time] [$Level] $CategoryTag$Message"

    # Pick a color based on the level
    $Color = switch ($Level) {
        "ERROR"    { "Red" }
        "SUCCESS"  { "Green" }
        "WARNING"  { "Yellow" }
        "PROGRESS" { "Cyan" }
        "DEBUG"    { "Gray" }
        default    { "White" }
    }

    # Print to console with color
    if (-not $NoConsole) {
        if ($NoNewLine) {
            Write-Host $LogLine -ForegroundColor $Color -NoNewline
        } else {
            Write-Host $LogLine -ForegroundColor $Color
        }
    }

    # Save to log file
    if (-not $NoFile -and $script:CurrentLogFile) {
        Add-Content -Path $script:CurrentLogFile -Value $LogLine -Encoding UTF8
    }
}

function Complete-LogSession {
    <#
    .SYNOPSIS
        Completes the current log session, writes summary, and updates index
    
    .PARAMETER Status
        Final status: SUCCESS, FAILED, PARTIAL, CANCELLED
    
    .PARAMETER OutputFile
        Optional path to the output file created (for display in summary)
    
    .PARAMETER OutputSize
        Optional size string of the output (e.g., "125 MB")
    
    .PARAMETER AdditionalInfo
        Optional hashtable of additional info to include in summary
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("SUCCESS", "FAILED", "PARTIAL", "CANCELLED")]
        [string]$Status,
        
        [string]$OutputFile = "",
        
        [string]$OutputSize = "",
        
        [hashtable]$AdditionalInfo = @{}
    )
    
    if (-not $script:CurrentLogFile -or -not $script:SessionStartTime) {
        return
    }
    
    $endTime = Get-Date
    $duration = $endTime - $script:SessionStartTime
    $durationStr = "{0:hh\:mm\:ss}" -f $duration
    
    # Build summary
    $summary = @"

================================================================================
SESSION COMPLETE
================================================================================
Duration:    $durationStr
Status:      $Status
"@

    if ($OutputFile) {
        $summary += "`nOutput:      $(Split-Path $OutputFile -Leaf)"
    }
    if ($OutputSize) {
        $summary += "`nSize:        $OutputSize"
    }
    
    foreach ($key in $AdditionalInfo.Keys) {
        $summary += "`n$($key):".PadRight(13) + $AdditionalInfo[$key]
    }
    
    $summary += "`n================================================================================"
    
    # Write to log file
    Add-Content -Path $script:CurrentLogFile -Value $summary -Encoding UTF8
    
    # Update index
    Update-LogIndex -Status $Status
    
    # Reset session variables
    $script:CurrentLogFile = $null
    $script:CurrentOperation = $null
    $script:SessionStartTime = $null
}

function Update-LogIndex {
    <#
    .SYNOPSIS
        Updates the index.txt file with the current operation entry
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Status
    )
    
    if (-not $script:LogDir -or -not $script:CurrentOperation -or -not $script:CurrentLogFile) {
        return
    }
    
    $indexFile = "$($script:LogDir)\index.txt"
    $logFileName = Split-Path $script:CurrentLogFile -Leaf
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Create index header if file doesn't exist
    if (-not (Test-Path $indexFile)) {
        $header = @"
================================================================================
CERBERUS OPERATION INDEX - $($script:HostPrefix)
================================================================================
TIMESTAMP              OPERATION      LOG FILE                                      STATUS
--------------------------------------------------------------------------------
"@
        Add-Content -Path $indexFile -Value $header -Encoding UTF8
    }
    
    # Add entry
    $entry = "{0}  {1,-14} {2,-45} {3}" -f $timestamp, $script:CurrentOperation, $logFileName, $Status
    Add-Content -Path $indexFile -Value $entry -Encoding UTF8
}


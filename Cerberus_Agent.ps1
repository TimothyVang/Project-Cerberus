# =============================================================================
# CERBERUS_AGENT.PS1 - Backward Compatible Wrapper
# =============================================================================
#
# WHAT IS THIS FILE?
# This is a "wrapper" script that maintains backward compatibility with
# existing Elastic Defend commands. It simply calls the appropriate
# Run-*.ps1 script based on the -Tool parameter.
#
# WHY DOES THIS EXIST?
# Existing Kibana response commands use:
#   powershell.exe -File "Cerberus_Agent.ps1" -Tool THOR
#
# Instead of updating all those commands, this wrapper redirects to the
# new simpler scripts (Run-Thor.ps1, Run-KapeDisk.ps1, etc.)
#
# NEW WAY (recommended for new deployments):
#   .\Run-Thor.ps1
#   .\Run-KapeDisk.ps1
#   .\Run-KapeRam.ps1
#   .\Run-Ftk.ps1
#   .\Run-UploadOnly.ps1
#
# OLD WAY (still works via this wrapper):
#   .\Cerberus_Agent.ps1 -Tool THOR
#   .\Cerberus_Agent.ps1 -Tool KAPE-DISK
#   .\Cerberus_Agent.ps1 -Tool KAPE-RAM
#   .\Cerberus_Agent.ps1 -Tool FTK
#   .\Cerberus_Agent.ps1 -UploadOnly
#
# =============================================================================

# Accept the same parameters as before for backward compatibility
param(
    [string]$Tool = "THOR",
    [switch]$UploadOnly
)

# Get the folder where this script is located
$ScriptRoot = $PSScriptRoot

# Load Write-Log so we can print nice messages
. "$ScriptRoot\Lib\Write-Log.ps1"

Write-Log "Cerberus Agent Wrapper v2.4"
Write-Log "=========================================="

# If -UploadOnly was passed, run the upload script
if ($UploadOnly) {
    Write-Log "Mode: Upload Only"
    Write-Log "Calling: Run-UploadOnly.ps1"
    Write-Log "=========================================="
    
    & "$ScriptRoot\Run-UploadOnly.ps1"
    exit $LASTEXITCODE
}

# Otherwise, run the appropriate tool script
Write-Log "Tool: $Tool"

switch ($Tool) {
    "THOR" {
        Write-Log "Calling: Run-Thor.ps1"
        Write-Log "=========================================="
        & "$ScriptRoot\Run-Thor.ps1"
    }
    "KAPE-DISK" {
        Write-Log "Calling: Run-KapeDisk.ps1"
        Write-Log "=========================================="
        & "$ScriptRoot\Run-KapeDisk.ps1"
    }
    "KAPE-RAM" {
        Write-Log "Calling: Run-KapeRam.ps1"
        Write-Log "=========================================="
        & "$ScriptRoot\Run-KapeRam.ps1"
    }
    "FTK" {
        Write-Log "Calling: Run-Ftk.ps1"
        Write-Log "=========================================="
        & "$ScriptRoot\Run-Ftk.ps1"
    }
    default {
        Write-Log "Unknown tool: $Tool" "ERROR"
        Write-Log ""
        Write-Log "Available tools:" "WARNING"
        Write-Log "  THOR      - Malware scanner"
        Write-Log "  KAPE-DISK - Forensic artifact collector"
        Write-Log "  KAPE-RAM  - Memory capture"
        Write-Log "  FTK       - Full disk imaging"
        Write-Log ""
        Write-Log "Or use -UploadOnly to upload existing evidence"
        exit 1
    }
}

# Pass through the exit code from the tool script
exit $LASTEXITCODE

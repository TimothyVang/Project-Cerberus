# =============================================================================
# CERBERUS.PS1 - Main Entry Point for Remote Forensic Collection
# =============================================================================
#
# USAGE:
#   .\Cerberus.ps1 THOR
#   .\Cerberus.ps1 KAPE-DISK
#   .\Cerberus.ps1 KAPE-RAM
#   .\Cerberus.ps1 KAPE-COMBINED
#   .\Cerberus.ps1 FTK
#   .\Cerberus.ps1 FTK E:\Images
#   .\Cerberus.ps1 UPLOAD
#
# TOOLS:
#   THOR          - Malware/APT scanner
#   KAPE-DISK     - Collect forensic artifacts (Registry, logs, etc.)
#   KAPE-RAM      - Capture system memory
#   KAPE-COMBINED - RAM first, then Disk (forensically correct order)
#   FTK           - Full disk image
#   UPLOAD        - Upload existing evidence to MinIO
#
# =============================================================================

param(
    # The forensic tool to run (tab-complete works!)
    [Parameter(Position = 0)]
    [ValidateSet("THOR","KAPE-DISK","KAPE-RAM","KAPE-COMBINED","FTK","UPLOAD",
                 "thor","kape-disk","kape-ram","kape-combined","ftk","upload")]
    [string]$Tool,

    # Optional: For FTK, specify output path (e.g., E:\Images)
    [Parameter(Position = 1)]
    [string]$Option
)

# Load shared libraries for logging and constants
. "$PSScriptRoot\Lib\Write-Log.ps1"
. "$PSScriptRoot\Lib\Cerberus-Constants.ps1"

# Show help if no tool specified
function Show-Help {
    Write-Host ""
    Write-Host "CERBERUS - Forensic Collection Toolkit" -ForegroundColor Cyan
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  .\Cerberus.ps1 <TOOL> [OPTIONS]"
    Write-Host ""
    Write-Host "TOOLS:" -ForegroundColor Yellow
    Write-Host "  THOR          Malware scan"
    Write-Host "  KAPE-DISK     Forensic artifacts"
    Write-Host "  KAPE-RAM      Memory capture"
    Write-Host "  KAPE-COMBINED RAM + Disk (RAM first)"
    Write-Host "  FTK           Full disk image"
    Write-Host "  UPLOAD        Upload existing evidence"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  .\Cerberus.ps1 THOR"
    Write-Host "  .\Cerberus.ps1 KAPE-COMBINED"
    Write-Host "  .\Cerberus.ps1 FTK E:\Images"
    Write-Host ""
}

# If no tool specified, show help
if (-not $Tool) {
    Show-Help
    exit 0
}

# Normalize to uppercase so the switch block below can use simple string matches.
# ValidateSet already restricts to valid values, but users may type "thor" or "Thor".
$Tool = $Tool.ToUpper()

Write-Log "=========================================="
Write-Log "CERBERUS $CERBERUS_VERSION"
Write-Log "Tool: $Tool"
Write-Log "=========================================="

# Dispatch table: tool name -> script and description
$ScriptMap = @{
    "THOR"          = @{ Script = "Run-Thor.ps1";         Desc = "THOR malware scan" }
    "KAPE-DISK"     = @{ Script = "Run-KapeDisk.ps1";     Desc = "KAPE disk artifact collection" }
    "KAPE-RAM"      = @{ Script = "Run-KapeRam.ps1";      Desc = "KAPE RAM capture" }
    "KAPE-COMBINED" = @{ Script = "Run-KapeCombined.ps1";  Desc = "KAPE combined (RAM first, then Disk)" }
    "FTK"           = @{ Script = "Run-Ftk.ps1";          Desc = "FTK disk imaging" }
    "UPLOAD"        = @{ Script = "Run-UploadOnly.ps1";    Desc = "evidence upload" }
}

$entry = $ScriptMap[$Tool]

if (-not $entry) {
    Write-Log "Unknown tool: $Tool" "ERROR"
    Write-Host ""
    Show-Help
    exit 1
}

Write-Log "Starting $($entry.Desc)..."

# FTK accepts an optional -OutputPath parameter
if ($Tool -eq "FTK" -and $Option) {
    Write-Log "Output path: $Option"
    & "$PSScriptRoot\$($entry.Script)" -OutputPath $Option
} else {
    & "$PSScriptRoot\$($entry.Script)"
}

exit $LASTEXITCODE

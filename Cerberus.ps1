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

# Get the tool name from first argument
$Tool = $args[0]

# Get optional second argument (used for FTK output path)
$Option = $args[1]

# Load Write-Log for nice output
. "$PSScriptRoot\Lib\Write-Log.ps1"

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

# Convert to uppercase for case-insensitive matching
$Tool = $Tool.ToUpper()

Write-Log "=========================================="
Write-Log "CERBERUS v2.4"
Write-Log "Tool: $Tool"
Write-Log "=========================================="

# Run the appropriate script based on tool name
switch ($Tool) {
    "THOR" {
        Write-Log "Starting THOR malware scan..."
        & "$PSScriptRoot\Run-Thor.ps1"
        exit $LASTEXITCODE
    }
    "KAPE-DISK" {
        Write-Log "Starting KAPE disk artifact collection..."
        & "$PSScriptRoot\Run-KapeDisk.ps1"
        exit $LASTEXITCODE
    }
    "KAPE-RAM" {
        Write-Log "Starting KAPE RAM capture..."
        & "$PSScriptRoot\Run-KapeRam.ps1"
        exit $LASTEXITCODE
    }
    "KAPE-COMBINED" {
        Write-Log "Starting KAPE combined (RAM first, then Disk)..."
        & "$PSScriptRoot\Run-KapeCombined.ps1"
        exit $LASTEXITCODE
    }
    "FTK" {
        if ($Option) {
            Write-Log "Starting FTK disk imaging to: $Option"
            & "$PSScriptRoot\Run-Ftk.ps1" -OutputPath $Option
        } else {
            Write-Log "Starting FTK disk imaging..."
            & "$PSScriptRoot\Run-Ftk.ps1"
        }
        exit $LASTEXITCODE
    }
    "UPLOAD" {
        Write-Log "Starting evidence upload..."
        & "$PSScriptRoot\Run-UploadOnly.ps1"
        exit $LASTEXITCODE
    }
    default {
        Write-Log "Unknown tool: $Tool" "ERROR"
        Write-Host ""
        Show-Help
        exit 1
    }
}

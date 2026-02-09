# =============================================================================
# DEPLOY-CERBERUS.PS1 - Target-side bootstrap for Elastic Defend deployment
# =============================================================================
#
# USAGE:
#   .\Deploy-Cerberus.ps1                          # Extract only
#   .\Deploy-Cerberus.ps1 -Run THOR                # Extract + run THOR
#   .\Deploy-Cerberus.ps1 -Run KAPE-DISK           # Extract + run KAPE-DISK
#   .\Deploy-Cerberus.ps1 -InstallPath D:\Cerberus # Custom install location
#
# This script is included in every Cerberus deployment package. It:
#   1. Finds all Part*.zip files (checks script dir, then Elastic response path)
#   2. Extracts them into InstallPath (default: C:\ProgramData\Google\Cerberus)
#   3. Optionally runs Cerberus.ps1 with the specified tool
#
# REQUIREMENTS: PowerShell 4.0+ (uses .NET ZipFile if Expand-Archive unavailable)
#
# =============================================================================

param(
    # Tool to run after extraction (optional)
    [Parameter(Position = 0)]
    [ValidateSet("THOR","KAPE-DISK","KAPE-RAM","KAPE-COMBINED","FTK","UPLOAD",
                 "thor","kape-disk","kape-ram","kape-combined","ftk","upload")]
    [string]$Run,

    # Where to install Cerberus (created if it doesn't exist)
    [string]$InstallPath = "C:\ProgramData\Google\Cerberus",

    # Where to find Part*.zip files (default: auto-detect)
    [string]$SourcePath
)


# =============================================================================
# STEP 1: Find Part*.zip files
# =============================================================================
# Auto-detect source: check explicit path, then script dir, then the Elastic
# Defend response actions folder where uploaded files land.

$ElasticResponsePath = "C:\Program Files\Elastic\Endpoint\state\response_actions"

Write-Host ""
Write-Host "=========================================="
Write-Host "CERBERUS - Deploy"
Write-Host "=========================================="
Write-Host ""

if (-not $SourcePath) {
    # Auto-detect: try PSScriptRoot first, then Elastic response path
    $candidates = @($PSScriptRoot, $ElasticResponsePath)
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            $found = Get-ChildItem -Path $candidate -Filter "Part*.zip" -ErrorAction SilentlyContinue
            if ($found.Count -gt 0) {
                $SourcePath = $candidate
                break
            }
        }
    }
    if (-not $SourcePath) { $SourcePath = $PSScriptRoot }
}

$zipFiles = Get-ChildItem -Path $SourcePath -Filter "Part*.zip" -ErrorAction SilentlyContinue |
    Sort-Object Name

if ($zipFiles.Count -eq 0) {
    Write-Host "[ERROR] No Part*.zip files found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Searched:"
    Write-Host "  $PSScriptRoot"
    Write-Host "  $ElasticResponsePath"
    Write-Host ""
    Write-Host "Use -SourcePath to point to the folder containing Part*.zip files."
    exit 1
}

Write-Host "Found $($zipFiles.Count) package(s) in: $SourcePath"
foreach ($zip in $zipFiles) {
    $sizeMB = [math]::Round($zip.Length / 1MB, 1)
    Write-Host "  $($zip.Name) ($sizeMB MB)"
}
Write-Host ""


# =============================================================================
# STEP 2: Create install directory
# =============================================================================

if (-not (Test-Path $InstallPath)) {
    try {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        Write-Host "Created install directory: $InstallPath"
    } catch {
        Write-Host "[ERROR] Failed to create directory: $InstallPath" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "Install directory exists: $InstallPath"
}
Write-Host ""


# =============================================================================
# STEP 3: Extract all Part*.zip files
# =============================================================================
# Uses Expand-Archive (PS 5.0+) with .NET ZipFile fallback (PS 4.0+)

Write-Host "Extracting packages..."
Write-Host ""

# Load .NET ZipFile once - needed for PS 4.0 fallback and always used for
# availability check
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

$useExpandArchive = Get-Command Expand-Archive -ErrorAction SilentlyContinue

foreach ($zip in $zipFiles) {
    Write-Host "  Extracting: $($zip.Name)..." -NoNewline

    try {
        if ($useExpandArchive) {
            Expand-Archive -Path $zip.FullName -DestinationPath $InstallPath -Force
        } else {
            # PS 4.0 fallback: use .NET ZipFile directly
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zip.FullName, $InstallPath)
        }
        Write-Host " OK" -ForegroundColor Green
    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""


# =============================================================================
# STEP 4: Verify extraction
# =============================================================================

$cerberusScript = Join-Path $InstallPath "Cerberus.ps1"

if (-not (Test-Path $cerberusScript)) {
    Write-Host "[ERROR] Extraction incomplete - Cerberus.ps1 not found at:" -ForegroundColor Red
    Write-Host "  $cerberusScript" -ForegroundColor Red
    Write-Host ""
    Write-Host "Check that Part1_Core.zip contains the Cerberus scripts."
    exit 1
}

Write-Host "Extraction complete. Cerberus installed to:" -ForegroundColor Green
Write-Host "  $InstallPath"
Write-Host ""


# =============================================================================
# STEP 5: Run tool (if requested)
# =============================================================================

if ($Run) {
    Write-Host "=========================================="
    Write-Host "Starting: $Run"
    Write-Host "=========================================="
    Write-Host ""

    & $cerberusScript $Run
    exit $LASTEXITCODE
} else {
    Write-Host "Extraction only (no -Run specified)."
    Write-Host "To run a tool manually:"
    Write-Host "  cd $InstallPath"
    Write-Host "  .\Cerberus.ps1 THOR"
    Write-Host ""
}

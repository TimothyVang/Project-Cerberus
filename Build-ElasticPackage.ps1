# =============================================================================
# BUILD-ELASTICPACKAGE.PS1 - Build deployment packages for Elastic Defend
# =============================================================================
#
# USAGE:
#   .\Build-ElasticPackage.ps1
#
# Reads Cerberus_Config.json and builds ready-to-upload packages for each tool.
# Run this AFTER editing Cerberus_Config.json with your MinIO credentials.
#
# OUTPUT:
#   Splits/
#   ├── THOR/     (Part1_Core + Part2_THOR_Exe + Part3_THOR_Sigs + commands)
#   ├── KAPE/     (Part1_Core + Part2_KAPE + commands)
#   ├── FTK/      (Part1_Core + Part2_FTK + commands)
#   └── ALL/      (Part1_Core + all tool parts + commands)
#
# Each folder is self-contained. Upload the zips from the folder you need,
# then run Deploy-Cerberus.ps1 on the target host.
#
# =============================================================================

$ErrorActionPreference = "Stop"

# =============================================================================
# STEP 1: Validate prerequisites
# =============================================================================

Write-Host ""
Write-Host "=========================================="
Write-Host "CERBERUS - Build Elastic Packages"
Write-Host "=========================================="
Write-Host ""

# Validate config exists
$configPath = "$PSScriptRoot\Cerberus_Config.json"
if (-not (Test-Path $configPath)) {
    Write-Host "[ERROR] Cerberus_Config.json not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Copy the template and fill in your MinIO credentials:"
    Write-Host "  copy Cerberus_Config.json.template Cerberus_Config.json"
    Write-Host "  notepad Cerberus_Config.json"
    exit 1
}

# Quick check that config has real values (not template placeholders)
$configRaw = Get-Content $configPath -Raw
if ($configRaw -match "YOUR_MINIO_SERVER" -or $configRaw -match "YOUR_ACCESS_KEY" -or $configRaw -match "YOUR_SECRET_KEY") {
    Write-Host "[ERROR] Cerberus_Config.json still has placeholder values!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Edit the config and replace:"
    Write-Host "  YOUR_MINIO_SERVER:PORT  ->  your actual MinIO server"
    Write-Host "  YOUR_ACCESS_KEY         ->  your actual access key"
    Write-Host "  YOUR_SECRET_KEY         ->  your actual secret key"
    exit 1
}

Write-Host "Config validated: $configPath" -ForegroundColor Green

# Validate Deploy-Cerberus.ps1 exists
$deployScript = "$PSScriptRoot\Deploy-Cerberus.ps1"
if (-not (Test-Path $deployScript)) {
    Write-Host "[ERROR] Deploy-Cerberus.ps1 not found!" -ForegroundColor Red
    Write-Host "  This file should be in the Cerberus root folder."
    exit 1
}


# =============================================================================
# STEP 2: Define package contents
# =============================================================================
# Each package is a list of zip parts. Part1_Core is shared across all packages.
#
# IMPORTANT: Elastic Defend file upload limit varies but is often around 25 MB.
# THOR signatures are the largest component, so they get their own zip.

# --- Core files (shared by every package) ---
# Includes: all .ps1 scripts, Lib/, config, and MinIO client
$coreFiles = @(
    "Cerberus.ps1"
    "Deploy-Cerberus.ps1"
    "Launch-Scans.ps1"
    "Run-Thor.ps1"
    "Run-KapeDisk.ps1"
    "Run-KapeRam.ps1"
    "Run-KapeCombined.ps1"
    "Run-Ftk.ps1"
    "Run-UploadOnly.ps1"
    "Cerberus_Config.json"
    "Lib"
    "Bin\MinIO"
)

# --- Tool-specific paths ---
$thorExePaths = @(
    "Bin\THOR\thor64-lite.exe"
    "Bin\THOR\thor64-lite.exe.sig"
    "Bin\THOR\config"
    "Bin\THOR\custom-signatures"
    "Bin\THOR\tools"
    "Bin\THOR\docs"
)

# Glob for .lic files in THOR root (license filenames vary)
$thorLicFiles = Get-ChildItem -Path "$PSScriptRoot\Bin\THOR" -Filter "*.lic" -ErrorAction SilentlyContinue

$thorSigPaths = @(
    "Bin\THOR\signatures"
)

$kapePaths = @(
    "Bin\KAPE"
)

$ftkPaths = @(
    "Bin\FTK"
)


# =============================================================================
# STEP 3: Helper function to create a zip from a list of relative paths
# =============================================================================

function New-PackageZip {
    param(
        [string]$ZipPath,
        [string[]]$RelativePaths,
        [System.IO.FileInfo[]]$ExtraFiles
    )

    # Remove existing zip if present
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

    # Create a temp staging folder, copy files preserving structure, then zip
    $staging = Join-Path $env:TEMP "CerberusBuild_$(Get-Random)"
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    try {
        foreach ($relPath in $RelativePaths) {
            $source = Join-Path $PSScriptRoot $relPath
            if (-not (Test-Path $source)) {
                Write-Host "    [WARN] Missing: $relPath" -ForegroundColor Yellow
                continue
            }

            $dest = Join-Path $staging $relPath
            $destParent = Split-Path $dest -Parent
            if (-not (Test-Path $destParent)) {
                New-Item -ItemType Directory -Path $destParent -Force | Out-Null
            }

            if ((Get-Item $source).PSIsContainer) {
                Copy-Item -Path $source -Destination $dest -Recurse -Force
            } else {
                Copy-Item -Path $source -Destination $dest -Force
            }
        }

        # Copy any extra files (e.g., THOR .lic files) preserving their relative position
        foreach ($file in $ExtraFiles) {
            $relPath = $file.FullName.Substring($PSScriptRoot.Length + 1)
            $dest = Join-Path $staging $relPath
            $destParent = Split-Path $dest -Parent
            if (-not (Test-Path $destParent)) {
                New-Item -ItemType Directory -Path $destParent -Force | Out-Null
            }
            Copy-Item -Path $file.FullName -Destination $dest -Force
        }

        # Compress
        Compress-Archive -Path "$staging\*" -DestinationPath $ZipPath -Force

        $sizeMB = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
        Write-Host "    $([System.IO.Path]::GetFileName($ZipPath)) ($sizeMB MB)" -ForegroundColor Cyan
    } finally {
        Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# =============================================================================
# STEP 4: Helper function to generate Deploy-Commands.txt
# =============================================================================

function New-DeployCommands {
    param(
        [string]$OutputPath,
        [string]$PackageName,
        [string[]]$PartNames,
        [string]$Tool
    )

    $date = Get-Date -Format "yyyy-MM-dd"
    $partCount = $PartNames.Count
    $partList = ($PartNames | ForEach-Object { "  $_" }) -join "`r`n"

    # Build the execute command
    # Step 1: Extract Part1_Core.zip to get Deploy-Cerberus.ps1 onto disk
    # Step 2: Run Deploy-Cerberus.ps1 which extracts remaining Part*.zips and runs the tool
    # Deploy-Cerberus.ps1 auto-detects the Elastic response_actions path for remaining zips
    $elasticPath = "C:\Program Files\Elastic\Endpoint\state\response_actions"
    $installPath = "C:\ProgramData\Google\Cerberus"
    $deployCmdPath = "$installPath\Deploy-Cerberus.ps1"
    # Use single quotes for paths inside the double-quoted execute command (matches SOP pattern)
    $bootstrap = "Expand-Archive -Force -Path '$elasticPath\Part1_Core.zip' -DestinationPath '$installPath'"
    if ($Tool) {
        $executeCmd = "execute --command `"powershell.exe -ExecutionPolicy Bypass -Command $bootstrap; & '$deployCmdPath' -Run $Tool`" --timeout 86400s"
    } else {
        $executeCmd = "execute --command `"powershell.exe -ExecutionPolicy Bypass -Command $bootstrap; & '$deployCmdPath'`" --timeout 86400s"
    }

    $content = @"
================================================================
CERBERUS - $PackageName Package
Parts: $partCount | Generated: $date
================================================================

STEP 1: Upload via Kibana Response Actions:
$partList

STEP 2: Deploy + Run (copy-paste into Response Console):
  $executeCmd
================================================================
"@

    $content | Out-File -FilePath $OutputPath -Encoding UTF8
}


# =============================================================================
# STEP 5: Create output directory structure
# =============================================================================

$splitsRoot = "$PSScriptRoot\Splits"

# Clean previous build
if (Test-Path $splitsRoot) {
    Remove-Item -Path $splitsRoot -Recurse -Force
    Write-Host "Cleaned previous build." -ForegroundColor DarkGray
}

$thorDir = "$splitsRoot\THOR"
$kapeDir = "$splitsRoot\KAPE"
$ftkDir  = "$splitsRoot\FTK"
$allDir  = "$splitsRoot\ALL"

New-Item -ItemType Directory -Path $thorDir -Force | Out-Null
New-Item -ItemType Directory -Path $kapeDir -Force | Out-Null
New-Item -ItemType Directory -Path $ftkDir  -Force | Out-Null
New-Item -ItemType Directory -Path $allDir  -Force | Out-Null

Write-Host ""


# =============================================================================
# STEP 6: Build Part1_Core.zip (shared across all packages)
# =============================================================================

Write-Host "Building Core package..."
$corePath = "$splitsRoot\Part1_Core.zip"
New-PackageZip -ZipPath $corePath -RelativePaths $coreFiles


# =============================================================================
# STEP 7: Build THOR packages
# =============================================================================

Write-Host ""
Write-Host "Building THOR packages..."

$thorExeZip = "$splitsRoot\Part2_THOR_Exe.zip"
New-PackageZip -ZipPath $thorExeZip -RelativePaths $thorExePaths -ExtraFiles $thorLicFiles

$thorSigZip = "$splitsRoot\Part3_THOR_Sigs.zip"
New-PackageZip -ZipPath $thorSigZip -RelativePaths $thorSigPaths

# Copy to THOR folder
Copy-Item $corePath    "$thorDir\Part1_Core.zip"
Copy-Item $thorExeZip  "$thorDir\Part2_THOR_Exe.zip"
Copy-Item $thorSigZip  "$thorDir\Part3_THOR_Sigs.zip"

New-DeployCommands -OutputPath "$thorDir\Deploy-Commands.txt" `
    -PackageName "THOR" `
    -PartNames @("Part1_Core.zip", "Part2_THOR_Exe.zip", "Part3_THOR_Sigs.zip") `
    -Tool "THOR"


# =============================================================================
# STEP 8: Build KAPE package
# =============================================================================

Write-Host ""
Write-Host "Building KAPE package..."

$kapeZip = "$splitsRoot\Part2_KAPE.zip"
New-PackageZip -ZipPath $kapeZip -RelativePaths $kapePaths

# Copy to KAPE folder
Copy-Item $corePath "$kapeDir\Part1_Core.zip"
Copy-Item $kapeZip  "$kapeDir\Part2_KAPE.zip"

New-DeployCommands -OutputPath "$kapeDir\Deploy-Commands.txt" `
    -PackageName "KAPE" `
    -PartNames @("Part1_Core.zip", "Part2_KAPE.zip") `
    -Tool "KAPE-DISK"


# =============================================================================
# STEP 9: Build FTK package
# =============================================================================

Write-Host ""
Write-Host "Building FTK package..."

$ftkZip = "$splitsRoot\Part2_FTK.zip"
New-PackageZip -ZipPath $ftkZip -RelativePaths $ftkPaths

# Copy to FTK folder
Copy-Item $corePath "$ftkDir\Part1_Core.zip"
Copy-Item $ftkZip   "$ftkDir\Part2_FTK.zip"

New-DeployCommands -OutputPath "$ftkDir\Deploy-Commands.txt" `
    -PackageName "FTK" `
    -PartNames @("Part1_Core.zip", "Part2_FTK.zip") `
    -Tool "FTK"


# =============================================================================
# STEP 10: Build ALL package (every tool)
# =============================================================================

Write-Host ""
Write-Host "Building ALL package..."

# ALL uses sequential numbering across all tools
Copy-Item $corePath    "$allDir\Part1_Core.zip"
Copy-Item $thorExeZip  "$allDir\Part2_THOR_Exe.zip"
Copy-Item $thorSigZip  "$allDir\Part3_THOR_Sigs.zip"
Copy-Item $kapeZip     "$allDir\Part4_KAPE.zip"
Copy-Item $ftkZip      "$allDir\Part5_FTK.zip"

New-DeployCommands -OutputPath "$allDir\Deploy-Commands.txt" `
    -PackageName "ALL" `
    -PartNames @("Part1_Core.zip", "Part2_THOR_Exe.zip", "Part3_THOR_Sigs.zip", "Part4_KAPE.zip", "Part5_FTK.zip") `
    -Tool $null


# =============================================================================
# STEP 11: Clean up temp zips and show summary
# =============================================================================

# Remove intermediate zips from Splits root (they've been copied into subfolders)
Remove-Item "$splitsRoot\Part*.zip" -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=========================================="
Write-Host "BUILD COMPLETE" -ForegroundColor Green
Write-Host "=========================================="
Write-Host ""
Write-Host "Packages ready in: $splitsRoot"
Write-Host ""

# Show summary for each package folder
foreach ($folder in @("THOR", "KAPE", "FTK", "ALL")) {
    $folderPath = "$splitsRoot\$folder"
    $zips = Get-ChildItem -Path $folderPath -Filter "*.zip"
    $totalMB = [math]::Round(($zips | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
    Write-Host "  $folder/ ($($zips.Count) zips, $totalMB MB total)" -ForegroundColor Cyan
    foreach ($zip in $zips) {
        $mb = [math]::Round($zip.Length / 1MB, 1)
        Write-Host "    $($zip.Name) ($mb MB)"
    }
    Write-Host ""
}

Write-Host "NEXT STEPS:"
Write-Host "  1. Open the folder for the tool you need (e.g., Splits\THOR\)"
Write-Host "  2. Read Deploy-Commands.txt for copy-paste instructions"
Write-Host "  3. Upload the Part*.zip files via Kibana Response Actions"
Write-Host "  4. Run the deploy command on the target host"
Write-Host ""

# =============================================================================
# CERBERUS-CONFIG.PS1 - Load and validate configuration file
# =============================================================================
#
# WHAT IS THIS FILE?
# This file contains ONE function: Get-CerberusConfig
# It reads Cerberus_Config.json and makes sure all required fields exist.
#
# HOW TO USE:
# 1. Dot-source this file: . "$PSScriptRoot\Lib\Cerberus-Config.ps1"
# 2. Call the function: $Config = Get-CerberusConfig -ScriptRoot $PSScriptRoot
# 3. If it returns $null, there was an error (already printed to screen)
#
# =============================================================================

function Get-CerberusConfig {
    <#
    .SYNOPSIS
        Loads and validates Cerberus_Config.json
    
    .DESCRIPTION
        This function:
        1. Checks if the config file exists
        2. Tries to parse the JSON
        3. Validates all required fields are present
        4. Returns the config object (or $null if error)
    
    .PARAMETER ScriptRoot
        The folder containing the Cerberus scripts (where Cerberus_Config.json lives)
    
    .EXAMPLE
        $Config = Get-CerberusConfig -ScriptRoot $PSScriptRoot
        if (-not $Config) { exit 1 }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot
    )
    
    $ConfigPath = "$ScriptRoot\Cerberus_Config.json"
    
    # -------------------------------------------------------------------------
    # STEP 1: Check if file exists
    # -------------------------------------------------------------------------
    if (-not (Test-Path $ConfigPath)) {
        Write-Host ""
        Write-Host "[ERROR] Config file not found!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Missing: $ConfigPath" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Cyan
        Write-Host "  1. Copy 'Cerberus_Config.json.template' to 'Cerberus_Config.json'"
        Write-Host "  2. Edit 'Cerberus_Config.json' with your MinIO credentials"
        Write-Host "  3. Run the script again"
        Write-Host ""
        return $null
    }
    
    # -------------------------------------------------------------------------
    # STEP 2: Try to parse JSON
    # -------------------------------------------------------------------------
    try {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host ""
        Write-Host "[ERROR] Failed to parse config file!" -ForegroundColor Red
        Write-Host ""
        Write-Host "JSON Error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "COMMON CAUSES:" -ForegroundColor Cyan
        Write-Host "  - Missing comma between fields"
        Write-Host "  - Missing quotes around strings"
        Write-Host "  - Trailing comma after last item in a list"
        Write-Host ""
        return $null
    }
    
    # -------------------------------------------------------------------------
    # STEP 3: Validate required fields
    # -------------------------------------------------------------------------
    $errors = @()
    
    # WHY validate MinIO credentials?
    # Even if the scan succeeds, we can't upload results without valid MinIO
    # settings. Catching this early saves operators from running a 4-hour scan
    # only to discover at upload time that credentials are missing.
    if (-not $Config.MinIO) {
        $errors += "Missing 'MinIO' section"
    } else {
        if (-not $Config.MinIO.Server -or $Config.MinIO.Server -eq $CONFIG_PLACEHOLDERS.Server) {
            $errors += "MinIO.Server not configured"
        }
        if (-not $Config.MinIO.AccessKey -or $Config.MinIO.AccessKey -eq $CONFIG_PLACEHOLDERS.AccessKey) {
            $errors += "MinIO.AccessKey not configured"
        }
        if (-not $Config.MinIO.SecretKey -or $Config.MinIO.SecretKey -eq $CONFIG_PLACEHOLDERS.SecretKey) {
            $errors += "MinIO.SecretKey not configured"
        }
        if (-not $Config.MinIO.Bucket) {
            $errors += "MinIO.Bucket not configured"
        }
    }
    
    # WHY validate Tools section?
    # Each Run-*.ps1 script reads its tool args from config. If args are missing,
    # the tool would either fail silently or run with no targets. Validating here
    # gives a clear "fix your config" message instead of a cryptic tool error.
    if (-not $Config.Tools) {
        $errors += "Missing 'Tools' section"
    } else {
        if (-not $Config.Tools.Thor -or -not $Config.Tools.Thor.Args) {
            $errors += "Tools.Thor.Args not configured"
        }
        if (-not $Config.Tools.Kape) {
            $errors += "Missing 'Tools.Kape' section"
        } else {
            if (-not $Config.Tools.Kape.DiskArgs) {
                $errors += "Tools.Kape.DiskArgs not configured"
            }
            if (-not $Config.Tools.Kape.RamArgs) {
                $errors += "Tools.Kape.RamArgs not configured"
            }
        }
        if (-not $Config.Tools.FTK -or -not $Config.Tools.FTK.Args) {
            $errors += "Tools.FTK.Args not configured"
        }
    }
    
    # If errors found, print them all
    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "=========================================" -ForegroundColor Red
        Write-Host "[ERROR] CONFIG VALIDATION FAILED" -ForegroundColor Red
        Write-Host "=========================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "Found $($errors.Count) problem(s):" -ForegroundColor Yellow
        Write-Host ""
        foreach ($err in $errors) {
            Write-Host "  [X] $err" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Cyan
        Write-Host "  1. Open Cerberus_Config.json"
        Write-Host "  2. Compare against Cerberus_Config.json.template"
        Write-Host "  3. Fill in all missing values"
        Write-Host ""
        return $null
    }
    
    # -------------------------------------------------------------------------
    # SUCCESS: Return the config object
    # -------------------------------------------------------------------------
    Write-Host "[CONFIG] Loaded successfully" -ForegroundColor Green
    return $Config
}

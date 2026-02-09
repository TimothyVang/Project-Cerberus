# =============================================================================
# CERBERUS-BOOTSTRAP.PS1 - Shared boilerplate for all Run-*.ps1 scripts
# =============================================================================
#
# WHAT IS THIS FILE?
# This file contains common setup and teardown functions that every Run-*.ps1
# script uses. Instead of duplicating ~120 lines of library loading, config
# validation, compression, and upload logic in each script, they call these
# shared functions.
#
# HOW TO USE:
# 1. Dot-source this file: . "$PSScriptRoot\Lib\Cerberus-Bootstrap.ps1"
# 2. Call Import-CerberusLibraries to load all shared modules
# 3. Call Initialize-CerberusRun to set up logging + config
# 4. (do your tool-specific work)
# 5. Call Compress-Evidence to zip results
# 6. Call Complete-CerberusRun to finish logging + upload
#
# =============================================================================

function Import-CerberusLibraries {
    <#
    .SYNOPSIS
        Dot-sources all shared Cerberus library files into the caller's scope

    .PARAMETER ScriptRoot
        The root folder of the Cerberus scripts (where Lib/ lives)

    .PARAMETER SkipRunTool
        If set, skips loading Cerberus-RunTool.ps1 (for scripts that don't
        execute external tools, like Run-UploadOnly.ps1)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ScriptRoot,

        [switch]$SkipRunTool
    )

    # Dot-source into the CALLER's scope so functions are available there
    . "$ScriptRoot\Lib\Write-Log.ps1"
    . "$ScriptRoot\Lib\Cerberus-Constants.ps1"
    . "$ScriptRoot\Lib\Cerberus-Config.ps1"
    . "$ScriptRoot\Lib\Cerberus-Upload.ps1"

    if (-not $SkipRunTool) {
        . "$ScriptRoot\Lib\Cerberus-RunTool.ps1"
    }
}

function Get-ZipFileName {
    <#
    .SYNOPSIS
        Generates a zip filename with HOSTNAME-DOMAIN-TOOL.zip format

    .PARAMETER Tool
        The tool name to include in the filename (e.g., "THOR", "KAPE-Disk")

    .PARAMETER Directory
        The directory where the zip file will be created
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Tool,

        [Parameter(Mandatory)]
        [string]$Directory
    )

    $hostname = $env:COMPUTERNAME
    $domain = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "WORKGROUP" }
    $zipName = "$hostname-$domain-$Tool.zip"

    return Join-Path $Directory $zipName
}

function Initialize-CerberusRun {
    <#
    .SYNOPSIS
        Performs common initialization: log session + config load + evidence folder

    .DESCRIPTION
        Every Run-*.ps1 script needs to:
        1. Initialize a log session for the operation
        2. Load and validate Cerberus_Config.json
        3. Ensure the Evidence folder exists
        This function does all three. If config fails, it logs the error,
        completes the session as FAILED, and exits the calling script.

    .PARAMETER Operation
        The operation name for logging (e.g., "THOR", "KAPE-Disk")

    .PARAMETER ScriptRoot
        The root folder of the Cerberus scripts

    .RETURNS
        Hashtable with Config, EvidenceFolder, and LogFile keys
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("THOR", "KAPE-Disk", "KAPE-Ram", "FTK", "UPLOAD", "UPLOAD-ONLY")]
        [string]$Operation,

        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )

    # Initialize log session
    $logFile = Initialize-LogSession -Operation $Operation -ScriptRoot $ScriptRoot

    # Load configuration
    Write-Log "Loading configuration..." "INFO" -Category "CONFIG"

    $config = Get-CerberusConfig -ScriptRoot $ScriptRoot

    if (-not $config) {
        Write-Log "Failed to load configuration" "ERROR" -Category "CONFIG"
        Complete-LogSession -Status "FAILED"
        exit 1
    }

    Write-Log "Configuration loaded successfully" "SUCCESS" -Category "CONFIG"

    # Ensure evidence folder exists
    $evidenceFolder = "$ScriptRoot\Evidence"
    if (-not (Test-Path $evidenceFolder)) {
        New-Item -ItemType Directory -Path $evidenceFolder -Force | Out-Null
    }

    return @{
        Config         = $config
        EvidenceFolder = $evidenceFolder
        LogFile        = $logFile
    }
}

function Compress-Evidence {
    <#
    .SYNOPSIS
        Compresses tool output into a zip file

    .DESCRIPTION
        Handles the common compression pattern: check for source, remove old zip,
        compress, log the result. Exits with code 1 on failure.

    .PARAMETER SourcePath
        The folder or path pattern containing files to compress

    .PARAMETER ZipFile
        The destination zip file path

    .PARAMETER SourceFiles
        Optional array of specific file paths to compress instead of SourcePath\*

    .PARAMETER SizeUnit
        Unit for displaying zip size: "MB" (default) or "GB"
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$ZipFile,

        [string[]]$SourceFiles,

        [ValidateSet("MB", "GB")]
        [string]$SizeUnit = "MB"
    )

    Write-Log "Compressing results..." "INFO" -Category "COMPRESS"

    # Determine what to compress
    $hasSource = if ($SourceFiles) {
        $SourceFiles.Count -gt 0
    } else {
        Test-Path $SourcePath
    }

    if ($hasSource) {
        try {
            if (Test-Path $ZipFile) {
                Remove-Item $ZipFile -Force
            }

            if ($SourceFiles) {
                Compress-Archive -Path $SourceFiles -DestinationPath $ZipFile -Force
            } else {
                Compress-Archive -Path "$SourcePath\*" -DestinationPath $ZipFile -Force
            }

            $zipBytes = (Get-Item $ZipFile).Length
            $divisor = if ($SizeUnit -eq "GB") { 1GB } else { 1MB }
            $zipSize = [math]::Round($zipBytes / $divisor, 2)
            Write-Log "Created: $ZipFile ($zipSize $SizeUnit)" "SUCCESS" -Category "COMPRESS"

            return "$zipSize $SizeUnit"
        }
        catch {
            Write-Log "Failed to compress: $($_.Exception.Message)" "ERROR" -Category "COMPRESS"
            Complete-LogSession -Status "FAILED"
            exit 1
        }
    } else {
        Write-Log "No output found - nothing to compress" "WARNING" -Category "COMPRESS"
        Complete-LogSession -Status "FAILED"
        exit 1
    }
}

function Complete-CerberusRun {
    <#
    .SYNOPSIS
        Completes the tool log session and uploads to MinIO

    .DESCRIPTION
        Every Run-*.ps1 script ends by:
        1. Completing the tool's log session with SUCCESS
        2. Uploading the zip to MinIO (which creates its own UPLOAD log session)
        3. Exiting with 0 on success or 1 on upload failure

    .PARAMETER ZipFile
        Path to the zip file to upload

    .PARAMETER ZipSizeFormatted
        Human-readable size string (e.g., "125.5 MB")

    .PARAMETER Config
        The config object containing MinIO credentials

    .PARAMETER ScriptRoot
        The root folder of the Cerberus scripts
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ZipFile,

        [Parameter(Mandatory)]
        [string]$ZipSizeFormatted,

        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )

    # Complete the tool's log session
    Complete-LogSession -Status "SUCCESS" -OutputFile $ZipFile -OutputSize $ZipSizeFormatted

    # Upload to MinIO (creates its own log session)
    Write-Log "Initiating upload to MinIO..." "INFO" -Category "UPLOAD"

    $uploaded = Send-ToMinIO -FilePath $ZipFile -Config $Config -ScriptRoot $ScriptRoot

    if ($uploaded) {
        Write-Log "==========================================" "INFO"
        Write-Log "SUCCESS: Evidence uploaded to MinIO" "SUCCESS"
        Write-Log "==========================================" "INFO"
        exit 0
    } else {
        Write-Log "==========================================" "INFO"
        Write-Log "Upload failed - evidence saved locally" "WARNING"
        Write-Log "Local file: $ZipFile" "WARNING"
        Write-Log "==========================================" "INFO"
        exit 1
    }
}

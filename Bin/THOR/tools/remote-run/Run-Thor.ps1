##################################################
# Script Title: THOR Download and Execute Script
# Script File Name: Run-Thor.ps1  
# Author: Florian Roth 
# Version: 0.3
# Date Created: 26.03.2020  
################################################## 
 
#Requires -Version 3

<#   
    .SYNOPSIS   
        The "Run-Thor" script downloads THOR and executes it
    .DESCRIPTION 
        The "Run-Thor" script downloads THOR from an ASGARD instance or the Netxron customer portal and executes THOR on the local system writing log files or transmitting syslog messages to a remote system
    .PARAMETER AsgardServer 
        Enter the server name or IP address of your ASGARD instance. 
    .PARAMETER UseCustomerPortal 
        Use the official Nextron customer portal instead of an ASGARD instance. 
    .PARAMETER ApiKey 
        API key used when connecting to Nextron's customer portal instead of an ASGARD instance.
    .PARAMETER CustomUrl 
        Allows you to define a custom URL from which the THOR package is retrieved. Make sure that the package is provided as ZIP archive, contains all valid licenses (or IR license) and contains no sub directory. A deflated archive must contain all binaries and important folders in the root of the archive. 
    .PARAMETER SyslogServer 
        Enter the server or IP address of your remote SYSLOG server to send the results to. 
    .PARAMETER OutputPath 
        A switching parameter that does not accept any value, but rather is used to tell the function to open the path location where the file was downloaded to.  
    .PARAMETER QuickScan 
        Perform a quick scan only. This reduces scan time by 80%, skipping "Eventlog" scan and checking the most relevant locations in "Filesystem" scan only. 
    .PARAMETER NoLog 
        Do not write a log file in the current working directory of the PowerShell script named run-thor.log. 
    .EXAMPLE
        Download THOR from asgard1.intranet.local (API key isn't required in on-premise installations)
        
        Run-Thor -AsgardServer asgard1.intranet.local
    .EXAMPLE
        Download THOR from asgard1.cloud.net using an API key and send the log to a remote SYSLOG system
        
        Run-Thor -AsgardServer asgard1.intranet.local -ApiKey wWfC0A0kMziG7GRJ5XEcGdZKw3BrigavxAdw9C9yxJX -SyslogServer siem-collector1.intranet.local
    .EXAMPLE
        Download THOR from asgard1.cloud.net using an API key and run a scan with a given config file
        
        Run-Thor -AsgardServer asgard1.intranet.local -ApiKey wWfC0A0kMziG7GRJ5XEcGdZKw3BrigavxAdw9C9yxJX -Config config.yml
    .EXAMPLE
        Download THOR from asgard1.intranet.local and save all output files to a writable network share
        
        Run-Thor -AsgardServer asgard1.intranet.local -OutputPath \\server\share
    .NOTES
        You can set a static API key and ASGARD server in this file (see below in the parameters)

        You can use YAML config files to pass parameters to the scan. Only the long form of the parameter is accepted. The contents of a config.yml could look like: 
        ```
        module:
            - Rootkit
            - Mutex
            - ShimCache
            - Eventlog
        nofast: true
        nocolor: true
        lookback: 3
        syslog:
            - siem1.local
        ```
        There is also a section in this script in which you can predefine a config. See the predefined variables  after the params section.
#>

# #####################################################################
# Parameters ----------------------------------------------------------
# #####################################################################

param  
( 
    [Parameter( 
        HelpMessage='The ASGARD instance to download THOR from (license will be generated on that instance)')] 
        [ValidateNotNullOrEmpty()] 
        [Alias('AMC')]    
        # You can set your static ASGARD server here. 
        # Just uncomment the next line and comment the second next line. 
        #[string]$AsgardServer = "asgard.beta.nextron-systems.com",
        [string]$AsgardServer,  

    [Parameter(HelpMessage="Use Nextron's customer portal instead of an ASGARD instance to download THOR and generate a license")] 
        [ValidateNotNullOrEmpty()] 
        [Alias('CP')]    
        [switch]$UseCustomerPortal,

    [Parameter(HelpMessage="Use the following API key")] 
        [ValidateNotNullOrEmpty()] 
        [Alias('K')]
        # You can set your static API key here. 
        # You can find your user's API key in "User Settings > Tab: API Key"
        # Just uncomment the next line and comment the second next line. 
        #[string]$ApiKey = "YOUR API KEY",
        [string]$ApiKey,
 
    [Parameter( 
        HelpMessage='Allows you to define a custom URL from which the THOR package is retrieved.')] 
        [ValidateNotNullOrEmpty()] 
        [Alias('CU')]    
        # You can set your static custom downlod URL here. 
        # Just uncomment the next line and comment the second next line. 
        #[string]$CustomUrl = "https://internal-webserver1.intranet.local",
        [string]$CustomUrl, 

    [Parameter(HelpMessage="Config YAML file to be used in the scan")] 
        [ValidateNotNullOrEmpty()] 
        [Alias('C')]    
        [string]$Config, 

    [Parameter(HelpMessage="Remote SYSLOG system that should receive THOR's log as SYSLOG messages")] 
        [ValidateNotNullOrEmpty()] 
        [Alias('SS')]    
        [string]$SyslogServer, 
 
    [Parameter(HelpMessage='Output path to write all output files to (can be a local directory or UNC path to a file share on a server)')] 
        [ValidateNotNullOrEmpty()] 
        [Alias('OP')]    
        [string]$OutputPath = $PSScriptRoot, 

    [Parameter(HelpMessage='Activates quick scan')] 
        [ValidateNotNullOrEmpty()] 
        [Alias('Q')]    
        [switch]$QuickScan,

    [Parameter(HelpMessage='Deactivates log file for this PowerShell script (thor-run.log)')] 
        [ValidateNotNullOrEmpty()] 
        [Alias('NL')]    
        [switch]$NoLog
)

# Global Variables ----------------------------------------------------
$global:NoLog = $NoLog

# Predefined YAML Config ----------------------------------------------
$UsePresetConfig = $True
# Lines with '#' are commented and inactive. We decided to give you 
# some examples for your convenience. You can see all possible command 
# line parameters running thor64.exe --help. Only the long forms of the
# parameters are accepted in the YAML config. 
$PresetConfig = @"
module:
# - Autoruns
  - Rootkit
  - ShimCache
  - DNSCache 
# - RegistryChecks
# - ScheduledTasks
  - FileScan
# - Eventlog
nofast: true
# nocolor: true
lookback: 3  # Log and Eventlog look back time in days
cpulimit: 50  # Limit the CPU usage of the scan
path:
    - C:\Temp
    - C:\Users\Public
"@

# Show Help
# No ASGARD server 
if ( $Args.Count -eq 0 -and $AsgardServer -eq "" -and $UseCustomerPortal -eq $False -and $CustomUrl -eq "" ) {
    Get-Help $MyInvocation.MyCommand.Definition -Detailed
    Write-Host -ForegroundColor Yellow 'Note: You must at least define an ASGARD server via command line parameter -AsgardServer or in this PowerShell script as preset value in the "params" section. For ASGARD Cloud you also need an API key that you can get in the "User Settings" sction of that ASGARD Cloud instance.'
    return
}
# Customer Portal but no API key
if ( $Args.Count -eq 0 -and $UseCustomerPortal -eq $True ) {
    Get-Help $MyInvocation.MyCommand.Definition -Detailed
    Write-Host -ForegroundColor Yellow 'Note: You must at least define an API key via command line parameter -ApiKey or in this PowerShell script as preset value in the "params" section.'
    return
}

# #####################################################################
# Functions -----------------------------------------------------------
# #####################################################################

function New-TemporaryDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    $name = [System.IO.Path]::GetRandomFileName()
    New-Item -ItemType Directory -Path (Join-Path $parent $name)
}

# Required for ZIP extraction in PowerShell version <5.0
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Expand-File {
    param([string]$ZipFile, [string]$OutPath)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFile, $OutPath)
}

function Write-Log {
    param (
        [Parameter(Mandatory=$True, Position=0, HelpMessage="Log entry")]
            [ValidateNotNullOrEmpty()] 
            [String]$Entry,

        [Parameter(Position=1, HelpMessage="Log file to write into")] 
            [ValidateNotNullOrEmpty()] 
            [Alias('SS')]    
            [IO.FileInfo]$LogFile = "run-thor.log",

        [Parameter(Position=3, HelpMessage="Level")]
            [ValidateNotNullOrEmpty()] 
            [String]$Level = "Info"
    )
    
    # Indicator 
    $Indicator = "[+]"
    if ( $Level -eq "Warning" ) {
        $Indicator = "[!]"
    } elseif ( $Level -eq "Error" ) {
        $Indicator = "[E]"
    } elseif ( $Level -eq "Process" ) {
        $Indicator = "[.]"
    } elseif ($Level -eq "Note" ) {
        $Indicator = "[i]"
    }

    # Output Pipe
    if ( $Level -eq "Warning" ) {
        Write-Warning -Message "$($Indicator) $($Entry)"
    } elseif ( $Level -eq "Error" ) {
        Write-Host "$($Indicator) $($Entry)" -ForegroundColor Red
    } else {
        Write-Host "$($Indicator) $($Entry)"
    }
    
    # Log File
    if ( $global:NoLog -eq $False ) {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $($env:COMPUTERNAME): $Entry" | Out-File -FilePath $LogFile -Append
    }
}

# #####################################################################
# Main Program --------------------------------------------------------
# #####################################################################

Write-Host "==========================================================="
Write-Host "     ___               ________ ______  ___  "
Write-Host "    / _ \__ _____  ___/_  __/ // / __ \/ _ \ "
Write-Host "   / , _/ // / _ \/___// / / _  / /_/ / , _/ "
Write-Host "  /_/|_|\_,_/_//_/    /_/ /_//_/\____/_/|_|  "
Write-Host "                                                           "
Write-Host "  Nextron Systems, by Florian Roth "
Write-Host "                                                           "
Write-Host "==========================================================="

# Measure time
$StartTime = $(get-date)

Write-Log "Started Run-THOR with PowerShell v$($PSVersionTable.PSVersion)"

# ---------------------------------------------------------------------
# Get THOR ------------------------------------------------------------
# ---------------------------------------------------------------------
try {
    # Presets
    # Temporary directory for the THOR package
    $ThorDirectory = New-TemporaryDirectory
    $TempPackage = Join-Path $ThorDirectory "thor-package.zip"

    # Generate Download URL
    # License Type
    $LicenseType = "server"
    $OsInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ( $osInfo.ProductType -eq 1 ) { 
        $LicenseType = "client"
    }
    # Download Source
    # Asgard Instance
    if ( $AsgardServer -ne "" ) {
        # Generate download URL 
        $DownloadUrl = "https://$($AsgardServer):8443/api/v0/downloads/thor/thor10-win?hostname=$($env:COMPUTERNAME)&type=$($LicenseType)&iocs=%5B%22default%22%5D"
    }
    # Netxron Customer Portal
    elseif ( $UseCustomerPortal ) {
        # not yet available in customer portal API
    } 
    # Custom URL 
    elseif ( $CustomUrl -ne "" ) {
        $DownloadUrl = $CustomUrl
    # 
    } else {
        Write-Log 'Download URL cannot be generated (select one of the three options: $AsgardServer, $UseCustomerPortal or $CustomUrl'
        break
    }

    # Download
    try {
        # Web Client
        $WebClient = New-Object System.Net.WebClient 
        if ( $ApiKey ) { 
            $WebClient.Headers.add('Authorization',$ApiKey)
        }
        # Info Messages
        if ( $UseCustomerPortal ) {
            Write-Log 'Attempting to download THOR from nextron customer portal, please wait ...' -Level "Process"
        } else {
            Write-Log "Attempting to download THOR from $AsgardServer" -Level "Process"
        } 
        Write-Log "Download URL: $($DownloadUrl)"
        # Request
        $WebClient.DownloadFile($DownloadUrl, $TempPackage)
        Write-Log "Successfully downloaded THOR package to $($TempPackage)"
    }
    # HTTP Errors
    catch [System.Net.WebException] {
        Write-Log "The following error occurred: $_" -Level "Error"
        $Response = $_.Exception.Response
        # 401 Unauthorized
        if ( [int]$Response.StatusCode -eq 401 ) { 
            Write-Log "The server returned an 401 Unauthorized status code. Did you set an API key? (-ApiKey key)" -Level "Warning"
            if ( $UseCustomerPortal ) { 
                Write-Log "Note: you can find your API key here: https://portal.nextron-systems.com/"
            } else {
                Write-Log "Note: you can find your API key here: https://$AsgardServer:8443/ui/user-settings#tab-apikey"
            }
        }
        break
    }
    catch { 
        Write-Log "The following error occurred: $_" -Level "Error"
        break 
    } 

    # Unzip
    try {
        Write-Log "Extracting THOR package" -Level "Process"
        Expand-File $TempPackage $ThorDirectory
    } catch {
        Write-Log "Error while expanding the THOR ZIP package $_" -Level "Error"  
        break
    }
} catch {
    Write-Log "Download or extraction of THOR failed. $_" -Level "Error"
    break
}

# ---------------------------------------------------------------------
# Run THOR ------------------------------------------------------------
# ---------------------------------------------------------------------
try {
    # Evaluate Architecture 
    $ThorVariant = "thor64.exe"
    if ( [System.Environment]::Is64BitOperatingSystem -eq $False ) {
        $ThorVariant = "thor.exe"
    }
    $ThorBinary = Join-Path $ThorDirectory $ThorVariant
    # Check if binary exist
    if (-Not (Test-Path $ThorBinary -PathType leaf )) { 
        Write-Log "THOR binary $($ThorVariant) not found in directory $($ThorDirectory)" -Level "Error"
        if ( $CustomUrl ) {
            Write-Log 'When using a custom ZIP package, make sure that the THOR binaries are in the root of the archive and not any sub-folder. (e.g. ./thor64.exe and ./signatures)' -Level "Warning"
        } else {
            Write-Log "This seems to be a bug. You could check the temporary THOR package yourself in location $($ThorDirectory)." -Level "Warning"
        }
        break
    }

    # Use Preset Config (instead of external .yml file)
    if ( $UsePresetConfig -and $Config -eq "" ) {
        Write-Log "Using preset config defined in script header due to $UsePresetConfig = True"
        $TempConfig = Join-Path $ThorDirectory "config.yml"
        Write-Log "Writing temporary config to $($TempConfig)" -Level "Process"
        Out-File -FilePath $TempConfig -InputObject $PresetConfig -Encoding ASCII
        $Config = $TempConfig
    }

    # Scan parameters 
    [string[]]$ScanParameters = @()
    if ( $QuickScan ) {
        $ScanParameters += "--quick"
    }
    if ( $SyslogServer ) {
        $ScanParameters += "-s $($SyslogServer)"
    }
    if ( $OutputPath ) { 
        $ScanParameters += "-e $($OutputPath)"
    }
    if ( $Config ) {
        $ScanParameters += "-t $($Config)"
    }

    # Run THOR
    Write-Log "Starting THOR scan ..." -Level "Process"
    Write-Log "Command Line: $($ThorBinary) $($ScanParameters)"
    # With Arguments
    if ( $ScanParameters.Count -gt 0 ) {
        $p = Start-Process $ThorBinary -ArgumentList $ScanParameters -wait -NoNewWindow -PassThru
    } 
    # Without Arguments
    else { 
        $p = Start-Process $ThorBinary -wait -NoNewWindow -PassThru
    }

    if ( $p.ExitCode -ne 0 ) {
        Write-Log "THOR scan terminated with error code $($p.ExitCode)" -Level "Error" 
    } else {
        Write-Log "Successfully finished THOR scan"
    }
} catch { 
    Write-Log "Unknown error during THOR scan $_" -Level "Error"   
}

# ---------------------------------------------------------------------
# Cleanup -------------------------------------------------------------
# ---------------------------------------------------------------------
try {
    Write-Log "Cleaning up temporary directory with THOR package ..." -Level Process
    # Delete THOR ZIP package
    Remove-Item -Confirm:$False -Force -Recurse $TempPackage -ErrorAction Ignore
    # Delete THOR Folder
    Remove-Item -Confirm:$False -Recurse -Force $ThorDirectory -ErrorAction Ignore
} catch {
    Write-Log "Cleanup of temp directory $($ThorDirectory) failed. $_" -Level "Error"
}

# ---------------------------------------------------------------------
# End -----------------------------------------------------------------
# ---------------------------------------------------------------------
$ElapsedTime = $(get-date) - $StartTime
$TotalTime = "{0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks)
Write-Log "Scan took $($TotalTime) to complete" -Level "Information"

# =============================================================================
# PROJECT CERBERUS - REMOTE AGENT (ELASTIC DEFEND / SECURITY ONION)
# =============================================================================
# Purpose: Run Thor/KAPE remotely via Kibana and upload results to MinIO.
# Usage:   powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\Cerberus_Agent.ps1" -Tool <THOR|KAPE>
# Note:    Does NOT auto-delete evidence. Persistence allowed.
# =============================================================================

param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("THOR", "KAPE-TRIAGE", "KAPE-RAM", "FTK")]
    [string]$Tool = "THOR",  # Default to Thor if not specified

    [switch]$UploadOnly  # If set, skips scan and just tries to upload existing evidence
)

# =============================================================================
# [CONFIGURATION] - LOADED FROM Cerberus_Config.json
# =============================================================================
# $ConfigPath = Path to the JSON configuration file in the same folder as this script
$ConfigPath = "$PSScriptRoot\Cerberus_Config.json"

# Test-Path checks if a file exists (returns True or False)
if (Test-Path $ConfigPath) {
    try {
        # Step 1: Read JSON file and convert it to a PowerShell object
        # Get-Content reads the file | ConvertFrom-Json parses the JSON
        $Config = Get-Content $ConfigPath | ConvertFrom-Json

        # Step 2: Extract values from the JSON object
        # $Config.MinIO.Server means: get the "Server" property from the "MinIO" section
        $MINIO_SERVER = $Config.MinIO.Server
        $ACCESS_KEY = $Config.MinIO.AccessKey
        $SECRET_KEY = $Config.MinIO.SecretKey
        $UPLOAD_BUCKET = $Config.MinIO.Bucket

        # Step 3: Validate config values to ensure they were actually configured
        # -not means "NOT" (opposite of True)
        # -or means "OR" (if ANY condition is true, the whole thing is true)
        # -eq means "equals"
        if (-not $MINIO_SERVER -or $MINIO_SERVER -eq "" -or $MINIO_SERVER -eq "YOUR_MINIO_SERVER:PORT") {
            Write-Host "[ERROR] MinIO Server not configured in Cerberus_Config.json" -ForegroundColor Red
            Write-Host "[INFO] Copy Cerberus_Config.json.template to Cerberus_Config.json and edit" -ForegroundColor Yellow
            exit 1
        }
        if (-not $ACCESS_KEY -or $ACCESS_KEY -eq "" -or $ACCESS_KEY -eq "YOUR_ACCESS_KEY") {
            Write-Host "[ERROR] MinIO AccessKey not configured" -ForegroundColor Red
            exit 1
        }
        if (-not $SECRET_KEY -or $SECRET_KEY -eq "" -or $SECRET_KEY -eq "YOUR_SECRET_KEY") {
            Write-Host "[ERROR] MinIO SecretKey not configured" -ForegroundColor Red
            exit 1
        }
        if (-not $UPLOAD_BUCKET -or $UPLOAD_BUCKET -eq "") {
            Write-Host "[ERROR] MinIO Bucket not configured" -ForegroundColor Red
            exit 1
        }

        Write-Host "[INFO] Loaded Configuration from Cerberus_Config.json" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to parse Cerberus_Config.json: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "[ERROR] Config file not found: $ConfigPath" -ForegroundColor Red
    Write-Host "[INFO] Copy Cerberus_Config.json.template to Cerberus_Config.json" -ForegroundColor Yellow
    exit 1
}

# =============================================================================

# =============================================================================
# SETUP PATHS
# =============================================================================
# $PSScriptRoot = The folder where this script is located
# Example: If script is at C:\Cerberus\Cerberus_Agent.ps1, then $PSScriptRoot = C:\Cerberus
$ScriptRoot = $PSScriptRoot
$BinDir = "$ScriptRoot\Bin"              # Where tools are stored (THOR, KAPE, etc.)
$EvidenceDir = "$ScriptRoot\Evidence"    # Where collected evidence is saved
$MinioExe = "$BinDir\MinIO\mc.exe"       # MinIO client for uploads

# Create Evidence directory if it doesn't exist
if (-not (Test-Path $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

# =============================================================================
# MONITORING & HELPER FUNCTIONS
# =============================================================================

function Monitor-Process {
    <#
    .SYNOPSIS
        Monitors a running process and provides progress heartbeats
    .DESCRIPTION
        Tracks process execution with periodic heartbeats every 60 seconds
        to prevent Elastic Defend timeouts during long-running operations
    #>
    param(
        [System.Diagnostics.Process]$Process,
        [string]$ToolName,
        [string]$LogFile,
        [int]$HeartbeatInterval = 60  # seconds
    )

    $startTime = Get-Date
    $lastFileSize = 0

    while (-not $Process.HasExited) {
        $waitResult = $Process.WaitForExit($HeartbeatInterval * 1000)

        $elapsed = (Get-Date) - $startTime
        $elapsedMin = [math]::Round($elapsed.TotalMinutes, 1)

        # Check for progress indicators
        if (Test-Path $LogFile) {
            $currentFileSize = (Get-Item $LogFile).Length
            $sizeKB = [math]::Round($currentFileSize / 1KB, 2)

            if ($currentFileSize -gt $lastFileSize) {
                Write-Host "[$ToolName] Progress: Log file now $sizeKB KB (elapsed: $elapsedMin min)"
                $lastFileSize = $currentFileSize
            } else {
                Write-Host "[$ToolName] Still running... (elapsed: $elapsedMin min, PID: $($Process.Id))"
            }
        } else {
            Write-Host "[$ToolName] Running... (elapsed: $elapsedMin min, PID: $($Process.Id))"
        }
    }

    return $Process.ExitCode
}

function Test-MinIOConnectivity {
    <#
    .SYNOPSIS
        Tests network connectivity to MinIO server
    .DESCRIPTION
        Validates that MinIO server is reachable before attempting uploads
        to prevent silent failures
    #>
    param([string]$Server)

    $serverParts = $Server -split ':'
    $hostName = $serverParts[0]
    $port = if ($serverParts.Count -gt 1) { $serverParts[1] } else { 443 }

    Write-Host "[NETWORK] Testing connectivity to $hostName`:$port..."

    try {
        $testConnection = Test-NetConnection -ComputerName $hostName -Port $port -WarningAction SilentlyContinue -ErrorAction Stop

        if ($testConnection.TcpTestSucceeded) {
            Write-Host "[NETWORK] MinIO server is reachable at $Server"
            return $true
        } else {
            Write-Host "[NETWORK] Cannot reach MinIO server at $Server"
            Write-Host "[NETWORK] Check firewall rules and network connectivity"
            return $false
        }
    }
    catch {
        Write-Host "[NETWORK] Network test failed: $($_.Exception.Message)"
        return $false
    }
}

# Import logging module (loads Write-Log function from Lib folder)
# The dot (.) means "run this script in the current scope"
. "$PSScriptRoot\Lib\Write-Log.ps1"

# =============================================================================
# UPLOAD FUNCTION - Sends files/folders to MinIO server
# =============================================================================
function Upload-To-MinIO ($FilePath) {
    # Step 1: Check if MinIO client exists
    if (-not (Test-Path $MinioExe)) {
        Write-Log "MinIO Client (mc.exe) not found at: $MinioExe" "ERROR"
        return  # Exit function early
    }

    Write-Log "Starting MinIO Upload for: $FilePath"

    # Step 2: Configure MinIO connection
    # This sets an environment variable that mc.exe will use
    $env:MC_HOST_minio = "https://${ACCESS_KEY}:${SECRET_KEY}@${MINIO_SERVER}"

    # Step 3: Upload (different command for files vs directories)
    if (Test-Path $FilePath -PathType Container) {
        # It's a directory - use recursive flag (-r)
        # The & operator runs the external program
        & $MinioExe put -r "$FilePath" "minio/$UPLOAD_BUCKET" --insecure
    }
    else {
        # It's a single file - no -r flag needed
        & $MinioExe put "$FilePath" "minio/$UPLOAD_BUCKET" --insecure
    }

    # Step 4: Check if upload succeeded
    # $LASTEXITCODE = exit code from the last program we ran
    # 0 = success, anything else = error
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Upload Complete: $FilePath" "SUCCESS"
    }
    else {
        Write-Log "Upload Failed for: $FilePath" "ERROR"
        Write-Log "Check Network: Can you reach $MINIO_SERVER ?" "ERROR"
        Write-Log "Check Config: Verify AccessKey/SecretKey in Cerberus_Config.json" "ERROR"
        Write-Log "Local Copy Preserved: $FilePath" "INFO"
    }
}

# =============================================================================
# MAIN LOGIC - Decides whether to scan or just upload
# =============================================================================
if ($UploadOnly) {
    # User passed -UploadOnly flag, so skip scanning and just upload existing files
    Write-Log "Upload-Only mode selected. Skipping scan."
}
else {
    # =============================================================================
    # DISK SPACE CHECK - Make sure we have enough space before starting
    # =============================================================================
    # Step 1: Get the drive letter where Evidence folder is located (e.g., "C:")
    $Drive = (Get-Item $EvidenceDir).PSDrive.Name + ":"

    # Step 2: Query Windows WMI to get disk information
    # Win32_LogicalDisk is a Windows class that contains disk info
    $DiskSpace = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$Drive'"

    # Step 3: Convert bytes to GB and round to 2 decimal places
    # [math]::Round() is a .NET method for rounding numbers
    # 1GB = 1073741824 bytes (PowerShell understands 1GB as a shortcut)
    $FreeGB = [math]::Round($DiskSpace.FreeSpace / 1GB, 2)

    Write-Log "Available disk space on ${Drive}: $FreeGB GB"

    # Step 4: Check if we have enough space for large operations
    # -lt means "less than"
    if ($Tool -eq "FTK" -or $Tool -eq "KAPE-TRIAGE") {
        if ($FreeGB -lt 10) {
            Write-Log "ERROR: Insufficient disk space ($FreeGB GB). Need at least 10 GB for $Tool" "ERROR"
            exit 1  # Exit code 1 means "error" (0 would mean "success")
        }
    }
    elseif ($FreeGB -lt 1) {
        Write-Log "WARNING: Low disk space ($FreeGB GB) - operation may fail" "WARNING"
    }

    # =============================================================================
    # EXIT CODE TRACKING
    # =============================================================================
    # Track script execution status for proper exit codes to Elastic Defend
    $scriptSuccess = $true
    $failedComponents = @()

    # =============================================================================
    # TOOL EXECUTION - THOR (APT Scanner)
    # =============================================================================
    if ($Tool -eq "THOR") {
        Write-Log "Starting THOR Scan (Remote Mode)..."
        $ThorExe = "$BinDir\THOR\thor64-lite.exe"
        $ThorOutput = "$EvidenceDir\$env:COMPUTERNAME-THOR"

        if (-not (Test-Path $ThorExe)) {
            Write-Log "Thor binary not found at $ThorExe" "ERROR"
            $scriptSuccess = $false
            $failedComponents += "THOR"
            exit 1
        }

        if (-not (Test-Path $ThorOutput)) {
            New-Item -ItemType Directory -Path $ThorOutput -Force | Out-Null
        }

        # Get THOR arguments from config
        $ThorArgs = $Config.Tools.Thor.Args
        $ThorLogFile = "$ThorOutput\$env:COMPUTERNAME.txt"
        $ThorHtmlFile = "$ThorOutput\$env:COMPUTERNAME.html"

        Write-Log "[THOR] Command: $ThorExe --logfile `"$ThorLogFile`" --htmlfile `"$ThorHtmlFile`" $ThorArgs"
        Write-Log "[THOR] Output: $ThorOutput"
        Write-Log "[THOR] Starting scan (this may take 1-4 hours)..."

        # Start process with monitoring
        $thorProcess = Start-Process -FilePath $ThorExe `
            -ArgumentList "--logfile `"$ThorLogFile`" --htmlfile `"$ThorHtmlFile`" $ThorArgs" `
            -PassThru -NoNewWindow

        # Monitor with timeout (48 hours)
        $timeout = 172800000  # 48 hours in milliseconds
        $startTime = Get-Date
        $lastLogSize = 0

        while (-not $thorProcess.HasExited) {
            $elapsed = (Get-Date) - $startTime

            # Timeout check
            if ($elapsed.TotalMilliseconds -gt $timeout) {
                Write-Log "[THOR] Timeout after 48 hours - killing process" "ERROR"
                $thorProcess.Kill()
                Write-Log "[ERROR] THOR scan timeout" "ERROR"
                $scriptSuccess = $false
                $failedComponents += "THOR"
                exit 1
            }

            # Wait 60 seconds or until exit
            $exited = $thorProcess.WaitForExit(60000)

            # Progress heartbeat
            if (Test-Path $ThorLogFile) {
                $currentSize = (Get-Item $ThorLogFile).Length
                $sizeMB = [math]::Round($currentSize / 1MB, 2)
                $elapsedMin = [math]::Round($elapsed.TotalMinutes, 1)

                if ($currentSize -gt $lastLogSize) {
                    Write-Log "[THOR] Progress: Log $sizeMB MB (elapsed: $elapsedMin min)"
                    $lastLogSize = $currentSize
                } else {
                    Write-Log "[THOR] Still scanning... (elapsed: $elapsedMin min)"
                }
            }
        }

        $exitCode = $thorProcess.ExitCode

        # Validate exit codes (Thor-specific)
        if ($exitCode -eq 0) {
            Write-Log "[THOR] Exit code 0: Success - No threats detected" "SUCCESS"
        } elseif ($exitCode -eq 1) {
            Write-Log "[THOR] Exit code 1: Warnings - Suspicious activity detected" "WARNING"
        } elseif ($exitCode -eq 2) {
            Write-Log "[THOR] Exit code 2: Alerts - Potential threats found" "WARNING"
        } elseif ($exitCode -eq 3) {
            Write-Log "[THOR] Exit code 3: Notices - Check manually" "WARNING"
        } elseif ($exitCode -ge 4) {
            Write-Log "[ERROR] THOR Exit code $exitCode: Fatal error" "ERROR"
            $scriptSuccess = $false
            $failedComponents += "THOR"
        }

        Write-Log "Thor Scan Finished with exit code: $exitCode"
    }
    # =============================================================================
    # TOOL EXECUTION - KAPE TRIAGE (Forensic File Collector)
    # =============================================================================
    elseif ($Tool -eq "KAPE-TRIAGE") {
        Write-Log "Starting KAPE Triage (Files/Artifacts)..."
        $KapeExe = "$BinDir\KAPE\kape.exe"
        $KapeOutput = "$EvidenceDir\$env:COMPUTERNAME-KAPE-Triage"

        # Check if KAPE executable exists
        if (-not (Test-Path $KapeExe)) { Write-Log "KAPE binary not found at $KapeExe" "ERROR"; exit 1 }

        # Build arguments using PowerShell array syntax
        # @ creates an array, each line is one argument
        # This is cleaner and safer than building one long string
        $KapeArgs = @(
            '--tsource', 'C:'          # Source drive to collect from
            '--tdest', $KapeOutput      # Destination folder for collected files
            '--tflush'                  # Flush (copy) files immediately
            '--target', '!SANS_Triage,IISLogFiles,Exchange,ExchangeCve-2021-26855,MemoryFiles,MOF,BITS'  # Which artifacts to collect
            '--ifw'                     # Ignore file write errors
            '--vhdx', 'TargetsOutput_%m'  # Create VHDX virtual disk image
            '--zpw', 'NWY0ZGNjM2I1YWE3NjVkNjFkODMyN2RlYjg4MmNmOTk='  # Zip password (base64 encoded)
        )

        # Execute KAPE and wait for completion
        $kapeProcess = Start-Process -FilePath $KapeExe -ArgumentList $KapeArgs -PassThru -NoNewWindow -Wait

        # Verify KAPE completed successfully
        if ($kapeProcess.ExitCode -ne 0) {
            Write-Log "KAPE Triage failed with exit code: $($kapeProcess.ExitCode)" "ERROR"
        }
        Write-Log "KAPE Triage Finished."
    }
    # =============================================================================
    # TOOL EXECUTION - KAPE RAM (Memory Capture)
    # =============================================================================
    elseif ($Tool -eq "KAPE-RAM") {
        Write-Log "Starting KAPE RAM Capture..."
        $KapeExe = "$BinDir\KAPE\kape.exe"
        $KapeOutput = "$EvidenceDir\$env:COMPUTERNAME-RAM"

        # Check if KAPE executable exists
        if (-not (Test-Path $KapeExe)) { Write-Log "KAPE binary not found at $KapeExe" "ERROR"; exit 1 }

        # Build arguments for RAM capture module
        # RAM capture grabs the contents of memory (running processes, etc.)
        $RamArgs = @(
            '--msource', 'C:\'          # Module source (not used for RAM capture but required)
            '--mdest', $KapeOutput       # Destination for memory dump
            '--zm', 'true'               # Zip module output
            '--module', 'MagnetForensics_RAMCapture'  # KAPE module for memory acquisition
            '--zpw', 'NWY0ZGNjM2I1YWE3NjVkNjFkODMyN2RlYjg4MmNmOTk='  # Zip password
        )

        # Execute KAPE RAM module
        $ramProcess = Start-Process -FilePath $KapeExe -ArgumentList $RamArgs -PassThru -NoNewWindow -Wait

        # Verify RAM capture succeeded
        if ($ramProcess.ExitCode -ne 0) {
            Write-Log "KAPE RAM failed with exit code: $($ramProcess.ExitCode)" "ERROR"
        }

        Write-Log "KAPE RAM Capture Finished."
    }
    # =============================================================================
    # TOOL EXECUTION - FTK IMAGER (Disk Imaging)
    # =============================================================================
    elseif ($Tool -eq "FTK") {
        Write-Log "Starting FTK Imager (Remote Mode)..."
        $FtkExe = "$BinDir\FTK\x64\ftkimager.exe"
        $FtkImageBase = "$EvidenceDir\$env:COMPUTERNAME-Disk"

        # Check if FTK executable exists
        if (-not (Test-Path $FtkExe)) { Write-Log "FTK binary not found at $FtkExe" "ERROR"; exit 1 }

        # Get FTK arguments from config (like --compress 9 --frag 1TB)
        $FtkArgs = $Config.Tools.FTK.Args

        # FTK creates a forensic image (exact copy) of the C: drive
        # This takes a LONG time and uses a lot of disk space!
        Write-Log "Acquiring C: drive to $FtkImageBase.raw..."
        $ftkProcess = Start-Process -FilePath $FtkExe -ArgumentList "C: `"$FtkImageBase.raw`" $FtkArgs" -PassThru -NoNewWindow -Wait

        # Check if imaging succeeded
        if ($ftkProcess.ExitCode -ne 0) {
            Write-Log "FTK failed with exit code: $($ftkProcess.ExitCode)" "ERROR"
        }

        Write-Log "FTK Acquisition Finished."
    }
    
    # =============================================================================
    # AUTO-UPLOAD - Upload evidence immediately after collection
    # =============================================================================
    Write-Log "`n[PHASE] Auto-Uploading Evidence..."

    # Upload the correct folder based on which tool we ran
    if ($Tool -eq "THOR") {
        Upload-To-MinIO -FilePath "$EvidenceDir\$env:COMPUTERNAME-THOR"
    }
    elseif ($Tool -eq "KAPE-TRIAGE") {
        Upload-To-MinIO -FilePath "$EvidenceDir\$env:COMPUTERNAME-KAPE-Triage"
    }
    elseif ($Tool -eq "KAPE-RAM") {
        Upload-To-MinIO -FilePath "$EvidenceDir\$env:COMPUTERNAME-RAM"
    }
    elseif ($Tool -eq "FTK") {
        # FTK creates multiple files (image.raw, image.raw.001, etc.)
        # Get-ChildItem lists files in a directory
        # | ForEach-Object runs code for each file found
        Get-ChildItem -Path "$EvidenceDir" -Filter "$env:COMPUTERNAME-Disk.*" | ForEach-Object {
            Upload-To-MinIO -FilePath $_.FullName  # $_ = current file in the loop
        }
    }
}

# =============================================================================
# FINAL UPLOAD PHASE - Upload any remaining evidence files
# =============================================================================
Write-Log "Scanning for evidence to upload..."

# Search Evidence directory for files matching this computer's name
# -Recurse means "search subfolders too"
# Where-Object filters the results
# -match does pattern matching, -not means NOT, $_.PSIsContainer checks if it's a folder
$EvidenceFiles = Get-ChildItem -Path $EvidenceDir -Recurse | Where-Object { $_.Name -match $env:COMPUTERNAME -and -not $_.PSIsContainer }

if ($EvidenceFiles) {
    # Loop through each evidence file found
    foreach ($File in $EvidenceFiles) {
        # Compress large files to save bandwidth and storage
        # 100MB = 100 megabytes (1MB = 1048576 bytes)
        if ($File.Extension -ne ".zip" -and $File.Length -gt 100MB) {
            Write-Log "[INFO] Large file detected: $($File.Name). Attempting to Zip before upload..."
            $ZipPath = "$($File.FullName).zip"

            # Compress-Archive creates a .zip file
            # -Force means "overwrite if zip already exists"
            Compress-Archive -Path $File.FullName -DestinationPath $ZipPath -Force
            Upload-To-MinIO -FilePath $ZipPath

            # Keep the original unzipped file locally (for persistence!)
        }
        else {
            # File is small or already zipped - upload as-is
            Upload-To-MinIO -FilePath $File.FullName
        }
    }
}
else {
    # No evidence files found - this might indicate a problem
    Write-Log "[WARN] No evidence files found matching $env:COMPUTERNAME in $EvidenceDir"
}

Write-Log "Cerberus Agent Execution Complete."

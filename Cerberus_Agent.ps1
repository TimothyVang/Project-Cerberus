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
    if (-not (Test-Path $MinioExe)) {
        Write-Log "[ERROR] MinIO Client (mc.exe) not found at: $MinioExe" "ERROR"
        return $false
    }

    if (-not (Test-Path $FilePath)) {
        Write-Log "[ERROR] File not found for upload: $FilePath" "ERROR"
        return $false
    }

    # File size validation
    if (Test-Path $FilePath -PathType Container) {
        $fileSize = (Get-ChildItem $FilePath -Recurse -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    } else {
        $fileSize = (Get-Item $FilePath).Length
    }
    $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
    Write-Log "[UPLOAD] File: $FilePath ($fileSizeMB MB)"

    # Network pre-check
    if (-not (Test-MinIOConnectivity -Server $MINIO_SERVER)) {
        Write-Log "[UPLOAD] Skipping upload due to network failure" "ERROR"
        Write-Log "[LOCAL] Evidence preserved at: $FilePath"
        return $false
    }

    Write-Log "[UPLOAD] Starting upload to minio\$UPLOAD_BUCKET..."

    # Configure MinIO host
    $env:MC_HOST_minio = "https://${ACCESS_KEY}:${SECRET_KEY}@${MINIO_SERVER}"

    # Upload with proper path separator
    if (Test-Path $FilePath -PathType Container) {
        & $MinioExe put -r "$FilePath" "minio\$UPLOAD_BUCKET" --insecure
    } else {
        & $MinioExe put "$FilePath" "minio\$UPLOAD_BUCKET" --insecure
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Log "[SUCCESS] Upload complete: $FilePath ($fileSizeMB MB)" "SUCCESS"
        return $true
    } else {
        Write-Log "[ERROR] Upload failed with exit code: $LASTEXITCODE" "ERROR"
        Write-Log "[ERROR] Check network: Can you reach $MINIO_SERVER ?" "ERROR"
        Write-Log "[ERROR] Check credentials in Cerberus_Config.json" "ERROR"
        Write-Log "[LOCAL] Evidence preserved at: $FilePath"
        return $false
    }
}

# =============================================================================
# MAIN LOGIC - Decides whether to scan or just upload
# =============================================================================
if ($UploadOnly) {
    # User passed -UploadOnly flag, so skip scanning and just upload existing files
    Write-Log "[MODE] Upload-Only Mode - Scanning for existing evidence..."

    # Scan Evidence folder for files matching this computer's name
    $EvidenceFiles = Get-ChildItem -Path $EvidenceDir -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $env:COMPUTERNAME -and -not $_.PSIsContainer }

    if ($EvidenceFiles) {
        $uploadCount = 0
        $failedCount = 0

        Write-Log "[UPLOAD] Found $($EvidenceFiles.Count) evidence files to upload"

        foreach ($File in $EvidenceFiles) {
            # Compress large files before upload
            if ($File.Extension -ne ".zip" -and $File.Length -gt 100MB) {
                Write-Log "[INFO] Large file detected: $($File.Name) - compressing before upload..."
                $ZipPath = "$($File.FullName).zip"

                try {
                    Compress-Archive -Path $File.FullName -DestinationPath $ZipPath -Force -ErrorAction Stop
                    $result = Upload-To-MinIO -FilePath $ZipPath
                    if ($result) { $uploadCount++ } else { $failedCount++ }
                } catch {
                    Write-Log "[ERROR] Failed to compress $($File.Name): $($_.Exception.Message)" "ERROR"
                    $failedCount++
                }
            } else {
                # Upload file as-is
                $result = Upload-To-MinIO -FilePath $File.FullName
                if ($result) { $uploadCount++ } else { $failedCount++ }
            }
        }

        Write-Log "[UPLOAD] Upload complete: $uploadCount succeeded, $failedCount failed"

        if ($failedCount -gt 0) {
            Write-Log "[WARN] Some uploads failed - check network connectivity and credentials" "WARNING"
            exit 1
        } else {
            Write-Log "[SUCCESS] All evidence uploaded successfully" "SUCCESS"
            exit 0
        }
    } else {
        Write-Log "[WARN] No evidence files found matching $env:COMPUTERNAME in $EvidenceDir" "WARNING"
        Write-Log "[INFO] Ensure evidence was collected before running -UploadOnly mode"
        exit 0  # Not an error, just nothing to upload
    }
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
                $failedComponents += "THOR-Timeout"
                break  # Exit monitoring loop but continue to upload phase
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

        if (-not (Test-Path $KapeExe)) {
            Write-Log "KAPE binary not found at $KapeExe" "ERROR"
            $scriptSuccess = $false
            $failedComponents += "KAPE-TRIAGE-Missing"
            # Skip KAPE execution but continue to upload phase
        } else {
            # Build arguments using config
            $KapeArgs = $Config.Tools.Kape.TriageArgs -replace "\$\{Output\}", "`"$KapeOutput`""

            Write-Log "[KAPE] Command: $KapeExe $KapeArgs"
            Write-Log "[KAPE] Output: $KapeOutput"
            Write-Log "[KAPE] Starting collection (15-30 minutes estimated)..."

        # Start process
        $kapeProcess = Start-Process -FilePath $KapeExe `
            -ArgumentList $KapeArgs `
            -PassThru -NoNewWindow

        # Monitor with timeout (24 hours)
        $timeout = 86400000  # 24 hours
        $startTime = Get-Date

        while (-not $kapeProcess.HasExited) {
            $elapsed = (Get-Date) - $startTime

            if ($elapsed.TotalMilliseconds -gt $timeout) {
                Write-Log "[KAPE] Timeout after 24 hours - killing process" "ERROR"
                $kapeProcess.Kill()
                Write-Log "[ERROR] KAPE collection timeout" "ERROR"
                $scriptSuccess = $false
                $failedComponents += "KAPE-TRIAGE-Timeout"
                break  # Exit monitoring loop but continue to upload phase
            }

            $exited = $kapeProcess.WaitForExit(60000)

            # Check output directory size as progress indicator
            if (Test-Path $KapeOutput) {
                $outputSize = (Get-ChildItem $KapeOutput -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                $sizeMB = [math]::Round($outputSize / 1MB, 2)
                $elapsedMin = [math]::Round($elapsed.TotalMinutes, 1)
                Write-Log "[KAPE] Progress: Collected $sizeMB MB (elapsed: $elapsedMin min)"
            } else {
                Write-Log "[KAPE] Running... (elapsed: $([math]::Round($elapsed.TotalMinutes, 1)) min)"
            }
        }

        $exitCode = $kapeProcess.ExitCode

        if ($exitCode -eq 0) {
            Write-Log "[KAPE] Triage collection completed successfully" "SUCCESS"
        } else {
            Write-Log "[ERROR] KAPE exited with code: $exitCode (may be partial collection)" "ERROR"
            $scriptSuccess = $false
            $failedComponents += "KAPE-TRIAGE"
        }

        Write-Log "KAPE Triage Finished."
        }  # End of else block for KAPE-TRIAGE execution
    }
    # =============================================================================
    # TOOL EXECUTION - KAPE RAM (Memory Capture)
    # =============================================================================
    elseif ($Tool -eq "KAPE-RAM") {
        Write-Log "Starting KAPE RAM Capture..."
        $KapeExe = "$BinDir\KAPE\kape.exe"
        $KapeOutput = "$EvidenceDir\$env:COMPUTERNAME-RAM"

        if (-not (Test-Path $KapeExe)) {
            Write-Log "KAPE binary not found at $KapeExe" "ERROR"
            $scriptSuccess = $false
            $failedComponents += "KAPE-RAM-Missing"
            # Skip KAPE-RAM execution but continue to upload phase
        } else {
            # Build arguments using config
            $RamArgs = $Config.Tools.Kape.RamArgs -replace "\$\{Output\}", "`"$KapeOutput`""

            Write-Log "[KAPE-RAM] Command: $KapeExe $RamArgs"
            Write-Log "[KAPE-RAM] Output: $KapeOutput"
            Write-Log "[KAPE-RAM] Starting memory capture (5-15 minutes estimated)..."

        # Start process
        $ramProcess = Start-Process -FilePath $KapeExe `
            -ArgumentList $RamArgs `
            -PassThru -NoNewWindow

        # Monitor with timeout (2 hours for RAM)
        $timeout = 7200000  # 2 hours
        $startTime = Get-Date

        while (-not $ramProcess.HasExited) {
            $elapsed = (Get-Date) - $startTime

            if ($elapsed.TotalMilliseconds -gt $timeout) {
                Write-Log "[KAPE-RAM] Timeout after 2 hours - killing process" "ERROR"
                $ramProcess.Kill()
                Write-Log "[ERROR] KAPE RAM timeout" "ERROR"
                $scriptSuccess = $false
                $failedComponents += "KAPE-RAM-Timeout"
                break  # Exit monitoring loop but continue to upload phase
            }

            $exited = $ramProcess.WaitForExit(60000)

            # Check output directory size
            if (Test-Path $KapeOutput) {
                $outputSize = (Get-ChildItem $KapeOutput -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                $sizeMB = [math]::Round($outputSize / 1MB, 2)
                $elapsedMin = [math]::Round($elapsed.TotalMinutes, 1)
                Write-Log "[KAPE-RAM] Progress: Captured $sizeMB MB (elapsed: $elapsedMin min)"
            } else {
                Write-Log "[KAPE-RAM] Running... (elapsed: $([math]::Round($elapsed.TotalMinutes, 1)) min)"
            }
        }

        $exitCode = $ramProcess.ExitCode

        if ($exitCode -eq 0) {
            Write-Log "[KAPE-RAM] Memory capture completed successfully" "SUCCESS"
        } else {
            Write-Log "[ERROR] KAPE RAM exited with code: $exitCode" "ERROR"
            $scriptSuccess = $false
            $failedComponents += "KAPE-RAM"
        }

        Write-Log "KAPE RAM Capture Finished."
        }  # End of else block for KAPE-RAM execution
    }
    # =============================================================================
    # TOOL EXECUTION - FTK IMAGER (Disk Imaging)
    # =============================================================================
    elseif ($Tool -eq "FTK") {
        Write-Log "Starting FTK Imager (Remote Mode)..."
        $FtkExe = "$BinDir\FTK\x64\ftkimager.exe"
        $FtkImageBase = "$EvidenceDir\$env:COMPUTERNAME-Disk"

        if (-not (Test-Path $FtkExe)) {
            Write-Log "FTK binary not found at $FtkExe" "ERROR"
            $scriptSuccess = $false
            $failedComponents += "FTK-Missing"
            # Skip FTK execution but continue to upload phase
        } else {
            # Get FTK arguments from config
            $FtkArgs = $Config.Tools.FTK.Args
            $FtkLogFile = "$EvidenceDir\$env:COMPUTERNAME-FTK.log"

            Write-Log "[FTK] Command: $FtkExe C: `"$FtkImageBase.raw`" $FtkArgs"
            Write-Log "[FTK] Output: $FtkImageBase.raw"
            Write-Log "[FTK] Starting disk imaging (this may take 2-8 hours)..."

        # Start process
        $ftkProcess = Start-Process -FilePath $FtkExe `
            -ArgumentList "C: `"$FtkImageBase.raw`" $FtkArgs" `
            -PassThru -NoNewWindow

        # Monitor with timeout (72 hours for large disks)
        $timeout = 259200000  # 72 hours
        $startTime = Get-Date
        $lastImageSize = 0

        while (-not $ftkProcess.HasExited) {
            $elapsed = (Get-Date) - $startTime

            if ($elapsed.TotalMilliseconds -gt $timeout) {
                Write-Log "[FTK] Timeout after 72 hours - killing process" "ERROR"
                $ftkProcess.Kill()
                Write-Log "[ERROR] FTK imaging timeout" "ERROR"
                $scriptSuccess = $false
                $failedComponents += "FTK-Timeout"
                break  # Exit monitoring loop but continue to upload phase
            }

            $exited = $ftkProcess.WaitForExit(60000)

            # Check image file size as progress indicator
            $imageFiles = Get-ChildItem "$EvidenceDir\$env:COMPUTERNAME-Disk.raw*" -ErrorAction SilentlyContinue
            if ($imageFiles) {
                $totalSize = ($imageFiles | Measure-Object -Property Length -Sum).Sum
                $sizeGB = [math]::Round($totalSize / 1GB, 2)
                $elapsedMin = [math]::Round($elapsed.TotalMinutes, 1)

                if ($totalSize -gt $lastImageSize) {
                    Write-Log "[FTK] Progress: Image $sizeGB GB (elapsed: $elapsedMin min)"
                    $lastImageSize = $totalSize
                } else {
                    Write-Log "[FTK] Still imaging... (elapsed: $elapsedMin min)"
                }
            } else {
                Write-Log "[FTK] Running... (elapsed: $([math]::Round($elapsed.TotalMinutes, 1)) min)"
            }
        }

        $exitCode = $ftkProcess.ExitCode

        if ($exitCode -eq 0) {
            Write-Log "[FTK] Disk imaging completed successfully" "SUCCESS"
        } else {
            Write-Log "[ERROR] FTK exited with code: $exitCode" "ERROR"
            $scriptSuccess = $false
            $failedComponents += "FTK"
        }

        Write-Log "FTK Acquisition Finished."
        }  # End of else block for FTK execution
    }
    
    # =============================================================================
    # AUTO-UPLOAD - Zip and upload evidence immediately after collection
    # =============================================================================
    Write-Log "`n[PHASE] Compressing and Uploading Evidence..."

    # Determine output folder and zip path based on tool
    $uploadSuccess = $false
    $evidenceFolder = $null
    $zipPath = $null

    if ($Tool -eq "THOR") {
        $evidenceFolder = "$EvidenceDir\$env:COMPUTERNAME-THOR"
        $zipPath = "$EvidenceDir\$env:COMPUTERNAME-THOR.zip"
    }
    elseif ($Tool -eq "KAPE-TRIAGE") {
        $evidenceFolder = "$EvidenceDir\$env:COMPUTERNAME-KAPE-Triage"
        $zipPath = "$EvidenceDir\$env:COMPUTERNAME-KAPE-Triage.zip"
    }
    elseif ($Tool -eq "KAPE-RAM") {
        $evidenceFolder = "$EvidenceDir\$env:COMPUTERNAME-RAM"
        $zipPath = "$EvidenceDir\$env:COMPUTERNAME-RAM.zip"
    }
    elseif ($Tool -eq "FTK") {
        # FTK creates individual files, not a folder - zip them all together
        Write-Log "[ZIP] Compressing FTK disk image files..."
        $ftkFiles = Get-ChildItem -Path "$EvidenceDir" -Filter "$env:COMPUTERNAME-Disk.*"

        if ($ftkFiles) {
            $zipPath = "$EvidenceDir\$env:COMPUTERNAME-FTK.zip"

            try {
                Compress-Archive -Path $ftkFiles.FullName -DestinationPath $zipPath -Force
                Write-Log "[ZIP] Created: $zipPath"

                # Upload the zip file
                $uploadSuccess = Upload-To-MinIO -FilePath $zipPath
            }
            catch {
                Write-Log "[ERROR] Failed to compress FTK files: $($_.Exception.Message)" "ERROR"
                $scriptSuccess = $false
                $failedComponents += "Compression"
            }
        }
    }

    # Zip folder-based evidence (THOR, KAPE-TRIAGE, KAPE-RAM)
    if ($evidenceFolder -and (Test-Path $evidenceFolder)) {
        Write-Log "[ZIP] Compressing folder: $evidenceFolder"

        try {
            # Calculate folder size before compression
            $folderSize = (Get-ChildItem $evidenceFolder -Recurse -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            $folderSizeMB = [math]::Round($folderSize / 1MB, 2)
            Write-Log "[ZIP] Original size: $folderSizeMB MB"

            # Compress the entire folder
            Compress-Archive -Path "$evidenceFolder\*" -DestinationPath $zipPath -Force

            # Check zip file size
            if (Test-Path $zipPath) {
                $zipSize = (Get-Item $zipPath).Length
                $zipSizeMB = [math]::Round($zipSize / 1MB, 2)
                $compressionRatio = [math]::Round(($zipSize / $folderSize) * 100, 1)
                Write-Log "[ZIP] Compressed to: $zipSizeMB MB ($compressionRatio% of original)" "SUCCESS"

                # Upload the zip file
                $uploadSuccess = Upload-To-MinIO -FilePath $zipPath
            }
            else {
                Write-Log "[ERROR] Zip file was not created: $zipPath" "ERROR"
                $scriptSuccess = $false
                $failedComponents += "Compression"
            }
        }
        catch {
            Write-Log "[ERROR] Failed to compress folder: $($_.Exception.Message)" "ERROR"
            $scriptSuccess = $false
            $failedComponents += "Compression"
        }
    }

    # Track upload failures
    if (-not $uploadSuccess) {
        Write-Log "[WARN] Evidence upload failed - files preserved locally" "WARNING"
        Write-Log "[LOCAL] Original evidence: $evidenceFolder" "WARNING"
        Write-Log "[LOCAL] Zip file: $zipPath" "WARNING"
        $scriptSuccess = $false
        $failedComponents += "Upload"
    }
    else {
        Write-Log "[SUCCESS] Evidence uploaded successfully - originals preserved locally" "SUCCESS"
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
    $uploadedCount = 0
    $failedCount = 0

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
            $result = Upload-To-MinIO -FilePath $ZipPath

            # Keep the original unzipped file locally (for persistence!)
            if ($result) { $uploadedCount++ } else { $failedCount++ }
        }
        else {
            # File is small or already zipped - upload as-is
            $result = Upload-To-MinIO -FilePath $File.FullName
            if ($result) { $uploadedCount++ } else { $failedCount++ }
        }
    }

    Write-Log "[UPLOAD] Uploaded $uploadedCount files, $failedCount failed"

    # Track failures for final exit code
    if ($failedCount -gt 0 -and $uploadedCount -eq 0) {
        # All uploads failed
        $scriptSuccess = $false
        if ("Upload" -notin $failedComponents) {
            $failedComponents += "Upload"
        }
    }
}
else {
    # No evidence files found - this might indicate a problem
    Write-Log "[WARN] No evidence files found matching $env:COMPUTERNAME in $EvidenceDir"
}

# =============================================================================
# FINAL STATUS REPORTING AND EXIT CODES
# =============================================================================
Write-Log "`n=========================================="

if ($scriptSuccess) {
    Write-Log "CERBERUS AGENT EXECUTION COMPLETE - SUCCESS" "SUCCESS"
    Write-Log "All operations completed successfully"
    Write-Log "Evidence collected and uploaded to MinIO"
    Write-Log "=========================================="
    exit 0
} else {
    Write-Log "CERBERUS AGENT EXECUTION COMPLETE - WITH ERRORS" "ERROR"
    Write-Log "Failed components: $($failedComponents -join ', ')" "ERROR"
    Write-Log "Check logs above for detailed error information" "ERROR"
    Write-Log "Evidence preserved locally in: $EvidenceDir" "ERROR"
    Write-Log "=========================================="
    exit 1
}

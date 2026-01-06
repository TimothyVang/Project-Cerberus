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
$ConfigPath = "$PSScriptRoot\Cerberus_Config.json"

if (Test-Path $ConfigPath) {
    try {
        $Config = Get-Content $ConfigPath | ConvertFrom-Json
        $MINIO_SERVER = $Config.MinIO.Server
        $ACCESS_KEY = $Config.MinIO.AccessKey
        $SECRET_KEY = $Config.MinIO.SecretKey
        $UPLOAD_BUCKET = $Config.MinIO.Bucket
        
        Write-Host "[INFO] Loaded Configuration from Cerberus_Config.json" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to parse Cerberus_Config.json: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "[ERROR] Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

# =============================================================================

# Paths (Relative to this script)
$ScriptRoot = $PSScriptRoot
$BinDir = "$ScriptRoot\Bin"
$EvidenceDir = "$ScriptRoot\Evidence"
$MinioExe = "$BinDir\MinIO\mc.exe"

# 1. Setup Environment
if (-not (Test-Path $EvidenceDir)) { New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null }

function Write-Log ($Message) {
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$Time] $Message" -ForegroundColor Cyan
}

function Upload-To-MinIO ($FilePath) {
    if (-not (Test-Path $MinioExe)) {
        Write-Log "[ERROR] MinIO Client (mc.exe) not found at: $MinioExe"
        return
    }

    Write-Log "[UPLOAD] Starting MinIO Upload for: $FilePath"

    # Configure MinIO Host (Environment Variable Method)
    $env:MC_HOST_cerberus = "https://${ACCESS_KEY}:${SECRET_KEY}@${MINIO_SERVER}"

    # Upload (use cp with recursive for directories, cp for files)
    if (Test-Path $FilePath -PathType Container) {
        & $MinioExe cp --recursive "$FilePath" "cerberus/$UPLOAD_BUCKET/" --insecure
    }
    else {
        & $MinioExe cp "$FilePath" "cerberus/$UPLOAD_BUCKET/" --insecure
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Log "[SUCCESS] Upload Complete: $FilePath"
    }
    else {
        Write-Log "[ERROR] Upload Failed for: $FilePath"
        Write-Log "  -> Check Network: Can you reach $env:MC_HOST_cerberus ?"
        Write-Log "  -> Check Config: Verify AccessKey/SecretKey in Cerberus_Config.json"
        Write-Log "  -> Local Copy Reserved: The file is safe in $FilePath"
    }
}

# 2. Main Logic
if ($UploadOnly) {
    Write-Log "Upload-Only mode selected. Skipping scan."
}
else {
    if ($Tool -eq "THOR") {
        Write-Log "Starting THOR Scan (Remote Mode)..."
        $ThorExe = "$BinDir\THOR\thor64-lite.exe"
        $ThorOutput = "$EvidenceDir\$env:COMPUTERNAME-THOR"
        
        if (-not (Test-Path $ThorExe)) { Write-Log "[ERROR] Thor binary not found at $ThorExe"; exit 1 }
        if (-not (Test-Path $ThorOutput)) { New-Item -ItemType Directory -Path $ThorOutput -Force | Out-Null }
        
        # Args from Config
        $ThorArgs = $Config.Tools.Thor.Args
        $ThorLogFile = "$ThorOutput\thor.txt"
        Start-Process -FilePath $ThorExe -ArgumentList "-l `"$ThorLogFile`" $ThorArgs" -Wait -NoNewWindow
        
        Write-Log "Thor Scan Finished."
    }
    elseif ($Tool -eq "KAPE-TRIAGE") {
        Write-Log "Starting KAPE Triage (Files/Artifacts)..."
        $KapeExe = "$BinDir\KAPE\kape.exe"
        $KapeOutput = "$EvidenceDir\$env:COMPUTERNAME-KAPE-Triage"
        
        if (-not (Test-Path $KapeExe)) { Write-Log "[ERROR] KAPE binary not found at $KapeExe"; exit 1 }
        
        # Args from Config (Replacing ${Output} placeholder)
        $KapeArgs = $Config.Tools.Kape.TriageArgs -replace "\$\{Output\}", "`"$KapeOutput`""
        
        Start-Process -FilePath $KapeExe -ArgumentList $KapeArgs -Wait -NoNewWindow
        Write-Log "KAPE Triage Finished."
    }
    elseif ($Tool -eq "KAPE-RAM") {
        Write-Log "Starting KAPE RAM Capture..."
        $KapeExe = "$BinDir\KAPE\kape.exe"
        $KapeOutput = "$EvidenceDir\$env:COMPUTERNAME-RAM"
        
        if (-not (Test-Path $KapeExe)) { Write-Log "[ERROR] KAPE binary not found at $KapeExe"; exit 1 }
        
        # Args from Config (Replacing ${Output} placeholder)
        $RamArgs = $Config.Tools.Kape.RamArgs -replace "\$\{Output\}", "`"$KapeOutput`""
        
        Start-Process -FilePath $KapeExe -ArgumentList $RamArgs -Wait -NoNewWindow
        
        Write-Log "KAPE RAM Capture Finished."
    }
    elseif ($Tool -eq "FTK") {
        Write-Log "Starting FTK Imager (Remote Mode)..."
        $FtkExe = "$BinDir\FTK\x64\ftkimager.exe"
        $FtkImageBase = "$EvidenceDir\$env:COMPUTERNAME-Disk"

        if (-not (Test-Path $FtkExe)) { Write-Log "[ERROR] FTK binary not found at $FtkExe"; exit 1 }
        
        # Args from Config
        $FtkArgs = $Config.Tools.FTK.Args
        $LogFile = "$EvidenceDir\$env:COMPUTERNAME-FTK.log"
        
        Write-Log "[INFO] Acquiring PhysicalDrive0 to $FtkImageBase.E01..."
        Start-Process -FilePath $FtkExe -ArgumentList "\\.\PhysicalDrive0 `"$FtkImageBase`" $FtkArgs" -Wait -NoNewWindow
        
        Write-Log "FTK Acquisition Finished."
    }
    
    # [AUTO-UPLOAD]
    # Attempt to upload the results immediately.
    Write-Log "`n[PHASE] Auto-Uploading Evidence..."
    
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
        # Upload all E01 segments and logs
        Get-ChildItem -Path "$EvidenceDir" -Filter "$env:COMPUTERNAME-Disk.*" | ForEach-Object {
            Upload-To-MinIO -FilePath $_.FullName
        }
        Upload-To-MinIO -FilePath "$EvidenceDir\$env:COMPUTERNAME-FTK.log"
    }
}

# 3. Upload Phase
# We upload everything in the Evidence directory that matches the hostname
Write-Log "Scanning for evidence to upload..."
$EvidenceFiles = Get-ChildItem -Path $EvidenceDir -Recurse | Where-Object { $_.Name -match $env:COMPUTERNAME -and -not $_.PSIsContainer }

if ($EvidenceFiles) {
    foreach ($File in $EvidenceFiles) {
        # Zip huge folders if needed logic could go here, but Thor usually outputs manageable files or we upload individually
        if ($File.Extension -ne ".zip" -and $File.Length -gt 100MB) {
            Write-Log "[INFO] Large file detected: $($File.Name). Attempting to Zip before upload..."
            $ZipPath = "$($File.FullName).zip"
            Compress-Archive -Path $File.FullName -DestinationPath $ZipPath -Force
            Upload-To-MinIO -FilePath $ZipPath
            # We keep the original for persistence!
        }
        else {
            Upload-To-MinIO -FilePath $File.FullName
        }
    }
}
else {
    Write-Log "[WARN] No evidence files found matching $env:COMPUTERNAME in $EvidenceDir"
}

Write-Log "Cerberus Agent Execution Complete."

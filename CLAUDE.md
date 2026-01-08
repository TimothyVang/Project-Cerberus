# CLAUDE.md
**Project Cerberus Developer Documentation v2.2 - Updated January 2026**

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Project Cerberus is a unified Digital Forensics & Incident Response (DFIR) triage toolkit designed for dual operational modes:

1. **USB/Local Deployment**: Interactive batch-based launcher for on-site forensic collection
2. **Remote Deployment**: PowerShell agent for network-wide collection via Elastic Defend/Security Onion with MinIO upload

The kit integrates multiple forensic tools (KAPE, THOR, FTK Imager) with automated evidence collection, organization, and remote upload capabilities.

## Architecture

### Dual-Mode Design Pattern

The kit uses a **bifurcated execution model**:

- **Cerberus_Launcher.bat**: Batch-based TUI for USB/local scenarios. Uses `setlocal EnableDelayedExpansion` for dynamic variable handling and provides menu-driven interface with legacy system support (XP/2003)
- **Cerberus_Agent.ps1**: PowerShell-based headless agent for remote execution via Kibana/Elastic. Handles tool orchestration and MinIO uploads using environment variable authentication

### Configuration System

- **_settings.bat**: Local configuration for batch launcher (KAPE targets, THOR args, FTK compression settings)
- **Cerberus_Config.json**: Remote agent configuration containing MinIO credentials and tool arguments. Uses placeholder substitution pattern (`${Output}` replaced at runtime)

### Directory Structure
```
Bin/                   # Tool binaries (FTK, KAPE, THOR, MinIO)
  ├── FTK/            # x64 and x86 subdirectories for modern/legacy support
  ├── KAPE/           # kape.exe and modules
  ├── THOR/           # thor64-lite.exe and signatures
  └── MinIO/          # mc.exe (MinIO client)
Evidence/             # Output directory (auto-created per hostname)
Logs/                 # Operation logs
```

### Tool Execution Patterns

**KAPE** (Kroll Artifact Parser and Extractor):
- Targets specified via `--target` flag using escaped exclamation marks (`^!`) in batch
- Default targets: `!SANS_Triage,IISLogFiles,Exchange,ExchangeCve-2021-26855,MemoryFiles,MOF,BITS`
  - `!SANS_Triage`: Registry hives, Event Logs, Prefetch, SRUM, MFT, USN Journal
  - `IISLogFiles`: Web server logs
  - `Exchange`: Email server artifacts
  - `ExchangeCve-2021-26855`: ProxyLogon vulnerability indicators
  - `MemoryFiles`: Pagefile, hiberfil.sys, swapfile.sys
  - `MOF`: WMI persistence artifacts
  - `BITS`: Background Intelligent Transfer Service logs
- Module parsing via `--module ^!EZParser`
- Remote mode adds `--vhdx TargetsOutput_%m` (VHDX container named with current month)
- Password protection via `--zpw NWY0ZGNjM2I1YWE3NjVkNjFkODMyN2RlYjg4MmNmOTk=` (Base64-encoded password)
- RAM capture uses `--module MagnetForensics_RAMCapture` with `--zm true` (zip module output)

**Batch vs PowerShell invocation examples:**
```batch
# Batch THOR (Cerberus_Launcher.bat)
thor64-lite.exe --logfile "%EVIDENCE%\%COMPUTERNAME%_THOR\%COMPUTERNAME%.txt" --htmlfile "%EVIDENCE%\%COMPUTERNAME%_THOR\%COMPUTERNAME%.html" --utc --nothordb
```
```powershell
# PowerShell THOR (Cerberus_Agent.ps1 line 348-350)
Start-Process -FilePath $ThorExe -ArgumentList "--logfile `"$ThorLogFile`" --htmlfile `"$ThorHtmlFile`" $ThorArgs" -Wait -NoNewWindow
```

**THOR** (Threat Hunting Scanner):
- Arguments: `--utc --nothordb` (removed `--nocsv` to enable CSV output)
  - `--utc`: Timestamps in UTC
  - `--nothordb`: Skip ThorDB online lookup (offline mode)
- **Output flags**:
  - `--logfile "path\to\thor.txt"` - Text log output (required)
  - `--htmlfile "path\to\thor.html"` - HTML report output (recommended)
  - ⚠️ NOT `--output` (unsupported flag)
- Uses `start /wait` in batch for synchronous execution
- Remote mode uses `Start-Process -Wait -NoNewWindow`
- Output directory contains: `COMPUTERNAME.txt`, `COMPUTERNAME.html`, CSV files, and summary reports

**FTK Imager**:
- Target: `C:` (logical drive imaging)
- Output: RAW format (dd-style raw disk image) with:
  - `--compress 9`: Maximum compression level (saves storage space on large images)
  - `--frag 1TB`: Split into 1TB chunks (e.g., `image.raw`, `image.raw.001`, etc.)
  - ⚠️ No verification flag (not used in production deployments)
- Legacy mode (x86) uses `start /low` to reduce CPU priority and prevent system crashes on fragile kernels
- Memory capture uses `--capture-memory <path>` with `--compress 1` (minimal compression for speed)
- Example: `ftkimager.exe C: "Evidence\HOSTNAME_Disk.raw" --compress 9 --frag 1TB`

### MinIO Upload Architecture

The agent uses **environment variable authentication** pattern (Cerberus_Agent.ps1:208-215):
```powershell
$env:MC_HOST_minio = "https://${ACCESS_KEY}:${SECRET_KEY}@${MINIO_SERVER}"

# For directories
& $MinioExe put -r "$FilePath" "minio\$UPLOAD_BUCKET" --insecure

# For files
& $MinioExe put "$FilePath" "minio\$UPLOAD_BUCKET" --insecure
```
⚠️ **Note:** Agent uses `mc put -r` for directories and `mc put` for files. Path uses backslash format (`minio\bucket`) for Windows compatibility.

**Upload Logic Flow:**
1. Tool execution completes and saves to `Evidence\<hostname>-<tool>`
2. **Primary compression phase** (lines 626-715):
   - Entire evidence folder is compressed to .zip file
   - Zip file is uploaded to MinIO automatically
   - Original folder is preserved locally
3. **Fallback upload scan** (lines 720-770):
   - Scans for any remaining files matching `$env:COMPUTERNAME` pattern
   - Files >100MB are zipped before upload
   - Small files uploaded as-is
4. **Forensic preservation**:
   - Original evidence is **NEVER auto-deleted**
   - Both original folder and zip remain on disk
   - Upload failures are logged but don't trigger cleanup
5. Failed uploads can be retried with `-UploadOnly` switch without re-collecting

**Error Handling:**
- Exit code checked via `$LASTEXITCODE -eq 0` (line 217)
- Network pre-check with `Test-MinIOConnectivity` function (lines 136-168)
- Network failures log troubleshooting hints (lines 222-224):
  - Can you reach the MinIO server?
  - Are credentials correct in `Cerberus_Config.json`?
  - Evidence preserved locally in Evidence folder
- Script tracks failed components and returns appropriate exit codes (0=success, 1=failure)

## Common Commands

### Local/USB Mode
```cmd
# Run the launcher (requires administrator)
Cerberus_Launcher.bat

# Edit local settings (KAPE targets, tool args)
notepad _settings.bat
```

### Remote Mode (Elastic Defend)

**Deploy via Elastic Response Console:**
```bash
# Upload kit
upload --file "Project_Cerberus.zip"

# Extract to deployment path
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Project_Cerberus.zip' -DestinationPath 'C:\ProgramData\Google'"
```

**Execute tools:**
```bash
# THOR malware scan (24h timeout)
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus\Cerberus_Agent.ps1\" -Tool THOR" --timeout 86400s

# KAPE triage collection (1h timeout)
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus\Cerberus_Agent.ps1\" -Tool KAPE-TRIAGE" --timeout 3600s

# KAPE RAM capture
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus\Cerberus_Agent.ps1\" -Tool KAPE-RAM" --timeout 3600s

# FTK disk imaging (48h timeout)
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus\Cerberus_Agent.ps1\" -Tool FTK" --timeout 172800s

# Upload-only mode (retry failed uploads)
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus\Cerberus_Agent.ps1\" -UploadOnly" --timeout 7200s
```

## Configuration

### Editing MinIO Credentials
Edit `Cerberus_Config.json`:
```json
{
    "MinIO": {
        "Server": "your-server:8443",
        "AccessKey": "your-access-key",
        "SecretKey": "your-secret-key",
        "Bucket": "upload"
    }
}
```

### Modifying Tool Arguments

**For Local Mode**: Edit `_settings.bat`
```batch
set "KAPE_TARGETS=^!SANS_Triage,IISLogFiles,Exchange"
set "THOR_ARGS=--utc --nothordb"
set "FTK_ARGS=--compress 9 --frag 1TB"
```
⚠️ Note: `--nocsv` has been removed to enable CSV output generation

**For Remote Mode**: Edit `Cerberus_Config.json` → `Tools` section

## Important Implementation Details

### Batch Scripting Quirks

**Critical Escaping Patterns:**
- `^!` escapes exclamation marks in `EnableDelayedExpansion` context (batch scripts)
  - Without escape: `!SANS_Triage` would be interpreted as variable expansion
  - With escape: `^!SANS_Triage` passes literal `!SANS_Triage` to KAPE
  - Example in `_settings.bat` line 32: `set "SANS_Triage=!SANS_Triage,IISLogFiles..."`
- `%~dp0` expands to script's directory with trailing backslash (Cerberus_Launcher.bat line 26)
  - Example: `E:\Project_Cerberus\`
- Double quotes required around paths with spaces: `"%BIN%\KAPE\kape.exe"`

**Privilege & Process Control:**
- `net session >nul 2>&1` tests for administrator rights (line 7)
  - Redirects both stdout and stderr to avoid console spam
  - Exit code 0 = admin, non-zero = needs elevation
- `start /wait` for synchronous execution (waits for process to complete)
- `start /low` for low CPU priority on legacy systems
- `start /wait "" "path"` - empty string (`""`) is required window title parameter

**Menu System:**
- Uses `set /p` for user input
- `if /I` for case-insensitive comparison
- `goto :LABEL` for navigation between menu states
- `cls` clears screen between menu transitions
- `pause >nul` waits for keypress without "Press any key..." message

### PowerShell Agent Pattern

**Parameter Validation (lines 9-15):**
```powershell
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("THOR", "KAPE-TRIAGE", "KAPE-RAM", "FTK")]
    [string]$Tool = "THOR",
    [switch]$UploadOnly
)
```
- `[ValidateSet()]` ensures only valid tool names accepted
- Defaults to THOR if no parameter provided
- `-UploadOnly` switch skips collection and only uploads existing evidence

**Configuration Loading (lines 21-65):**
```powershell
$Config = Get-Content $ConfigPath | ConvertFrom-Json
$MINIO_SERVER = $Config.MinIO.Server
$ACCESS_KEY = $Config.MinIO.AccessKey
```
- JSON parsed into PowerShell object (line 28)
- Dot notation accesses nested properties (lines 32-35)
- Validates credentials are not default/empty values (lines 41-57)
- Try-catch handles malformed JSON gracefully (lines 25-64)

**Dynamic Argument Substitution:**
```powershell
# Pattern in JSON: "${Output}"
# Replacement at runtime (line 422 for KAPE-TRIAGE, line 491 for KAPE-RAM):
$KapeArgs = $Config.Tools.Kape.TriageArgs -replace "\$\{Output\}", "`"$KapeOutput`""
```
- Allows JSON to contain placeholders for runtime values
- Escaped regex pattern: `\$\{Output\}` matches literal `${Output}`
- Replacement includes quotes around path for space handling

**Process Execution:**
```powershell
Start-Process -FilePath $ThorExe -ArgumentList $args -Wait -NoNewWindow
```
- `-Wait`: Blocks until completion (synchronous)
- `-NoNewWindow`: Redirects output to current console (required for Kibana)
- Exit codes accessible via `$LASTEXITCODE` after completion

**Environment Variable Auth:**
- No temporary credential files created (opsec consideration)
- Credentials only in memory: `$env:MC_HOST_minio = "https://..."`
- Cleared when PowerShell session ends

### Evidence Preservation & Naming

**Naming Convention Differences:**
- Batch launcher: `%COMPUTERNAME%_<TOOL>` (underscore separator)
  - Examples: `DESKTOP-ABC123_KAPE`, `DESKTOP-ABC123_THOR`, `DESKTOP-ABC123_Disk`
- PowerShell agent: `$env:COMPUTERNAME-<TOOL>` (hyphen separator)
  - Examples: `DESKTOP-ABC123-THOR`, `DESKTOP-ABC123-KAPE-Triage`, `DESKTOP-ABC123-RAM`

**Output Structure:**
```
Evidence/
├── HOSTNAME_KAPE/              # Local batch collection
│   ├── C/                      # Collected artifacts from C:
│   └── Modules/                # Parsed output from !EZParser
├── HOSTNAME-KAPE-Triage/       # Remote agent collection
│   ├── TargetsOutput_01.vhdx   # VHDX container (remote mode only)
│   └── *.zip                   # Password-protected zip
├── HOSTNAME-THOR/
│   ├── thor.txt                # Main scan log
│   └── thor-summary.txt        # Summary report
├── HOSTNAME-Disk.raw           # RAW disk image (or first segment if >1TB)
├── HOSTNAME-Disk.raw.001       # Additional segment (if >1TB)
└── HOSTNAME-FTK.log            # FTK acquisition log
```

**Forensic Integrity Rules:**
- Evidence is **NEVER** auto-deleted (fail-safe design)
- Upload failures don't trigger cleanup
- Large files compressed **in addition to** (not instead of) originals
- RAW format disk images with maximum compression for storage efficiency

### Legacy System Support
- Uses x86 binaries from `Bin\FTK\x86` for Windows XP/2003/2008
- Avoids PowerShell dependencies in legacy mode
- `/low` priority prevents CPU/kernel stress on fragile systems

## Security Considerations

This is a **forensic toolkit** for authorized incident response and security testing. When modifying:
- Do NOT commit credentials (MinIO keys are already in .gitignore)
- Do NOT modify evidence handling logic without forensic validation
- Verify tool signatures before deployment
- Use TLS/HTTPS for MinIO uploads (`--insecure` flag is for self-signed certs only)

## Typical Workflow

1. **Preparation**: Configure `Cerberus_Config.json` with MinIO server and credentials
2. **Deployment**:
   - Local: Copy kit to USB, run `Cerberus_Launcher.bat` as administrator
   - Remote: Upload zip via Elastic, extract to `C:\ProgramData\Google`, execute agent with `-Tool` parameter
3. **Collection**: Tools execute and save to `Evidence\<hostname>_<tool>`
4. **Upload** (remote only): Agent automatically uploads to MinIO
5. **Verification**: Check `Logs\` directory or Elastic response console output

## Troubleshooting

**"Target EZParser not found" (KAPE):**
- Caused by incorrect escaping of `!` in batch context
- Fix: Ensure `^!EZParser` is used (caret escape before exclamation)
- Already fixed in current version

**MinIO Upload Failures:**
1. Test network connectivity: `ping <minio-server>`
2. Verify credentials in `Cerberus_Config.json` match MinIO server
3. Check Elastic agent network policies (may block outbound HTTPS)
4. Use `-UploadOnly` switch to retry without re-collecting evidence
5. Evidence always preserved locally at `Evidence\<hostname>-<tool>`

**FTK Crashes on Legacy Systems:**
- Ensure using Legacy Mode (Option 2) which uses x86 binaries
- Legacy mode automatically uses `/low` priority
- Avoid modern mode on XP/2003 - will use x64 binaries that crash

**KAPE VHDX Password:**
- Default password: Base64-decode `NWY0ZGNjM2I1YWE3NjVkNjFkODMyN2RlYjg4MmNmOTk=`
- Change in `Cerberus_Config.json` → `Tools.Kape.TriageArgs` → `--zpw` value
- Password protects VHDX container to prevent tampering during upload

**Administrator Rights Required:**
- Batch launcher checks via `net session` command (Cerberus_Launcher.bat line 7)
- Required for logical drive imaging (`C:`)
- Required for memory acquisition
- Required for VSS (Volume Shadow Copy) access by KAPE

## Code Modification Patterns

**Adding a New Tool:**
1. Place binary in `Bin\<ToolName>\`
2. Add menu option in `Cerberus_Launcher.bat` MODERN_MODE or LEGACY_MODE sections
3. Add case to `Cerberus_Agent.ps1` elseif chain (lines 322-621 for execution, lines 633-666 for compression)
4. Add tool arguments to `Cerberus_Config.json` → `Tools` section
5. Add upload logic in auto-upload section (lines 626-716)
6. Follow evidence naming convention: `$env:COMPUTERNAME-<TOOLNAME>`

**Changing KAPE Targets:**
- Local mode: Edit `_settings.bat` line 32 (variable: `SANS_Triage`)
- Remote mode: Edit `Cerberus_Config.json` → `Tools.Kape.TriageArgs`
- Use comma-separated list without spaces: `!Target1,Target2,Target3`
- Prefix compound targets with `!` (KAPE notation for target files)

**Modifying MinIO Upload Destination:**
- Change bucket: `Cerberus_Config.json` → `MinIO.Bucket`
- Change server: `Cerberus_Config.json` → `MinIO.Server` (format: `host:port`)
- Upload path format: `minio\<bucket-name>` (line 212, 214) where "minio" is the configured alias

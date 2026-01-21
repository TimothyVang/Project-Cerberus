# PROJECT CERBERUS: STANDARD OPERATING PROCEDURE

**Unified Digital Forensics & Incident Response Toolkit**

---

| Field | Value |
|-------|-------|
| **Document Type** | Standard Operating Procedure |
| **Version** | 1.0 |
| **Author** | PUG |
| **Date** | January 2026 |
| **Classification** | Unclassified |
| **Scope** | Windows Endpoint Forensic Collection |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Pre-Mission Checklist](#2-pre-mission-checklist)
3. [Kit Preparation](#3-kit-preparation)
4. [MODE 1: USB/Local Deployment](#4-mode-1-usblocal-deployment)
5. [MODE 2: Remote Deployment (Elastic Defend)](#5-mode-2-remote-deployment-elastic-defend)
6. [Tool-Specific Procedures](#6-tool-specific-procedures)
7. [Evidence Handling](#7-evidence-handling)
8. [Manual Fallback Operations](#8-manual-fallback-operations)
9. [Cleanup Procedures](#9-cleanup-procedures)
10. [Troubleshooting Guide](#10-troubleshooting-guide)
11. [Quick Reference](#11-quick-reference)
12. [Appendices](#12-appendices)
13. [Revision History](#13-revision-history)

---

## 1. Executive Summary

### 1.1 What is Project Cerberus?

Project Cerberus is a unified Digital Forensics and Incident Response (DFIR) toolkit designed to streamline evidence collection from Windows endpoints. It integrates three industry-standard forensic tools into a single, operator-friendly package:

| Tool | Purpose | Output |
|------|---------|--------|
| **THOR Lite** | Malware/APT scanning, IOC detection | HTML report + text log |
| **KAPE** | Forensic artifact collection (Registry, logs, MFT) | VHDX container + zip |
| **FTK Imager** | Full disk imaging, memory capture | RAW disk image |

### 1.2 Operational Modes

Project Cerberus supports two deployment methods:

| Mode | Use Case | Method |
|------|----------|--------|
| **MODE 1: USB/Local** | Physical access to endpoint, air-gapped networks | `Cerberus_Launcher.bat` (TUI) |
| **MODE 2: Remote/Elastic** | Network-wide collection via Security Onion / Elastic Defend | `Cerberus.ps1` via Response Actions |

### 1.3 Key Features

- **Unified Interface**: One toolkit for all forensic collection needs
- **Automatic Upload**: Evidence automatically uploads to MinIO server
- **Heartbeat Monitoring**: Prevents Elastic timeout during long scans
- **Pre-flight Checks**: Validates disk space before collection
- **Consistent Naming**: Output files follow `HOSTNAME-DOMAIN-TOOL.zip` convention

### 1.4 Directory Structure

```
Project_Cerberus/
├── Bin/                      # Tool binaries
│   ├── KAPE/                 # KAPE executable + targets/modules
│   ├── THOR/                 # THOR Lite scanner + signatures
│   ├── FTK/                  # FTK Imager (x64 and x86)
│   └── MinIO/                # MinIO client (mc.exe)
├── Evidence/                 # Collection output (auto-created)
├── Logs/                     # Operation logs
├── Lib/                      # Shared PowerShell modules
├── Splits/                   # Pre-split packages for Elastic upload
├── Cerberus_Launcher.bat     # USB/Local launcher (TUI)
├── Cerberus.ps1              # Remote entry point
├── Cerberus_Config.json      # Configuration file (EDIT THIS)
├── Run-Thor.ps1              # THOR execution script
├── Run-KapeDisk.ps1          # KAPE disk collection
├── Run-KapeRam.ps1           # KAPE RAM capture
├── Run-KapeCombined.ps1      # RAM + Disk (forensically correct order)
├── Run-Ftk.ps1               # FTK disk imaging
└── Run-UploadOnly.ps1        # Retry failed uploads
```

---

## 2. Pre-Mission Checklist

Complete all items before deploying Project Cerberus to a mission partner network.

### 2.1 Kit Acquisition

- [ ] Obtain latest THOR Lite package from MEL
- [ ] Obtain valid THOR Lite license file (`.lic`)
- [ ] Obtain current YARA rules (e.g., CrowdStrike ruleset)
- [ ] Obtain MinIO credentials from Kit personnel

### 2.2 Kit Configuration

- [ ] Encrypt YARA rules using `thor-util.exe` (produces `.yas` file)
- [ ] Place encrypted rules in `Bin\THOR\signatures\yara\`
- [ ] Copy license file to `Bin\THOR\`
- [ ] Edit `Cerberus_Config.json` with MinIO credentials
- [ ] Verify all tool binaries exist in `Bin\` folders

### 2.3 Pre-Deployment Verification

- [ ] Test kit on isolated/lab system before deployment
- [ ] Verify THOR scan completes without license errors
- [ ] Verify KAPE collection produces expected artifacts
- [ ] Verify MinIO upload succeeds (if network available)
- [ ] Create split packages for Elastic deployment (if applicable)

### 2.4 Documentation

- [ ] Document mission-specific MinIO server IP and port
- [ ] Document any custom KAPE targets required
- [ ] Confirm cleanup procedures with mission lead

### 2.5 Disk Space Requirements

Ensure sufficient free space on target system and evidence storage:

| Tool | Target System | Evidence Output | Notes |
|------|---------------|-----------------|-------|
| **THOR Lite** | ~500 MB | 10-100 MB | Log + HTML report only |
| **KAPE Disk** | ~2 GB temp | 500 MB - 5 GB | VHDX compressed output |
| **KAPE RAM** | ~2x RAM | RAM size + 10% | Requires temp space = RAM |
| **KAPE Combined** | ~2x RAM + 2 GB | RAM + 5 GB | RAM captured first |
| **FTK Disk Image** | Minimal | **50-100% of source** | RAW image = disk size |
| **FTK Memory** | Minimal | RAM size | Compressed ~50% |

**Minimum Recommendations:**

| Scenario | Target System Free Space | Evidence Drive |
|----------|--------------------------|----------------|
| THOR only | 1 GB | 500 MB |
| KAPE triage | 5 GB | 10 GB |
| Full collection (KAPE + THOR) | 10 GB | 20 GB |
| FTK disk image | 2 GB | **Equal to source disk** |

> **Warning**: FTK disk imaging requires an external drive with capacity equal to or greater than the source disk. Never save disk images to the drive being imaged.

---

## 3. Kit Preparation

This section describes how to build a valid Project Cerberus kit from scratch.

### 3.1 Phase 1: Acquire Components from MEL

Contact your **Mission Element Lead (MEL)** to obtain:

| Component | Description | Example Filename |
|-----------|-------------|------------------|
| THOR Lite Package | Scanner executable + base signatures | `thor10.7lite-win-pack.zip` |
| License File | Activation file for THOR | `thor-lite-XXXXXX-XXXXXX.lic` |
| YARA Rules | Custom threat signatures | `CrowdStrike_Rules_Jan2026.yar` |
| MinIO Credentials | Server IP, access key, secret key | (provided verbally or secure channel) |

> **Reference**: [THOR Lite Download](https://www.nextron-systems.com/thor-lite/)

### 3.2 Phase 2: Build the THOR Package

#### Step 1: Extract THOR Lite

```
1. Unzip thor10.7lite-win-pack.zip to temporary folder (e.g., C:\Temp\thor)
2. Verify thor64-lite.exe exists in extracted folder
```

#### Step 2: Install License

```
1. Copy the .lic file to C:\Temp\thor\
2. Verify only ONE license file exists in that folder
```

#### Step 3: Encrypt YARA Rules (CRITICAL)

THOR Lite cannot read raw `.yar` files. You must encrypt them to `.yas` format.

**Option A: Command Line (Recommended)**

```cmd
cd C:\Temp\thor\
thor-util.exe encrypt -f "CrowdStrike_Rules.yar" -o "signatures\yara\CrowdStrike_Rules.yas"
```

**Option B: GUI**

```
1. Navigate to C:\Temp\thor\
2. Launch thor-util.exe (GUI application)
3. Select "Encrypt / Convert" option
4. Input File:  Browse to your YARA rules (e.g., CrowdStrike_Rules.yar)
5. Output File: Save as signatures\yara\CrowdStrike_Rules.yas
6. Click Convert
7. Verify the .yas file exists and is larger than 0 KB
```

#### Step 4: Integrate into Project Cerberus

```
1. Navigate to Project_Cerberus\Bin\THOR\
2. Delete any existing files (if outdated)
3. Copy ALL contents from C:\Temp\thor\ to Bin\THOR\
4. Verify:
   - Bin\THOR\thor64-lite.exe exists
   - Bin\THOR\*.lic exists
   - Bin\THOR\signatures\yara\*.yas exists
```

> **Reference**: [THOR Manual - Custom Signatures](https://thor-manual.nextron-systems.com/en/latest/usage/custom-signatures.html)

### 3.3 Phase 3: Configure Cerberus_Config.json

Edit `Cerberus_Config.json` with your mission-specific values:

```json
{
    "MinIO": {
        "Server": "<KIT_IP>:<PORT>",
        "AccessKey": "<ACCESS_KEY>",
        "SecretKey": "<SECRET_KEY>",
        "Bucket": "upload"
    },
    "Paths": {
        "EvidenceRoot": "${ScriptRoot}\\Evidence",
        "FTK": ""
    },
    "Tools": {
        "Thor": {
            "Args": "--utc --nothordb"
        },
        "Kape": {
            "DiskArgs": "--tsource C: --tdest ${Output} --tflush --target !SANS_Triage,IISLogFiles,Exchange,ExchangeCve-2021-26855,MemoryFiles,MOF,BITS --ifw --vhdx TargetsOutput_%m",
            "RamArgs": "--msource C:\\ --mdest ${Output} --zm true --module MagnetForensics_RAMCapture"
        },
        "FTK": {
            "Args": "--compress 9 --frag 1TB"
        }
    }
}
```

**Configuration Fields:**

| Field | Description | Example |
|-------|-------------|---------|
| `MinIO.Server` | MinIO server IP and port | `192.168.1.50:8443` |
| `MinIO.AccessKey` | MinIO access key | `transfer-external` |
| `MinIO.SecretKey` | MinIO secret key | `TDtBW8ohsN...` |
| `MinIO.Bucket` | Target bucket name | `upload` |
| `Paths.FTK` | External drive path for FTK images | `E:\Evidence` |

### 3.4 Phase 4: Create Split Packages (For Elastic Deployment)

Elastic Defend has a **25MB upload limit**. Split the kit into parts:

| Part | Contents | Approximate Size |
|------|----------|------------------|
| `Part1_Core.zip` | Scripts, Lib, Config | ~50 KB |
| `Part2_FTK.zip` | Bin/FTK | ~4.2 MB |
| `Part3_MinIO.zip` | Bin/MinIO | ~11 MB |
| `Part4_KAPE.zip` | Bin/KAPE | ~24 MB |
| `Part5_THOR_Sigs.zip` | THOR signatures & config | ~8.4 MB |
| `Part6_THOR_Exe.zip` | THOR executable | ~16 MB |

Pre-split packages are available in the `Splits/` folder.

### 3.5 Phase 5: Verification

Run these checks before deployment:

```powershell
# Verify THOR
.\Bin\THOR\thor64-lite.exe --version

# Verify KAPE  
.\Bin\KAPE\kape.exe --help

# Verify FTK
.\Bin\FTK\x64\ftkimager.exe --help

# Verify MinIO client
.\Bin\MinIO\mc.exe --version
```

---

## 4. MODE 1: USB/Local Deployment

Use this mode when you have **physical access** to the endpoint or are working on an **air-gapped network**.

### 4.1 Prerequisites

- Administrator privileges on target system
- USB drive with Project Cerberus folder (SSD recommended for speed)
- Sufficient free space on USB for collected evidence

### 4.2 Launch Procedure

```
1. Plug USB into target machine
2. Navigate to Project_Cerberus folder on USB
3. Right-click Cerberus_Launcher.bat
4. Select "Run as Administrator"
```

### 4.3 Main Menu

The TUI displays:

```
+-----------------------------------------------------------------------+
|                   WELCOME TO PROJECT CERBERUS                         |
|                        DFIR TRIAGE TOOLKIT                            |
+-----------------------------------------------------------------------+

WHAT IS YOUR OPERATING SYSTEM?

[1] MODERN System (Windows 10, 11, Server 2012 or newer)
[2] LEGACY System (Windows XP, Server 2003, Server 2008, Vista)
[Q] Quit
```

### 4.4 Modern Mode Options

After selecting `[1] MODERN`:

| Option | Tool | Description | Duration |
|--------|------|-------------|----------|
| `[1]` | KAPE | Quick artifact collection (Registry, logs, prefetch) | 15-30 min |
| `[2]` | THOR | Malware/APT scanning | 1-4 hours |
| `[3]` | FTK | Full disk or memory imaging | 2-8 hours |

#### KAPE Sub-Menu

| Option | Collection Type | Description |
|--------|-----------------|-------------|
| `[1]` | Full Collection | SANS_Triage + IIS + Exchange + Memory + MOF + BITS |
| `[2]` | Disk-Only | SANS_Triage (excludes memory files - smaller output) |
| `[3]` | RAM Capture | Memory dump using Magnet RAM Capture |

#### FTK Sub-Menu

| Option | Type | Description |
|--------|------|-------------|
| `[1]` | Disk Image | Bit-for-bit copy of C: drive (RAW format) |
| `[2]` | Memory Dump | Snapshot of RAM memory |

### 4.5 Legacy Mode

For Windows XP, Server 2003, Server 2008, Vista:

- Uses 32-bit (x86) binaries
- Runs at LOW CPU priority to prevent system crashes
- Limited to FTK Imager operations (no KAPE, no THOR)

### 4.6 Evidence Location

All evidence is saved to:

```
USB:\Project_Cerberus\Evidence\<COMPUTERNAME>\
```

### 4.7 Post-Collection

1. Wait for "SUCCESS" message
2. Verify evidence files exist in `Evidence\` folder
3. Safely eject USB drive
4. Transport evidence per chain of custody procedures

---

## 5. MODE 2: Remote Deployment (Elastic Defend)

Use this mode for **network-wide collection** via Security Onion or Elastic Defend without physical access.

### 5.1 Prerequisites

- Access to Kibana/Elastic Security console
- Target endpoint has Elastic Defend agent installed
- MinIO server configured and accessible from target network
- `Cerberus_Config.json` configured with valid credentials

### 5.2 Phase 1: Staging Cerberus on Target

#### Step 1: Upload All Parts

In Elastic Console, upload each split package:

```bash
upload --file "Part1_Core.zip" --comment "Cerberus Core (1/6)"
upload --file "Part2_FTK.zip" --comment "Cerberus FTK (2/6)"
upload --file "Part3_MinIO.zip" --comment "Cerberus MinIO (3/6)"
upload --file "Part4_KAPE.zip" --comment "Cerberus KAPE (4/6)"
upload --file "Part5_THOR_Sigs.zip" --comment "Cerberus THOR Sigs (5/6)"
upload --file "Part6_THOR_Exe.zip" --comment "Cerberus THOR Exe (6/6)"
```

#### Step 2: Extract All Parts

Execute each extraction command:

```bash
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part1_Core.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract Core (1/6)"

execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part2_FTK.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract FTK (2/6)"

execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part3_MinIO.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract MinIO (3/6)"

execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part4_KAPE.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract KAPE (4/6)"

execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part5_THOR_Sigs.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract THOR Sigs (5/6)"

execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part6_THOR_Exe.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract THOR Exe (6/6)"
```

#### Step 3: Verify Deployment

```bash
execute --command "dir 'C:\ProgramData\Google\Project_Cerberus'" --comment "Verify extraction"
execute --command "dir 'C:\ProgramData\Google\Project_Cerberus\Bin'" --comment "Verify Bin folder"
```

#### Alternative: Single Zip Upload

If your environment allows larger uploads (>65MB):

```bash
upload --file "Project_Cerberus.zip" --comment "Upload Unified DFIR Kit"
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Project_Cerberus.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract Cerberus Kit"
```

### 5.3 Phase 2: Execute Collection

#### A. THOR Malware Scan

Scans system for malware, IOCs, APT indicators.

```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' THOR" --timeout 86400s --comment "THOR Scan"
```

#### B. KAPE Disk Collection (Forensic Artifacts)

Collects Registry, Event Logs, Prefetch, MFT, etc. into VHDX.

```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-DISK" --timeout 3600s --comment "KAPE Disk Collection"
```

#### C. KAPE RAM Capture (Memory Only)

Captures system memory.

```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-RAM" --timeout 3600s --comment "RAM Capture"
```

#### D. KAPE Combined (RAM + Disk)

Captures RAM first (preserves volatile data), then collects disk artifacts.

```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-COMBINED" --timeout 7200s --comment "RAM + Disk Combined"
```

> **Note**: This is the forensically correct order - RAM captured before disk operations modify memory.

#### E. FTK Full Disk Acquisition

Creates bit-for-bit RAW disk image. **Requires external drive configured in `Paths.FTK`**.

```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' FTK" --timeout 172800s --comment "Full Disk Acquisition"
```

#### F. FTK with Custom Output Path

Saves disk image to specific location (useful when C: doesn't have space).

```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' FTK E:\Images" --timeout 172800s --comment "FTK to External Drive"
```

#### G. Upload Retry

Retries MinIO upload without re-collecting (if previous upload failed).

```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' UPLOAD" --timeout 7200s --comment "Retry MinIO Upload"
```

### 5.4 Phase 3: Monitoring & Verification

#### Check Process Status

```bash
processes --comment "Check for running tools"
```

Look for:
- `thor64-lite.exe` (THOR scan)
- `kape.exe` (KAPE collection)
- `ftkimager.exe` (FTK imaging)

#### Check Evidence Folder

```bash
execute --command "dir \"C:\ProgramData\Google\Project_Cerberus\Evidence\" /s" --comment "List collected evidence"
```

#### Verify MinIO Upload

Access MinIO Browser at `https://<KIT_IP>:<PORT>/browser/` and check the `upload` bucket for files matching `<HOSTNAME>-*.zip`.

### 5.5 Phase 4: Cleanup

**CRITICAL**: Always clean up after collection. See [Section 9: Cleanup Procedures](#9-cleanup-procedures).

---

## 6. Tool-Specific Procedures

### 6.1 THOR Lite

#### What THOR Detects

- Malware signatures and IOCs
- APT indicators and suspicious files
- Registry persistence mechanisms
- Rootkits and anomalies
- YARA rule matches (custom + built-in)

#### Command Syntax

```
thor64-lite.exe --logfile <path> --htmlfile <path> [options]
```

#### Common Flags

| Flag | Description |
|------|-------------|
| `--logfile <path>` | Text log output (required) |
| `--htmlfile <path>` | HTML report output (recommended) |
| `--utc` | Use UTC timestamps |
| `--nothordb` | Skip online ThorDB lookup (offline mode) |

#### Output Files

| File | Description |
|------|-------------|
| `<HOSTNAME>.txt` | Detailed text log of scan |
| `<HOSTNAME>.html` | HTML report for easy viewing |

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Clean - no threats detected |
| 1 | Warnings found |
| 2 | Alerts found |
| 3 | Notices found |
| 4+ | Error occurred |

> **Reference**: [THOR Manual - Command Line Flags](https://thor-manual.nextron-systems.com/en/latest/usage/flags.html)

### 6.2 KAPE

#### What KAPE Collects

KAPE uses "Targets" to define which artifacts to collect:

| Target | Description |
|--------|-------------|
| `!SANS_Triage` | Comprehensive forensic artifacts (Registry, logs, prefetch, MFT) |
| `IISLogFiles` | IIS web server logs |
| `Exchange` | Exchange server artifacts |
| `ExchangeCve-2021-26855` | ProxyLogon vulnerability indicators |
| `MemoryFiles` | Pagefile, hiberfil, swapfile |
| `MOF` | WMI MOF files |
| `BITS` | Background Intelligent Transfer Service database |

#### Disk vs RAM vs Combined

| Mode | What It Does | Use Case |
|------|--------------|----------|
| **KAPE-DISK** | Collects forensic artifacts (NOT full disk) | Fast triage, artifact analysis |
| **KAPE-RAM** | Captures system memory | Malware in memory, volatile data |
| **KAPE-COMBINED** | RAM first, then Disk | Full forensic collection (correct order) |

#### Output Format

KAPE outputs to **VHDX** format (Virtual Hard Disk). To analyze:

1. Mount VHDX in Windows (right-click > Mount)
2. Extract contents for analysis
3. Import into forensic tools (Autopsy, X-Ways, etc.)

> **Reference**: [KAPE Documentation](https://ericzimmerman.github.io/KapeDocs/) | [AboutDFIR KAPE Tutorial](https://aboutdfir.com/toolsandartifacts/windows/kape/)

### 6.3 FTK Imager

#### What FTK Creates

- **Disk Image**: Bit-for-bit copy of entire drive (all sectors, deleted files, unallocated space)
- **Memory Dump**: Snapshot of RAM contents

#### CRITICAL: External Drive Required

FTK creates images that can be **100GB - 2TB** in size. **DO NOT** save to the same drive being imaged.

Configure `Paths.FTK` in `Cerberus_Config.json`:

```json
{
    "Paths": {
        "FTK": "E:\\Evidence"
    }
}
```

Or pass path as parameter:

```bash
.\Cerberus.ps1 FTK E:\Images
```

#### Command Syntax

```
ftkimager.exe <source> <destination> [options]
```

#### Common Options

| Option | Description |
|--------|-------------|
| `--compress 9` | Maximum compression |
| `--frag 1TB` | Split into 1TB fragments |
| `--capture-memory <path>` | Capture RAM to file |

> **Reference**: [FTK Imager](https://www.exterro.com/digital-forensics-software/ftk-imager)

---

## 7. Evidence Handling

### 7.1 Output Naming Convention

All evidence files follow this naming pattern:

```
<HOSTNAME>-<DOMAIN>-<TOOL>.zip
```

Examples:
- `DC01-contoso.local-THOR.zip`
- `WORKSTATION5-WORKGROUP-KAPE-Disk.zip`
- `SERVER01-corp.net-FTK.zip`

### 7.2 Evidence Locations

| Mode | Location |
|------|----------|
| USB/Local | `USB:\Project_Cerberus\Evidence\<HOSTNAME>\` |
| Remote/Elastic | `C:\ProgramData\Google\Project_Cerberus\Evidence\` |
| MinIO Server | `https://<KIT_IP>:<PORT>/browser/upload/` |

### 7.3 Log Files

Logs are stored in:

```
Logs\<HOSTNAME>-<DOMAIN>\<HOSTNAME>-<DOMAIN>-<TOOL>_<TIMESTAMP>.log
```

### 7.4 Manual Evidence Retrieval

If MinIO upload fails, retrieve evidence manually:

#### Via Elastic Defend (files <500MB)

```bash
get-file --path "C:/ProgramData/Google/Project_Cerberus/Evidence/<HOSTNAME>-<TOOL>.zip"
```

#### Via MinIO Client (for large files)

See [Section 8.4: Manual MinIO Upload](#84-manual-minio-upload).

---

## 8. Manual Fallback Operations

Use these procedures when automation fails.

### 8.1 When to Use Manual Mode

- Script execution policy blocks `Cerberus.ps1`
- Configuration file errors
- Network connectivity issues
- Need to run specific tool options

### 8.2 Manual THOR Scan

```cmd
REM Run from Project_Cerberus directory
Bin\THOR\thor64-lite.exe --logfile "Evidence\%COMPUTERNAME%_manual.txt" --htmlfile "Evidence\%COMPUTERNAME%_manual.html" --utc --nothordb
```

### 8.3 Manual KAPE Collection

#### Disk Artifacts

```cmd
Bin\KAPE\kape.exe --tsource C: --tdest "Evidence\%COMPUTERNAME%_KAPE" --tflush --target !SANS_Triage,IISLogFiles,Exchange,MemoryFiles,MOF,BITS --ifw
```

#### RAM Capture

```cmd
Bin\KAPE\kape.exe --msource C:\ --mdest "Evidence\%COMPUTERNAME%_RAM" --zm true --module MagnetForensics_RAMCapture
```

> **Note**: Remove `--gui` flag when running remotely (headless).

### 8.4 Manual FTK Operations

#### Disk Image

```cmd
Bin\FTK\x64\ftkimager.exe \\.\C: "E:\Evidence\%COMPUTERNAME%_Disk" --compress 9 --frag 1TB
```

#### Memory Capture

```cmd
Bin\FTK\x64\ftkimager.exe --capture-memory "Evidence\%COMPUTERNAME%_Memory.mem" --compress 1
```

### 8.5 Manual MinIO Upload

```powershell
# Set environment variable with credentials
$env:MC_HOST_minio = "https://<ACCESS_KEY>:<SECRET_KEY>@<KIT_IP>:<PORT>"

# Upload file
.\Bin\MinIO\mc.exe cp "Evidence\<FILENAME>.zip" "minio/upload/" --insecure

# Clear credentials from environment
Remove-Item Env:\MC_HOST_minio
```

---

## 9. Cleanup Procedures

**CRITICAL SECURITY STEP**: Always remove forensic tools from endpoints after collection.

### 9.1 Remote Cleanup (Elastic Defend)

#### Step 1: Remove Project Cerberus Directory

```bash
execute --command "powershell.exe -Command \"Remove-Item -Path 'C:\ProgramData\Google\Project_Cerberus' -Recurse -Force\"" --comment "Remove Cerberus directory"
```

#### Step 2: Remove Uploaded Zip Files

```bash
execute --command "powershell.exe -Command \"Remove-Item -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part*.zip' -Force\"" --comment "Remove uploaded zips"
```

#### Step 3: Remove MinIO Configuration (if used)

```bash
execute --command "powershell.exe -Command \"Remove-Item -Force -Recurse 'C:\Windows\System32\config\systemprofile\mc' -ErrorAction SilentlyContinue\"" --comment "Remove MinIO config"
```

#### Step 4: Verify Cleanup

```bash
execute --command "powershell.exe -Command \"Test-Path 'C:\ProgramData\Google\Project_Cerberus'\"" --comment "Verify removal (should return False)"
```

Expected output: `False`

### 9.2 Local/USB Cleanup

When using USB deployment:

1. Verify evidence has been copied from USB
2. Securely wipe `Evidence\` folder if sensitive data present
3. Remove any temporary files created during collection

### 9.3 Cleanup Verification Checklist

- [ ] `C:\ProgramData\Google\Project_Cerberus` does not exist
- [ ] `C:\Program Files\Elastic\Endpoint\state\response_actions\Part*.zip` removed
- [ ] `C:\Windows\System32\config\systemprofile\mc` removed (MinIO config)
- [ ] No forensic tools remain on endpoint
- [ ] No credentials remain in environment variables

### 9.4 Security Warning

> **IMPORTANT**: Failing to clean up forensic tools could:
> - Leave sensitive security tools accessible to adversaries
> - Expose MinIO credentials
> - Create audit/compliance issues
> - Violate mission partner agreements

---

## 10. Troubleshooting Guide

| Issue | Possible Cause | Solution |
|-------|---------------|----------|
| **THOR: "License File Missing"** | License not in `Bin\THOR` | Copy `.lic` file to `Bin\THOR\` folder |
| **THOR: "No Valid Rules"** | YARA rules not encrypted | Run `thor-util.exe` to encrypt `.yar` to `.yas` |
| **THOR: "unknown flag: --output"** | Wrong flag used | Use `--logfile` and `--htmlfile` instead of `--output` |
| **Script: "Access Denied"** | Not running as Administrator | Right-click > Run as Administrator |
| **Script: "Execution Policy"** | PowerShell blocks scripts | Use `-ExecutionPolicy Bypass` flag |
| **Remote: Script Hangs** | User input required | Do NOT use `Cerberus_Launcher.bat` remotely - use `.ps1` |
| **KAPE: "Target not found"** | Missing `!` escape character | Use `^^!SANS_Triage` in batch files |
| **FTK: "Not enough space"** | Output drive too small | Configure `Paths.FTK` to external drive |
| **FTK: Output path not configured** | `Paths.FTK` empty in config | Set path or pass `-OutputPath` parameter |
| **Upload: "Connection Refused"** | Firewall or wrong IP | Verify MinIO server IP/port, check firewall |
| **Upload: "Access Denied"** | Wrong credentials | Verify `Cerberus_Config.json` credentials |
| **Upload: File >500MB** | Elastic file size limit | Use MinIO direct upload instead of Elastic get-file |
| **Windows 7: Expand-Archive fails** | PowerShell <5.0 | Use legacy extraction (see Windows 7 section) |

### Windows 7 / Legacy PowerShell

If `Expand-Archive` fails on older systems:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory('C:\path\to\file.zip', 'C:\destination')
```

---

## 11. Quick Reference

### 11.1 Command Summary Table

| Tool | Elastic Command | Timeout |
|------|-----------------|---------|
| THOR | `Cerberus.ps1 THOR` | 86400s (24h) |
| KAPE Disk | `Cerberus.ps1 KAPE-DISK` | 3600s (1h) |
| KAPE RAM | `Cerberus.ps1 KAPE-RAM` | 3600s (1h) |
| KAPE Combined | `Cerberus.ps1 KAPE-COMBINED` | 7200s (2h) |
| FTK | `Cerberus.ps1 FTK` | 172800s (48h) |
| FTK (custom path) | `Cerberus.ps1 FTK E:\Images` | 172800s (48h) |
| Upload Retry | `Cerberus.ps1 UPLOAD` | 7200s (2h) |

### 11.2 Copy-Paste Commands

#### THOR Malware Scan
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' THOR" --timeout 86400s --comment "THOR Scan"
```

#### KAPE Disk Collection
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-DISK" --timeout 3600s --comment "KAPE Disk"
```

#### KAPE RAM Capture
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-RAM" --timeout 3600s --comment "KAPE RAM"
```

#### KAPE Combined (RAM + Disk)
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-COMBINED" --timeout 7200s --comment "KAPE Combined"
```

#### FTK Full Disk Image
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' FTK" --timeout 172800s --comment "FTK Disk Image"
```

#### Upload Retry
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' UPLOAD" --timeout 7200s --comment "Retry Upload"
```

#### Cleanup
```bash
execute --command "powershell.exe -Command \"Remove-Item -Path 'C:\ProgramData\Google\Project_Cerberus', 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part*.zip' -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -Force -Recurse 'C:\Windows\System32\config\systemprofile\mc' -ErrorAction SilentlyContinue\"" --comment "Cleanup"
```

### 11.3 Decision Matrix: Which Tool to Use?

| Scenario | Recommended Tool |
|----------|------------------|
| Quick triage - what happened? | KAPE-DISK |
| Is system compromised? | THOR |
| Need volatile data (passwords, malware in memory) | KAPE-RAM or KAPE-COMBINED |
| Full forensic preservation for legal/court | FTK |
| Server investigation (Exchange, IIS) | KAPE-DISK (includes server targets) |
| Suspected active intrusion | KAPE-COMBINED (RAM first!) |

---

## 12. Appendices

### Appendix A: Configuration File Template

```json
{
    "MinIO": {
        "Server": "<KIT_IP>:<PORT>",
        "AccessKey": "<ACCESS_KEY>",
        "SecretKey": "<SECRET_KEY>",
        "Bucket": "upload"
    },
    "Paths": {
        "EvidenceRoot": "${ScriptRoot}\\Evidence",
        "FTK": "<EXTERNAL_DRIVE>:\\Evidence"
    },
    "Tools": {
        "Thor": {
            "Args": "--utc --nothordb"
        },
        "Kape": {
            "DiskArgs": "--tsource C: --tdest ${Output} --tflush --target !SANS_Triage,IISLogFiles,Exchange,ExchangeCve-2021-26855,MemoryFiles,MOF,BITS --ifw --vhdx TargetsOutput_%m",
            "RamArgs": "--msource C:\\ --mdest ${Output} --zm true --module MagnetForensics_RAMCapture"
        },
        "FTK": {
            "Args": "--compress 9 --frag 1TB"
        }
    }
}
```

### Appendix B: KAPE Target Profiles

| Target | What It Collects |
|--------|------------------|
| `!SANS_Triage` | Registry hives, Event logs, Prefetch, $MFT, $UsnJrnl, Amcache, SRUM, Browser data |
| `IISLogFiles` | IIS web server access and error logs |
| `Exchange` | Exchange server mailbox and transport logs |
| `ExchangeCve-2021-26855` | ProxyLogon exploitation indicators |
| `MemoryFiles` | pagefile.sys, hiberfil.sys, swapfile.sys |
| `MOF` | WMI Managed Object Format files |
| `BITS` | Background Intelligent Transfer Service database |

> **Reference**: [KapeFiles GitHub](https://github.com/EricZimmerman/KapeFiles)

### Appendix C: Documentation & Resources

| Resource | URL |
|----------|-----|
| **THOR Lite Homepage** | https://www.nextron-systems.com/thor-lite/ |
| **THOR Manual** | https://thor-manual.nextron-systems.com/en/latest/ |
| **THOR Command Flags** | https://thor-manual.nextron-systems.com/en/latest/usage/flags.html |
| **THOR Custom Signatures** | https://thor-manual.nextron-systems.com/en/latest/usage/custom-signatures.html |
| **KAPE Documentation** | https://ericzimmerman.github.io/KapeDocs/ |
| **KapeFiles (Targets/Modules)** | https://github.com/EricZimmerman/KapeFiles |
| **KAPE Tutorial (AboutDFIR)** | https://aboutdfir.com/toolsandartifacts/windows/kape/ |
| **FTK Imager** | https://www.exterro.com/digital-forensics-software/ftk-imager |
| **Elastic Response Actions** | https://www.elastic.co/docs/solutions/security/endpoint/response-actions |
| **MinIO Client Reference** | https://min.io/docs/minio/linux/reference/minio-mc.html |

### Appendix D: THOR Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | No threats detected | System appears clean |
| 1 | Warnings found | Review warnings in report |
| 2 | Alerts found | Investigate alerts - potential compromise |
| 3 | Notices found | Review notices for context |
| 4+ | Error occurred | Check logs for error details |

### Appendix E: Version Compatibility Matrix

#### Operating System Support

| OS Version | THOR | KAPE | FTK | Mode |
|------------|------|------|-----|------|
| Windows 11 | Yes | Yes | Yes | Modern |
| Windows 10 | Yes | Yes | Yes | Modern |
| Windows Server 2022 | Yes | Yes | Yes | Modern |
| Windows Server 2019 | Yes | Yes | Yes | Modern |
| Windows Server 2016 | Yes | Yes | Yes | Modern |
| Windows Server 2012 R2 | Yes | Yes | Yes | Modern |
| Windows Server 2012 | Yes | Yes | Yes | Modern |
| Windows 8.1 | Yes | Yes | Yes | Modern |
| Windows 7 SP1 | Limited | Limited | Yes | Legacy* |
| Windows Server 2008 R2 | Limited | Limited | Yes | Legacy* |
| Windows Server 2008 | No | No | Yes (x86) | Legacy |
| Windows Vista | No | No | Yes (x86) | Legacy |
| Windows XP | No | No | Yes (x86) | Legacy |
| Windows Server 2003 | No | No | Yes (x86) | Legacy |

*Limited = Requires PowerShell 5.1 installation

#### PowerShell Requirements

| Component | Minimum Version | Recommended | Notes |
|-----------|-----------------|-------------|-------|
| **Cerberus.ps1** | PowerShell 5.1 | PowerShell 5.1+ | Required for all remote operations |
| **Expand-Archive** | PowerShell 5.0 | PowerShell 5.1 | Use legacy extraction on older systems |
| **JSON parsing** | PowerShell 3.0 | PowerShell 5.1 | ConvertFrom-Json cmdlet |

#### Check PowerShell Version

```powershell
$PSVersionTable.PSVersion
```

#### Windows 7 / Server 2008 R2 Workarounds

If `Expand-Archive` fails:

```powershell
# Legacy extraction method
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory('C:\path\to\file.zip', 'C:\destination')
```

#### .NET Framework Requirements

| Tool | Minimum .NET | Notes |
|------|--------------|-------|
| KAPE | .NET 4.6.2 | Required for kape.exe |
| THOR Lite | .NET 4.5 | Bundled runtime |
| PowerShell 5.1 | .NET 4.5 | Usually pre-installed |

---

## 13. Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | January 2026 | PUG | Initial release - comprehensive SOP for Project Cerberus |
| | | | |
| | | | |

---

*Project Cerberus SOP v1.0 - PUG - January 2026*

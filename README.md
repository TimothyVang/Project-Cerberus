# PROJECT CERBERUS - DFIR TRIAGE KIT
**Unified Forensic Collection for Local & Remote Deployments**

## Kit Structure
```text
Project_Cerberus/
├── Bin/                   # Tools (KAPE, THOR, FTK, MinIO)
├── Evidence/              # Output store (Preserved locally)
├── Logs/                  # Execution logs (cerberus-YYYYMMDD.log)
├── Lib/                   # Shared modules
│   ├── Write-Log.ps1          # Logging utility
│   ├── Cerberus-Constants.ps1 # Timeouts, thresholds, paths
│   ├── Cerberus-Config.ps1    # Load & validate JSON config
│   ├── Cerberus-Upload.ps1    # MinIO upload functions
│   └── Cerberus-RunTool.ps1   # Heartbeat monitoring
├── Cerberus_Launcher.bat  # [MODE 1] Local/USB Terminal Interface
├── Cerberus.ps1           # [MODE 2] Remote Entry Point (simple syntax)
├── Run-Thor.ps1           # THOR malware scan
├── Run-KapeDisk.ps1       # KAPE disk artifacts
├── Run-KapeRam.ps1        # KAPE RAM capture
├── Run-KapeCombined.ps1   # RAM first, then Disk
├── Run-Ftk.ps1            # Full disk imaging
├── Run-UploadOnly.ps1     # Upload existing evidence
├── Cerberus_Config.json   # Remote Configuration (Credentials & Args)
├── _settings.bat          # Local Configuration (Args)
└── README.md              # This SOP
```

---

## [MODE 1] USB / Local Triage
**Best for**: On-site incident response, air-gapped systems, or manual collection.

1.  **Preparation**:
    *   Copy the entire `Project_Cerberus` folder to a **high-speed USB drive**.
    *   *Legacy Systems (XP/2003)*: Ensure `Bin\FTK\x86\ftkimager.exe` is present.
    *   **Edit _settings.bat** to modify KAPE targets or FTK arguments.

2.  **Execution**:
    *   Right-Right on `Cerberus_Launcher.bat` and select **Run as Administrator**.
    *   Follow the Terminal Menu (Option 1 for Modern, Option 2 for Legacy).

3.  **Output**:
    *   All evidence is saved to: `USB:\Project_Cerberus\Evidence\%COMPUTERNAME%_*`

---

## [MODE 2] Remote / Elastic Defend Triage
**Best for**: Remote endpoints, scalable collection via Kibana/Security Onion.

### 1. Configuration

**FIRST TIME SETUP:**

1. Copy `Cerberus_Config.json.template` to `Cerberus_Config.json`
2. Edit `Cerberus_Config.json` with your MinIO credentials:

```json
{
    "MinIO": {
        "Server": "10.1.15.173:8443",
        "AccessKey": "YOUR_ACCESS_KEY",
        "SecretKey": "YOUR_SECRET_KEY",
        "Bucket": "upload"
    },
    "Paths": {
        "EvidenceRoot": "${ScriptRoot}\\Evidence",
        "FTK": "",
        "EnableCustomPaths": false
    },
    "Naming": {
        "IncludeDomain": false
    }
}
```

**IMPORTANT:** Never commit `Cerberus_Config.json` to version control (it's in `.gitignore`).

**OPTIONAL: Custom Paths & Domain Naming**

If you need to store evidence on different drives (e.g., FTK disk images on D:\), enable custom paths:

```json
{
    "Paths": {
        "EvidenceRoot": "${ScriptRoot}\\Evidence",
        "FTK": "D:\\FullDiskImages",
        "EnableCustomPaths": true
    },
    "Naming": {
        "IncludeDomain": true
    }
}
```

- **Path Variables**: `${ScriptRoot}`, `${ComputerName}`, `${Domain}`
- **EnableCustomPaths**: Set to `true` to use custom evidence paths
- **IncludeDomain**: Set to `true` to include domain name in zip filenames (e.g., `HOSTNAME-domain.com-THOR.zip`)
- **FTK Path**: Leave empty to use default Evidence folder, or specify custom path for large disk images

### 2. Deployment
1.  **Zip** the `Project_Cerberus` folder.
2.  **Upload** via Elastic "Response Actions".
3.  **Execute** using the `execute` commands found in `Cerberus_QRF.md`.

### 3. Execution Commands (Elastic Defend / Kibana)

**Copy-paste these commands into Kibana Response Console:**

```bash
# 1. THOR Scan (1-4 hours | ~50MB output)
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' THOR" --timeout 86400s

# 2. KAPE Disk Collection (15-30 min | 2-5GB output)
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-DISK" --timeout 3600s

# 3. RAM Capture (5-15 min | Size = Installed RAM)
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-RAM" --timeout 3600s

# 4. RAM + Disk Combined (20-45 min | RAM first, then artifacts)
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-COMBINED" --timeout 7200s

# 5. Full Disk Image (2-8 hours | 20-100GB output)
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' FTK" --timeout 172800s

# 6. FTK with custom output path (saves to external drive)
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' FTK E:\Images" --timeout 172800s

# 7. Upload Existing Evidence (if upload failed)
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' UPLOAD" --timeout 7200s
```

**Path Notes:**

- Default deployment path: `C:\ProgramData\Google\Project_Cerberus\`
- Adjust path if deployed elsewhere
- Use single quotes around file paths (NOT escaped backslashes)
- Always use `powershell.exe` (not `pwsh.exe`) for compatibility

**Tool Comparison:**

- **THOR** - Malware/APT scanner (analyzes files for threats)
- **KAPE-DISK** - Forensic artifact collector (Registry, logs, prefetch - **NOT full disk image**)
- **KAPE-RAM** - Memory capture only (RAM dump)
- **KAPE-COMBINED** - RAM first, then Disk (forensically correct order)
- **FTK** - Complete disk imaging (full forensic disk copy)
- **UPLOAD** - Retry MinIO upload without re-collecting

**Important:** For full disk forensics, use **FTK**. KAPE-DISK only collects specific artifacts.

**Timeout Guidelines:**

- THOR: 86400s (24 hours)
- KAPE-DISK: 3600s (1 hour)
- KAPE-RAM: 3600s (1 hour)
- KAPE-COMBINED: 7200s (2 hours)
- FTK: 172800s (48 hours)

---

## Command Reference

**THOR Scan:**
```batch
# Local Mode (with HTML reports)
Bin\THOR\thor64-lite.exe --logfile "Evidence\%COMPUTERNAME%\thor.txt" --htmlfile "Evidence\%COMPUTERNAME%\thor.html" --utc --nothordb

# Remote Mode (simple syntax)
powershell -ExecutionPolicy Bypass -File "Cerberus.ps1" THOR
```

**THOR Output Files:**
- `COMPUTERNAME.txt` - Text log file
- `COMPUTERNAME.html` - HTML report
- `*.csv` - CSV data files

**MinIO Upload (Remote Mode):**

```powershell
# Upload compressed evidence (automatic in agent)
mc put "Evidence\HOSTNAME-THOR.zip" minio\upload --insecure

# Upload FTK disk image (all segments compressed together)
mc put "Evidence\HOSTNAME-FTK.zip" minio\upload --insecure
```

**Important Notes:**

- THOR: Use `--logfile` and `--htmlfile` (NOT `--output`)
- MinIO: Evidence is automatically compressed to .zip before upload (line 626-715 in agent)
- MinIO: The agent uses `mc put` with backslash path separator (`minio\bucket`)
- MinIO: Automatically configures using `$env:MC_HOST_minio`
- Upload Workflow: Collect → Compress to .zip → Upload → Preserve original locally

---

## Evidence Handling & Compression

**Automatic Compression Workflow (Remote Mode)**:
1. Tool completes collection and saves to `Evidence\HOSTNAME-<TOOL>\`
2. Agent automatically compresses entire folder to `.zip` file
3. Compressed zip file is uploaded to MinIO server
4. **Original uncompressed folder is preserved** locally for forensic integrity
5. Both original and zip remain on disk (no auto-deletion)

**Compression Details**:
- Compression ratios typically 30-50% of original size
- Large files (>100MB) are always compressed before upload
- All evidence folders automatically zipped: THOR, KAPE-Disk, KAPE-RAM, FTK
- Preserves chain of custody by keeping originals intact

**Example Output**:
```
Evidence/
├── HOSTNAME-THOR/              # Original folder (preserved locally)
├── HOSTNAME-THOR.zip           # Compressed and uploaded to MinIO
├── HOSTNAME-KAPE-Disk/         # Original folder (preserved locally)
├── HOSTNAME-KAPE-Disk.zip      # Compressed and uploaded to MinIO
├── HOSTNAME-RAM/               # Original folder (preserved locally)
├── HOSTNAME-RAM.zip            # Compressed and uploaded to MinIO
├── HOSTNAME-Disk.raw           # FTK disk image segments (preserved)
└── HOSTNAME-FTK.zip            # All disk segments compressed together
```

**If Upload Fails**:
- Both original folder and zip remain in Evidence/ directory
- Evidence is NEVER deleted automatically (forensic preservation)
- Use `-UploadOnly` mode to retry upload without re-collecting
- Check logs for network errors or credential issues

---

## 📋 Troubleshooting & Logs

### Execution Logs

Logs are organized **per-host** with separate files **per-operation**:

```text
Logs/
  HOSTNAME-DOMAIN/
    index.txt                                      # Summary of all operations
    HOSTNAME-DOMAIN-THOR_20260116_103045.log      # THOR scan log
    HOSTNAME-DOMAIN-UPLOAD_20260116_110030.log    # Separate upload log
    HOSTNAME-DOMAIN-KAPE-Disk_20260116_143022.log # KAPE disk artifacts
    HOSTNAME-DOMAIN-KAPE-RAM_20260116_150000.log  # RAM capture
```

**Retrieve logs remotely:**

```bash
# List all log folders (one per host)
execute --command "dir C:\ProgramData\Google\Project_Cerberus\Logs"

# Get operation index for a host
get-file --path "C:/ProgramData/Google/Project_Cerberus/Logs/HOSTNAME-DOMAIN/index.txt"

# Get specific operation log
get-file --path "C:/ProgramData/Google/Project_Cerberus/Logs/HOSTNAME-DOMAIN/HOSTNAME-DOMAIN-THOR_20260116_103045.log"
```

**Log format:**

```text
[2026-01-16 10:30:45] [INFO] Starting THOR Scan (Remote Mode)...
[2026-01-16 11:25:12] [SUCCESS] Upload Complete: Evidence\HOSTNAME-THOR.zip
[2026-01-16 11:25:13] [ERROR] THOR failed with exit code: 1
```

**Index file format** (`index.txt`):
```text
================================================================================
PROJECT CERBERUS - Operation Index for DESKTOP-PC1-WORKGROUP
================================================================================
2026-01-16 10:30:45 | THOR      | DESKTOP-PC1-WORKGROUP-THOR_20260116_103045.log
2026-01-16 11:00:30 | UPLOAD    | DESKTOP-PC1-WORKGROUP-UPLOAD_20260116_110030.log
```

### Common Issues

**Config not found:**

- Copy `Cerberus_Config.json.template` to `Cerberus_Config.json`
- Edit with your MinIO credentials

**MinIO upload fails:**

- Evidence is automatically compressed before upload - check for .zip files in Evidence folder
- Check network: Can you reach the MinIO server?
- Verify credentials in `Cerberus_Config.json`
- Original evidence is preserved even if upload fails
- Use `-UploadOnly` mode to retry upload without re-collecting
- Check logs for detailed error messages

**Tool execution fails:**

- Check disk space (10GB+ required for FTK/KAPE)
- Verify tool binaries exist in `Bin/` directory
- Review exit codes in logs

**See `Logs/README.md` for detailed logging information.**

---

## Documentation & Resources

### Tool Documentation
| Tool | Documentation |
|------|---------------|
| **THOR Lite** | https://www.nextron-systems.com/thor-lite/ |
| **THOR Manual** | https://thor-manual.nextron-systems.com/ |
| **KAPE** | https://ericzimmerman.github.io/KapeDocs/ |
| **KAPE Targets/Modules** | https://github.com/EricZimmerman/KapeFiles |
| **FTK Imager** | https://www.exterro.com/digital-forensics-software/ftk-imager |
| **MinIO Client (mc)** | https://min.io/docs/minio/linux/reference/minio-mc.html |
| **MinIO Console** | https://min.io/docs/minio/linux/administration/minio-console.html |

### Elastic Stack
| Component | Documentation |
|-----------|---------------|
| **Elastic Defend** | https://www.elastic.co/docs/solutions/security/endpoint |
| **Response Actions** | https://www.elastic.co/docs/solutions/security/endpoint/response-actions |
| **Elastic Agent** | https://www.elastic.co/docs/reference/fleet/elastic-agent |

### PowerShell References
| Cmdlet | Documentation |
|--------|---------------|
| **Compress-Archive** | https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.archive/compress-archive |
| **Test-NetConnection** | https://learn.microsoft.com/en-us/powershell/module/nettcpip/test-netconnection |

---
*See `Project_Cerberus_User_Guide.md` for a detailed visual field manual.*

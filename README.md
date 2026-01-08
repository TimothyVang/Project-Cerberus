# PROJECT CERBERUS - DFIR TRIAGE KIT
**Unified Forensic Collection for Local & Remote Deployments**

## 📂 Kit Structure
```text
Project_Cerberus_Kit/
├── Bin/                   # Tools (KAPE, THOR, FTK, MinIO)
├── Evidence/              # Output store (Preserved locally)
├── Logs/                  # Execution logs (cerberus-YYYYMMDD.log)
├── Lib/                   # Shared modules (Write-Log.ps1)
├── Cerberus_Launcher.bat  # [MODE 1] Local/USB Terminal Interface
├── Cerberus_Agent.ps1     # [MODE 2] Remote/Elastic Headless Agent
├── Cerberus_Config.json   # Remote Configuration (Credentials & Args)
├── _settings.bat          # Local Configuration (Args)
└── README.md              # This SOP
```

---

## [MODE 1] USB / Local Triage
**Best for**: On-site incident response, air-gapped systems, or manual collection.

1.  **Preparation**:
    *   Copy the entire `Project_Cerberus_Kit` folder to a **high-speed USB drive**.
    *   *Legacy Systems (XP/2003)*: Ensure `Bin\FTK\x86\ftkimager.exe` is present.
    *   **Edit _settings.bat** to modify KAPE targets or FTK arguments.

2.  **Execution**:
    *   Right-Right on `Cerberus_Launcher.bat` and select **Run as Administrator**.
    *   Follow the Terminal Menu (Option 1 for Modern, Option 2 for Legacy).

3.  **Output**:
    *   All evidence is saved to: `USB:\Project_Cerberus_Kit\Evidence\%COMPUTERNAME%_*`

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
    }
}
```

**IMPORTANT:** Never commit `Cerberus_Config.json` to version control (it's in `.gitignore`).

### 2. Deployment
1.  **Zip** the `Project_Cerberus_Kit` folder.
2.  **Upload** via Elastic "Response Actions".
3.  **Execute** using the `execute` commands found in `Cerberus_QRF.md`.

### 3. Execution Commands (Elastic Defend / Kibana)

**Copy-paste these commands into Kibana Response Console:**

```bash
# 1. THOR Scan (1-4 hours | ~50MB output)
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool THOR" --timeout 86400s

# 2. KAPE Triage (15-30 min | 2-5GB output)
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool KAPE-TRIAGE" --timeout 3600s

# 3. RAM Capture (5-15 min | Size = Installed RAM)
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool KAPE-RAM" --timeout 3600s

# 4. Full Disk Image (2-8 hours | 20-100GB output)
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool FTK" --timeout 172800s

# 5. Upload Existing Evidence (if upload failed)
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -UploadOnly" --timeout 7200s
```

**Path Notes:**

- Default deployment path: `C:\ProgramData\Google\Project_Cerberus_Kit\`
- Adjust path if deployed elsewhere
- Use double backslashes (`\\`) or forward slashes (`/`) in paths
- Always use `powershell.exe` (not `pwsh.exe`) for compatibility

**Parameters Explained:**

- `-Tool THOR` - APT/Malware scanner
- `-Tool KAPE-TRIAGE` - Forensic artifact collector (files + server logs)
- `-Tool KAPE-RAM` - Memory capture only
- `-Tool FTK` - Full disk imaging
- `-UploadOnly` - Skip collection, retry MinIO upload

**Timeout Guidelines:**

- THOR: 86400s (24 hours)
- KAPE-TRIAGE: 3600s (1 hour)
- KAPE-RAM: 3600s (1 hour)
- FTK: 172800s (48 hours)

---

## Command Reference

**THOR Scan:**
```batch
# Local Mode (with HTML reports)
Bin\THOR\thor64-lite.exe --logfile "Evidence\%COMPUTERNAME%\thor.txt" --htmlfile "Evidence\%COMPUTERNAME%\thor.html" --utc --nothordb

# Remote Mode (via Agent)
powershell -ExecutionPolicy Bypass -File "Cerberus_Agent.ps1" -Tool THOR
```

**THOR Output Files:**
- `COMPUTERNAME.txt` - Text log file
- `COMPUTERNAME.html` - HTML report
- `*.csv` - CSV data files

**MinIO Upload (Remote Mode):**

```powershell
# Upload file
mc put "Evidence\file.zip" minio/upload --insecure

# Upload directory
mc put --recursive "Evidence\HOSTNAME-THOR" minio/upload --insecure
```

**Important Notes:**

- THOR: Use `--logfile` and `--htmlfile` (NOT `--output`)
- MinIO: The agent uses `mc put` with forward slashes in bucket path
- MinIO: Automatically configures using `$env:MC_HOST_minio`

---

## 📋 Troubleshooting & Logs

### Execution Logs

All operations are logged to: `Logs\cerberus-YYYYMMDD.log`

**Retrieve logs remotely:**

```bash
# Get today's log (replace date)
get-file --path "C:/ProgramData/Google/Logs/cerberus-20260108.log"

# List all available logs
execute --command "dir C:\ProgramData\Google\Logs\cerberus-*.log"
```

**Log format:**

```text
[2026-01-08 14:23:45] [INFO] Starting THOR Scan (Remote Mode)...
[2026-01-08 14:25:12] [SUCCESS] Upload Complete: Evidence\HOSTNAME-THOR
[2026-01-08 14:25:13] [ERROR] THOR failed with exit code: 1
```

### Common Issues

**Config not found:**

- Copy `Cerberus_Config.json.template` to `Cerberus_Config.json`
- Edit with your MinIO credentials

**MinIO upload fails:**

- Check network: Can you reach the MinIO server?
- Verify credentials in `Cerberus_Config.json`
- Check logs for detailed error messages

**Tool execution fails:**

- Check disk space (10GB+ required for FTK/KAPE)
- Verify tool binaries exist in `Bin/` directory
- Review exit codes in logs

**See `Logs/README.md` for detailed logging information.**

---
*See `Project_Cerberus_User_Guide.md` for a detailed visual field manual.*

# PROJECT CERBERUS - DFIR TRIAGE KIT
**Unified Forensic Collection for Local & Remote Deployments**

## 📂 Kit Structure
```text
Project_Cerberus_Kit/
├── Bin/                   # Tools (KAPE, THOR, FTK, MinIO)
├── Evidence/              # Output store (Preserved locally)
├── Logs/                  # Operation logs
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
Open `Cerberus_Config.json` in a text editor to set your MinIO credentials and tool flags:
```json
{
    "MinIO": { "Server": "...", "AccessKey": "...", "SecretKey": "..." }
}
```

### 2. Deployment
1.  **Zip** the `Project_Cerberus_Kit` folder.
2.  **Upload** via Elastic "Response Actions".
3.  **Execute** using the `execute` commands found in `Cerberus_QRF.md`.

### 3. Execution Commands
*   **THOR**: `powershell -ExecutionPolicy Bypass -File "...\Cerberus_Agent.ps1" -Tool THOR`
*   **KAPE**: `powershell -ExecutionPolicy Bypass -File "...\Cerberus_Agent.ps1" -Tool KAPE-TRIAGE`
*   **RAM**:  `powershell -ExecutionPolicy Bypass -File "...\Cerberus_Agent.ps1" -Tool KAPE-RAM`
*   **FTK**:  `powershell -ExecutionPolicy Bypass -File "...\Cerberus_Agent.ps1" -Tool FTK`

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
# Upload directory
mc cp --recursive "Evidence\HOSTNAME-THOR" "cerberus/upload/" --insecure

# Upload file
mc cp "Evidence\file.zip" "cerberus/upload/" --insecure
```

**Important Flags:**
- THOR: Use `--logfile` and `--htmlfile` (NOT `--output`)
- MinIO: Use `mc cp` command (NOT `mc put`)

---
*See `Project_Cerberus_User_Guide.md` for a detailed visual field manual.*

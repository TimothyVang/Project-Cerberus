# PROJECT CERBERUS: OPERATOR FIELD MANUAL
**Unified Digital Forensics & Incident Response Kit**

---

## 📸 Interface Preview
![Cerberus TUI Terminal](c:/Users/newbi/.gemini/antigravity/brain/15947f52-28a5-486e-b3e9-4e63f3dc95d2/uploaded_image_1767672330324.png)
*Above: The TUI interface for USB/Local deployments.*

---

## 1. Kit Overview
Project Cerberus is a unified toolkit designed for two distinct operational modes:
1.  **USB / Local Triage**: For air-gapped or onsite collection (using `Cerberus_Launcher.bat`).
2.  **Remote / Elastic Triage**: For network-wide collection via Kibana (using `Cerberus_Agent.ps1`).

### Directory Structure
```text
Project_Cerberus_Kit/
├── Bin/                   # Tool Binaries (FTK, KAPE, THOR, MinIO)
├── Evidence/              # Collection Output (Auto-created per hostname)
├── Cerberus_Launcher.bat  # USB Launcher (Double-click this)
├── Cerberus_Agent.ps1     # Remote Agent (Run via PowerShell/Kibana)
├── Cerberus_Config.json   # Configuration File (Edit this!)
├── _settings.bat          # Launcher Settings
└── README.md              # Quick Start Guide
```

---

## 2. [MODE 1] USB / Local Deployment
**Use Case**: You are physically present at the machine, or the machine is offline/air-gapped.

### Step-by-Step Instructions
1.  **Preparation**:
    *   Copy the `Project_Cerberus_Kit` folder to a high-performance USB drive (SSD recommended).
    *   *Legacy Note*: If targeting Windows XP/Server 2003, ensure `Bin\FTK\x86` contains the legacy binary.
    *   **Config**: Edit `_settings.bat` if you need to change KAPE targets or FTK compression levels.

2.  **Launch**:
    *   Plug the USB into the target machine.
    *   Navigate to the folder.
    *   Right-Right on `Cerberus_Launcher.bat` and select **Run as Administrator**.

3.  **Operation**:
    *   The TUI will auto-detect the OS (Modern vs Legacy).
    *   **Select Option [1]** for Modern Windows (10/11/Server 2016+).
        *   Choose **KAPE** for fast artifact collection (Registry, Logs, etc).
        *   Choose **THOR** for malware scanning.
        *   Choose **FTK** for live memory/disk imaging.
    *   **Select Option [2]** for Legacy Windows (XP/2003).
        *   Uses 32-bit stable tools safe for older kernels.

4.  **Collection**:
    *   Wait for the tool to finish (Green success message).
    *   Evidence is saved to `USB:\Project_Cerberus_Kit\Evidence\%COMPUTERNAME%`.
    *   Press any key to return to the menu or exit.

---

## 3. [MODE 2] Remote / Elastic Deployment
**Use Case**: You need to triage disparate endpoints via Elastic Defend or Security Onion without physical access.

### Configuration (IMPORTANT)
Before deployment, edit `Cerberus_Config.json` to set your credentials and tool arguments:
```json
{
    "MinIO": {
        "Server": "10.1.15.173:8443",
        "AccessKey": "your_key",
        "SecretKey": "your_secret",
        "Bucket": "upload"
    }
}
```
*   **Junior Devs**: This file allows you to change passwords, server IPs, and tool flags without touching the PowerShell code.
*   **Tradecraft**: KAPE arguments (including VHDX format and passwords) are already pre-configured here.

### Deployment Steps
1.  **Package**: Zip the `Project_Cerberus_Kit` folder -> `Project_Cerberus_Kit.zip`.
2.  **Upload**: Go to Elastic Console -> **Response Actions** -> **Upload**. Select the zip.
3.  **Extract**: Run the extraction command:
    ```bash
    execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Project_Cerberus_Kit.zip' -DestinationPath 'C:\ProgramData\Google'"
    ```

### Execution Commands (Copy-Paste)
Use the `Cerberus_Agent.ps1` to trigger specific actions. It handles the logic (checking binaries, setting flags, uploading to MinIO).

**A. KAPE Triage (Fast Artifacts)**
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool KAPE-TRIAGE" --timeout 3600s
```

**B. KAPE Memory Capture (RAM)**
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool KAPE-RAM" --timeout 3600s
```

**C. THOR Malware Scan**
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool THOR" --timeout 86400s
```

**D. FTK Full Disk Image**
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool FTK" --timeout 172800s
```

---

## 4. Verification & Troubleshooting
*   **Logs**: Check `Logs\` or the console output.
*   **"Upload Failed"**: 
    1.  Can you ping the MinIO server?
    2.  Did you update `Cerberus_Config.json` with the correct keys?
    3.  Check the "Network" section in the Agent logs only.
*   **"Target EZParser not found"**: This was a known issue in older versions. The current launcher uses escaped variables (`^!`) to fix this.
*   **XP/2003 Crashes**: Ensure you are using the **Legacy Menu** (Option 2).

---

## 5. Command Reference

### THOR Flags (Correct Usage)
```bash
# ✅ CORRECT - Log file output with HTML reports
--logfile "path\to\thor.txt" --htmlfile "path\to\thor.html"

# ✅ CORRECT - Log file only (no HTML)
--logfile "path\to\thor.txt"

# ❌ INCORRECT - Unsupported flag
--output "path\to\folder"
```

**THOR Output Flags:**
- `--logfile "file.txt"` - Text log file location (required)
- `--htmlfile "file.html"` - HTML report output (optional, recommended)
- `--nocsv` - Disable CSV output (remove this flag to generate CSV files)

### MinIO Upload Commands (Correct Usage)
```powershell
# ✅ CORRECT - Upload directory
mc cp --recursive "C:\Evidence\HOSTNAME-THOR" "cerberus/upload/" --insecure

# ✅ CORRECT - Upload single file
mc cp "C:\Evidence\file.zip" "cerberus/upload/" --insecure

# ❌ INCORRECT - Wrong command
mc put "file" "bucket"  # 'put' is not a valid mc command
```

### Common Issues
**"unknown flag: --output" (THOR)**
- Fix: Change `--output` to `--logfile "path\to\logfile.txt"`

**"Invalid arguments" (MinIO)**
- Fix: Change `mc put` to `mc cp`
- Fix: Add `--recursive` flag for directories

---
*Project Cerberus SOP v2.1 - Verified Jan 2026*

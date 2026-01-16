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
2.  **Remote / Elastic Triage**: For network-wide collection via Kibana (using `Cerberus.ps1`).

### Directory Structure
```text
Project_Cerberus/
├── Bin/                   # Tool Binaries (FTK, KAPE, THOR, MinIO)
├── Evidence/              # Collection Output (Auto-created per hostname)
├── Lib/                   # Shared modules
│   ├── Write-Log.ps1          # Logging utility
│   ├── Cerberus-Constants.ps1 # Timeouts, thresholds, paths
│   ├── Cerberus-Config.ps1    # Load & validate JSON config
│   ├── Cerberus-Upload.ps1    # MinIO upload functions
│   └── Cerberus-RunTool.ps1   # Heartbeat monitoring
├── Cerberus_Launcher.bat  # USB Launcher (Double-click this)
├── Cerberus.ps1           # Remote Entry Point (simple syntax)
├── Run-Thor.ps1           # THOR malware scan
├── Run-KapeDisk.ps1       # KAPE disk artifacts
├── Run-KapeRam.ps1        # KAPE RAM capture
├── Run-KapeCombined.ps1   # RAM first, then Disk
├── Run-Ftk.ps1            # Full disk imaging
├── Run-UploadOnly.ps1     # Upload existing evidence
├── Cerberus_Config.json   # Configuration File (Edit this!)
├── _settings.bat          # Launcher Settings
└── README.md              # Quick Start Guide
```

---

## 2. [MODE 1] USB / Local Deployment
**Use Case**: You are physically present at the machine, or the machine is offline/air-gapped.

### Step-by-Step Instructions
1.  **Preparation**:
    *   Copy the `Project_Cerberus` folder to a high-performance USB drive (SSD recommended).
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
    *   Evidence is saved to `USB:\Project_Cerberus\Evidence\%COMPUTERNAME%`.
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
    },
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

**Configuration Options:**
*   **MinIO**: Server credentials for evidence upload
*   **Paths**: Custom evidence storage locations (optional)
    *   `EvidenceRoot`: Default evidence folder (supports `${ScriptRoot}`, `${ComputerName}`, `${Domain}` variables)
    *   `FTK`: Separate path for large disk images (leave empty to use default)
    *   `EnableCustomPaths`: Set to `true` to activate custom paths
*   **Naming**: Zip filename format options
    *   `IncludeDomain`: Set to `true` to include domain in filenames (e.g., `DC01-morm.gov.mk-THOR.zip`)
*   **Junior Devs**: This file allows you to change passwords, server IPs, paths, and tool flags without touching the PowerShell code.
*   **Tradecraft**: KAPE arguments (including VHDX format and passwords) are already pre-configured here.

**Example Use Cases:**

*Domain Controller with FTK on D:\ drive:*
```json
{
    "Paths": {
        "FTK": "D:\\FullDiskImages\\${ComputerName}",
        "EnableCustomPaths": true
    },
    "Naming": {
        "IncludeDomain": true
    }
}
```
Result: FTK images saved to `D:\FullDiskImages\DC01-2016\` with zip named `DC01-2016-morm.gov.mk-FTK.zip`

*Default Behavior (Backward Compatible):*
```json
{
    "Paths": {
        "EnableCustomPaths": false
    },
    "Naming": {
        "IncludeDomain": false
    }
}
```
Result: All evidence in `Evidence\` folder with standard naming `HOSTNAME-Tool.zip`

### Deployment Steps
1.  **Package**: Zip the `Project_Cerberus` folder -> `Project_Cerberus.zip`.
2.  **Upload**: Go to Elastic Console -> **Response Actions** -> **Upload**. Select the zip.
3.  **Extract**: Run the extraction command:
    ```bash
    execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Project_Cerberus.zip' -DestinationPath 'C:\ProgramData\Google'"
    ```

### Execution Commands (Copy-Paste)
Use `Cerberus.ps1` with simple tool names. It handles the logic (checking binaries, setting flags, uploading to MinIO).

**A. THOR Malware Scan**
*APT/IOC scanner - analyzes system for threats*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' THOR" --timeout 86400s
```

**B. KAPE Disk Collection - Forensic Artifacts Collection**
*Collects Registry, Event Logs, Prefetch, MFT, etc. into VHDX (NOT a full disk image)*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-DISK" --timeout 3600s
```

**C. KAPE Memory Capture (RAM Only)**
*Captures system memory - does not image the disk*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-RAM" --timeout 3600s
```

**D. KAPE Combined (RAM + Disk)**
*Captures RAM first (preserves volatile data), then collects disk artifacts*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-COMBINED" --timeout 7200s
```

**E. FTK Full Disk Image (RAW Format)**
*Complete bit-for-bit disk image of C: drive*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' FTK" --timeout 172800s
```

**F. FTK with Custom Output Path**
*Saves disk image to external drive (useful when C: doesn't have space)*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' FTK E:\Images" --timeout 172800s
```

**G. Upload Existing Evidence**
*Retry MinIO upload without re-collecting*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' UPLOAD" --timeout 7200s
```

**Important:**
- **KAPE-DISK** collects specific forensic artifacts (fast, 2-5GB)
- **KAPE-COMBINED** runs RAM first, then Disk (forensically correct order)
- **FTK** creates a complete disk image (slow, 20-100GB+)
- For full disk forensics, use **FTK**, not KAPE

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
- `--utc` - Use UTC timestamps (enabled by default in agent)
- `--nothordb` - Skip online ThorDB lookup for offline mode (enabled by default)

### MinIO Upload Commands
```powershell
# Upload single file
mc put "C:\Evidence\file.zip" "minio\upload" --insecure

# Upload directory recursively
mc put -r "C:\Evidence\HOSTNAME-THOR" "minio\upload" --insecure
```

**Implementation Note:** Uses `mc put` with backslash separator (`minio\bucket`) for Windows compatibility.

### Common Issues
**"unknown flag: --output" (THOR)**
- Fix: Change `--output` to `--logfile "path\to\logfile.txt"` and `--htmlfile "path\to\report.html"`

**"Upload failures" (MinIO)**
- Check network connectivity to MinIO server
- Verify credentials in `Cerberus_Config.json`
- Evidence is always preserved locally even if upload fails

---

## 6. Documentation & Resources

### Tool Documentation
| Tool | Documentation |
|------|---------------|
| **THOR Lite** | https://www.nextron-systems.com/thor-lite/ |
| **THOR Manual** | https://thor-manual.nextron-systems.com/ |
| **KAPE Download** | https://www.kroll.com/en/insights/publications/cyber/kroll-artifact-parser-extractor-kape |
| **KAPE Manual** | https://ericzimmerman.github.io/KapeDocs/ |
| **KAPE Targets/Modules** | https://github.com/EricZimmerman/KapeFiles |
| **KAPE Tutorial** | https://aboutdfir.com/toolsandartifacts/windows/kape/ |
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
*Project Cerberus SOP v2.5 - Updated Jan 2026*

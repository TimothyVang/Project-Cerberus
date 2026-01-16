# Elastic Response Console - Project Cerberus Deployment Commands

## Overview
This document provides step-by-step commands for deploying and executing the unified **Project Cerberus Kit** via Elastic Response Console.

---

## Phase 1: Staging Cerberus (Multi-Part Upload for 25MB Limit)

The kit is split into 6 parts to accommodate upload size limits. Each part extracts to the same destination and files merge automatically.

### Part Sizes
| File | Contents | Size |
|------|----------|------|
| Part1_Core.zip | Scripts, Lib, Config | 50 KB |
| Part2_FTK.zip | Bin/FTK | 4.2 MB |
| Part3_MinIO.zip | Bin/MinIO | 11 MB |
| Part4_KAPE.zip | Bin/KAPE | 24 MB |
| Part5_THOR_Sigs.zip | THOR signatures & config | 8.4 MB |
| Part6_THOR_Exe.zip | THOR executable | 16 MB |

### Step 1: Upload All Parts
```bash
upload --file "Part1_Core.zip" --comment "Cerberus Core (1/6)"
upload --file "Part2_FTK.zip" --comment "Cerberus FTK (2/6)"
upload --file "Part3_MinIO.zip" --comment "Cerberus MinIO (3/6)"
upload --file "Part4_KAPE.zip" --comment "Cerberus KAPE (4/6)"
upload --file "Part5_THOR_Sigs.zip" --comment "Cerberus THOR Sigs (5/6)"
upload --file "Part6_THOR_Exe.zip" --comment "Cerberus THOR Exe (6/6)"
```

### Step 2: Extract All Parts (Same Destination)
```bash
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part1_Core.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract Core (1/6)"
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part2_FTK.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract FTK (2/6)"
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part3_MinIO.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract MinIO (3/6)"
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part4_KAPE.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract KAPE (4/6)"
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part5_THOR_Sigs.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract THOR Sigs (5/6)"
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Part6_THOR_Exe.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract THOR Exe (6/6)"
```

### Step 3: Verify Deployment
```bash
execute --command "dir 'C:\ProgramData\Google\Project_Cerberus'" --comment "Verify extraction"
execute --command "dir 'C:\ProgramData\Google\Project_Cerberus\Bin'" --comment "Verify Bin folder"
```

### Alternative: Single Zip (If No Size Limit)
If your upload limit is larger than 65MB, you can use a single zip instead:
```bash
upload --file "Project_Cerberus.zip" --comment "Upload Unified DFIR Kit"
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Project_Cerberus.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract Cerberus Kit"
```

---

## Phase 2: Execution Scenarios

### Option A: THOR Malware Scan
*Standard malware and IOC scan. Output uploads to MinIO automatically.*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' THOR" --timeout 86400s --comment "THOR Scan"
```
*Monitor process:* `processes --comment "Check for thor64-lite.exe"`

### Option B: KAPE Disk Collection (Forensic Artifacts - NOT Full Disk)
*Collects Registry, Event Logs, Prefetch, MFT, Amcache, etc. into VHDX*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-DISK" --timeout 3600s --comment "KAPE Disk Collection"
```
**Note:** KAPE-DISK collects specific artifacts (2-5GB), not a complete disk image.

### Option C: KAPE RAM Capture (Memory Only)
*Dumps system memory - does NOT image the disk*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-RAM" --timeout 3600s --comment "RAM Capture"
```

### Option D: KAPE Combined (RAM + Disk)
*Captures RAM first (preserves volatile data), then collects disk artifacts*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' KAPE-COMBINED" --timeout 7200s --comment "RAM + Disk Combined"
```
**Note:** Forensically correct order - RAM captured before disk operations modify memory.

### Option E: FTK Full Disk Acquisition (Complete Disk Image)
*Creates bit-for-bit RAW disk image of C: drive (20-100GB+)*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' FTK" --timeout 172800s --comment "Full Disk Acquisition"
```

### Option F: FTK with Custom Output Path
*Saves disk image to external drive (useful when C: doesn't have space)*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' FTK E:\Images" --timeout 172800s --comment "FTK to External Drive"
```
**Note:** For complete forensic disk imaging, use FTK (not KAPE).

---

## Phase 3: Verification & Recovery

### Check Evidence Folder
```bash
execute --command "dir \"C:\ProgramData\Google\Project_Cerberus\Evidence\" /s" --comment "List collected evidence"
```

### Retry Uploads (If MinIO failed)
*Evidence is NOT deleted. You can retry the upload step only.*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File 'C:\ProgramData\Google\Project_Cerberus\Cerberus.ps1' UPLOAD" --timeout 7200s --comment "Retry MinIO Upload"
```

---

## Configuration Note
*   **MinIO Credentials**: configured in `Cerberus_Config.json`.
*   **Tool Arguments**: Configurable in `Cerberus_Config.json`.
*   **Custom Paths**: Use `Paths.EnableCustomPaths: true` to store FTK images on D:\ or E:\ drives.
*   **Domain Naming**: Use `Naming.IncludeDomain: true` to include domain in zip filenames.

---

## Troubleshooting Common Command Errors

### THOR: "unknown flag: --output"
**Problem:** THOR doesn't support `--output` flag.

**Solution:**
```bash
# ❌ Wrong
thor64-lite.exe --output "C:\Evidence\output"

# ✅ Correct (with HTML reports)
thor64-lite.exe --logfile "C:\Evidence\output\thor.txt" --htmlfile "C:\Evidence\output\thor.html"

# ✅ Correct (text log only)
thor64-lite.exe --logfile "C:\Evidence\output\thor.txt"
```

### THOR: No HTML reports generated
**Problem:** Missing `--htmlfile` flag.

**Solution:**
```bash
# Add --htmlfile flag with output file path
thor64-lite.exe --logfile "log.txt" --htmlfile "C:\Evidence\THOR_Reports\report.html"
```

### MinIO: "Invalid arguments provided"
**Problem:** Wrong MinIO client command or missing flags.

**Solution:**
```powershell
# ❌ Wrong (missing -r flag for directories)
mc put "Evidence\folder" "minio\upload"

# ✅ Correct - Agent implementation (Cerberus_Agent.ps1)
mc put -r "Evidence\folder" "minio\upload" --insecure

# ✅ Correct - Single file
mc put "Evidence\file.zip" "minio\upload" --insecure

# ℹ️ Alternative syntax (standard mc client, uses forward slash)
mc cp --recursive "Evidence\folder" "minio/upload/" --insecure
```

**Note:** The Cerberus Agent uses `mc put -r` for directories with backslash path separator (`minio\bucket`) for Windows compatibility. The `--insecure` flag is required for self-signed certificates.

### Custom Paths: FTK images on D:\ drive
**Problem:** Default Evidence folder doesn't have enough space for large disk images.

**Solution:**
```json
{
    "Paths": {
        "EvidenceRoot": "${ScriptRoot}\\Evidence",
        "FTK": "D:\\FullDiskImages\\${ComputerName}",
        "EnableCustomPaths": true
    }
}
```

**Supported Variables:**
- `${ScriptRoot}` - Script directory (e.g., `C:\ProgramData\Google\Project_Cerberus`)
- `${ComputerName}` - Computer name (e.g., `DC01-2016`)
- `${Domain}` - Domain name or `WORKGROUP` (e.g., `morm.gov.mk`)

**Verification:**
```bash
# Check where FTK images are stored
execute --command "dir D:\FullDiskImages\ /s"

# Check logs for path confirmation
get-file --path "C:/ProgramData/Google/Project_Cerberus/Logs/cerberus-*.log"
```

### Domain Naming: Including domain in zip filenames
**Problem:** Multiple domains/workgroups need clear identification in uploaded files.

**Solution:**
```json
{
    "Naming": {
        "IncludeDomain": true
    }
}
```

**Result Examples:**
- Domain-joined: `DC01-2016-morm.gov.mk-FTK.zip`
- Workgroup: `DESKTOP-ABC123-WORKGROUP-THOR.zip`

**Backward Compatibility:**
Set `IncludeDomain: false` for standard naming: `HOSTNAME-Tool.zip`

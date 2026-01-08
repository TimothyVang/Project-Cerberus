# Elastic Response Console - Project Cerberus Deployment Commands

## Overview
This document provides step-by-step commands for deploying and executing the unified **Project Cerberus Kit** via Elastic Response Console.

---

## Phase 1: Staging Cerberus

### 1. Upload Kit
```bash
upload --file "Project_Cerberus.zip" --comment "Upload Unified DFIR Kit"
```

### 2. Extract to ProgramData
```bash
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Project_Cerberus.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract Cerberus Kit"
```

### 3. Verify Deployment
```bash
execute --command "dir \"C:\ProgramData\Google\Project_Cerberus\"" --comment "Verify extraction"
```

---

## Phase 2: Execution Scenarios

### Option A: THOR Malware Scan
*Standard malware and IOC scan. Output uploads to MinIO automatically.*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus\Cerberus_Agent.ps1\" -Tool THOR" --timeout 86400s --comment "THOR Scan (Remote)"
```
*Monitor process:* `processes --comment "Check for thor64-lite.exe"`

### Option B: KAPE Triage (Forensic Artifacts - NOT Full Disk)
*Collects Registry, Event Logs, Prefetch, MFT, Amcache, etc. into VHDX*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus\Cerberus_Agent.ps1\" -Tool KAPE-TRIAGE" --timeout 3600s --comment "KAPE Triage Collection"
```
**Note:** KAPE-TRIAGE collects specific artifacts (2-5GB), not a complete disk image.

### Option C: KAPE RAM Capture (Memory Only)
*Dumps system memory - does NOT image the disk*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus\Cerberus_Agent.ps1\" -Tool KAPE-RAM" --timeout 3600s --comment "RAM Capture"
```

### Option D: FTK Full Disk Acquisition (Complete Disk Image)
*Creates bit-for-bit RAW disk image of C: drive (20-100GB+)*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus\Cerberus_Agent.ps1\" -Tool FTK" --timeout 172800s --comment "Full Disk Acquisition"
```
**Note:** For complete forensic disk imaging, use FTK (not KAPE).

---

## Phase 3: Verification & Recovery

### Check Evidence Folder
```bash
execute --command "dir \"C:\ProgramData\Google\Project_Cerberus\Evidence\" /s" --comment "List collected evidence"
```

### Retry Uploads (If MinIO failed)
*The Agent does NOT delete evidence. You can retry the upload step only.*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus\Cerberus_Agent.ps1\" -UploadOnly" --timeout 7200s --comment "Retry MinIO Upload"
```

---

## Configuration Note
*   **MinIO Credentials**: configured in `Cerberus_Config.json`.
*   **Tool Arguments**: Configurable in `Cerberus_Config.json`.

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

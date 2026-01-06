# Elastic Response Console - Project Cerberus Deployment Commands

## Overview
This document provides step-by-step commands for deploying and executing the unified **Project Cerberus Kit** via Elastic Response Console.

---

## Phase 1: Staging Cerberus

### 1. Upload Kit
```bash
upload --file "Project_Cerberus_Kit.zip" --comment "Upload Unified DFIR Kit"
```

### 2. Extract to ProgramData
```bash
execute --command "powershell.exe -command Expand-Archive -Force -Path 'C:\Program Files\Elastic\Endpoint\state\response_actions\Project_Cerberus_Kit.zip' -DestinationPath 'C:\ProgramData\Google'" --comment "Extract Cerberus Kit"
```

### 3. Verify Deployment
```bash
execute --command "dir \"C:\ProgramData\Google\Project_Cerberus_Kit\"" --comment "Verify extraction"
```

---

## Phase 2: Execution Scenarios

### Option A: THOR Malware Scan
*Standard malware and IOC scan. Output uploads to MinIO automatically.*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool THOR" --timeout 86400s --comment "THOR Scan (Remote)"
```
*Monitor process:* `processes --comment "Check for thor64-lite.exe"`

### Option B: KAPE Triage (Artifacts)
*Collects Event Logs, Registry, Prefetch, Amcache, etc.*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool KAPE-TRIAGE" --timeout 3600s --comment "KAPE Triage Collection"
```

### Option C: KAPE RAM Capture
*Dumps system memory.*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool KAPE-RAM" --timeout 3600s --comment "RAM Capture"
```

### Option D: FTK Full Disk Acquisition
*Acquires PhysicalDrive0 to E01 format with verification.*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -Tool FTK" --timeout 172800s --comment "Full Disk Acquisition"
```

---

## Phase 3: Verification & Recovery

### Check Evidence Folder
```bash
execute --command "dir \"C:\ProgramData\Google\Project_Cerberus_Kit\Evidence\" /s" --comment "List collected evidence"
```

### Retry Uploads (If MinIO failed)
*The Agent does NOT delete evidence. You can retry the upload step only.*
```bash
execute --command "powershell.exe -ExecutionPolicy Bypass -File \"C:\ProgramData\Google\Project_Cerberus_Kit\Cerberus_Agent.ps1\" -UploadOnly" --timeout 7200s --comment "Retry MinIO Upload"
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
# ❌ Wrong
mc put "Evidence\folder" "cerberus/upload"

# ✅ Correct (for directory)
mc cp --recursive "Evidence\folder" "cerberus/upload/" --insecure

# ✅ Correct (for file)
mc cp "Evidence\file.zip" "cerberus/upload/" --insecure
```

@echo off
setlocal EnableDelayedExpansion
title Project Cerberus - Incident Response Kit
color 0A

:: Check for Administrator Privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo   [ERROR] ADMIN RIGHTS REQUIRED
    echo   -----------------------------
    echo   This tool needs to read raw disk/memory.
    echo   Please right-click and "Run as Administrator".
    echo.
    pause
    exit /b
)

:: ============================================================================
::  PROJECT CERBERUS LAUNCHER
::  "One Tool to Rule Them All" (Legacy + Modern Support)
:: ============================================================================

:: 1. SET HOME DIRECTORY
:: %~dp0 is a special variable that means "The folder this script is in"
set "KIT_ROOT=%~dp0"
set "BIN=%KIT_ROOT%Bin"
set "EVIDENCE=%KIT_ROOT%Evidence"
set "LOGS=%KIT_ROOT%Logs"

:: Create Evidence folder if missing
if not exist "%EVIDENCE%" (
    mkdir "%EVIDENCE%"
    if !errorlevel! neq 0 (
        echo.
        echo   [ERROR] Failed to create Evidence directory
        echo   [ERROR] Check permissions or disk space
        echo.
        pause
        exit /b 1
    )
)

if not exist "%LOGS%" (
    mkdir "%LOGS%"
    if !errorlevel! neq 0 (
        echo.
        echo   [ERROR] Failed to create Logs directory
        echo   [ERROR] Check permissions or disk space
        echo.
        pause
        exit /b 1
    )
)

:MAIN_MENU
cls
echo.
color 0B
echo   =========================================================================
echo    .d8888b.                    888
echo   d88P  Y88b                   888
echo   888    888                   888
echo   888        .d88b.  888d888   88888b.   .d88b.  888d888 888  888 .d8888b
echo   888       d8P  Y8b 888P"     888 "88b d8P  Y8b 888P"   888  888 88K
echo   888    888 88888888 888       888  888 88888888 888     888  888 "Y8888b.
echo   Y88b  d88P Y8b.     888       888 d88P Y8b.     888     Y88b 888      X88
echo    "Y8888P"   "Y8888  888       88888P"   "Y8888  888      "Y88888  88888P'
echo   =========================================================================
echo.
echo            APT Scanner    Artifact         Disk Imager
echo             (THOR)       Collector          (FTK)
echo                          (KAPE)
echo                ^^            ^^            ^^
echo             .-"""-.       .-"""-.      .-"""-.
echo            /  o o  \     /  o o  \    /  o o  \
echo           (    ^    )   (    ^    )  (    ^    )
echo            \  \_/  /     \  \_/  /    \  \_/  /
echo             '-----'       '-----'      '-----'
echo              \   \         \   \        /   /
echo               \   \_________\   \______/   /
echo                \                          /
echo                 \    THE THREE-HEADED    /
echo                  \    DFIR WATCHDOG      /
echo                   \____________________/
echo                          /    \
echo                         /      \
echo                        /        \
echo   =========================================================================
echo   Author: PUG  ^|  Project Cerberus DFIR Triage Kit
echo   =========================================================================
echo.
echo    [ SYSTEM INFO ]
echo    Computer: %COMPUTERNAME%
echo    User:     %USERNAME%
for /f "tokens=*" %%i in ('ver') do set "OS_VERSION=%%i"
echo    OS:       !OS_VERSION!
echo.
echo   +-----------------------------------------------------------------------+
echo   ^|                   WELCOME TO PROJECT CERBERUS                         ^|
echo   ^|                        DFIR TRIAGE TOOLKIT                            ^|
echo   +-----------------------------------------------------------------------+
echo.
echo   WHAT IS YOUR OPERATING SYSTEM?
echo.
echo   [1] MODERN System (Windows 10, 11, Server 2012 or newer)
echo       ^^
echo       ^|__ If your computer is from 2015 or later, choose this!
echo       ^|__ Fast tools with advanced features
echo       ^|__ Includes: KAPE (artifact collector), THOR (malware scanner),
echo       ^|            FTK (disk imager)
echo.
echo   [2] LEGACY System (Windows XP, Server 2003, Server 2008, Vista)
echo       ^^
echo       ^|__ If your computer is OLD (before 2012), choose this!
echo       ^|__ Safe low-priority tools that won't crash old systems
echo       ^|__ Includes: FTK x86 (memory ^& disk imaging), THOR Lite x86
echo.
echo   [Q] Quit - Exit the program
echo.
echo   +-----------------------------------------------------------------------+
echo   HOW TO USE: Type the number (1 or 2) and press ENTER
echo   +-----------------------------------------------------------------------+
echo.
set "Choice="
set /p "Choice=[?] Enter your choice (1, 2, or Q): "

if /I "!Choice!"=="1" goto MODERN_MODE
if /I "!Choice!"=="2" goto LEGACY_MODE
if /I "!Choice!"=="Q" exit /b
goto MAIN_MENU

:: ============================================================================
::  MODERN MODE (The Fast Lane)
:: ============================================================================
:MODERN_MODE
cls
echo.
echo   ========================================================================
echo   [ MODERN TRIAGE MENU - Windows 10/11/Server 2012+ ]
echo   ========================================================================
echo.
echo   CHOOSE A FORENSIC TOOL:
echo.
echo   [1] KAPE - Quick Evidence Collection (RECOMMENDED FOR BEGINNERS)
echo       ^^
echo       ^|__ WHAT IT DOES: Collects important files for investigation
echo       ^|__ COLLECTS: Registry hives, event logs, browser history,
echo       ^|             prefetch files, scheduled tasks, and more
echo       ^|__ TIME: 5-30 minutes  ^|  DISK SPACE NEEDED: 500MB - 5GB
echo       ^|__ BEST FOR: Fast triage when you need evidence quickly
echo.
echo   [2] THOR - Malware Scanner (Checks for viruses and hacking tools)
echo       ^^
echo       ^|__ WHAT IT DOES: Scans your entire system for malware
echo       ^|__ FINDS: Viruses, ransomware, APT tools, rootkits, IOCs
echo       ^|__ TIME: 1-4 hours  ^|  DISK SPACE NEEDED: ~50MB
echo       ^|__ BEST FOR: Checking if system is compromised/infected
echo.
echo   [3] FTK - Complete Disk or Memory Copy (For advanced users)
echo       ^^
echo       ^|__ WHAT IT DOES: Makes exact copy of hard drive or RAM
echo       ^|__ CREATES: Forensic disk image or memory dump
echo       ^|__ TIME: 2-8 hours  ^|  DISK SPACE NEEDED: 10GB - 100GB+
echo       ^|__ BEST FOR: Deep forensic analysis, legal evidence
echo       ^|__ WARNING: Takes LONG time and LOTS of space!
echo.
echo   [B] Back - Return to main menu
echo.
echo   ========================================================================
echo   HOW TO USE: Type a number (1, 2, or 3) and press ENTER
echo   ========================================================================
set "MChoice="
set /p "MChoice=[?] Enter your choice: "

if /I "!MChoice!"=="1" goto KAPE_MENU

if /I "!MChoice!"=="2" (
    cls
    echo.
    echo   ====================================================================
    echo   THOR MALWARE SCANNER
    echo   ====================================================================
    echo.
    echo   This will scan your system for:
    echo   - Malware signatures and IOCs
    echo   - APT indicators and suspicious files
    echo   - Registry persistence mechanisms
    echo   - Rootkits and anomalies
    echo.
    echo   ESTIMATED TIME: 1-4 hours (depends on system size)
    echo   OUTPUT: %EVIDENCE%\%COMPUTERNAME%_THOR
    echo.
    echo   ====================================================================
    echo.
    set /p "Confirm=Continue with THOR scan? (Y/N): "
    if /I not "!Confirm!"=="Y" goto MODERN_MODE

    echo.
    echo [INFO] Creating output directory...
    if not exist "%EVIDENCE%\%COMPUTERNAME%_THOR" mkdir "%EVIDENCE%\%COMPUTERNAME%_THOR"

    echo [INFO] Starting THOR scan...
    echo [INFO] Progress will be shown in the THOR window that opens.
    echo [WAIT] Do not close this window or the THOR window!
    echo.

    :: Arguments: --utc --nothordb
    start /wait "" "%BIN%\THOR\thor64-lite.exe" --logfile "%EVIDENCE%\%COMPUTERNAME%_THOR\%COMPUTERNAME%.txt" --htmlfile "%EVIDENCE%\%COMPUTERNAME%_THOR\%COMPUTERNAME%.html" --utc --nothordb

    echo.
    echo   ====================================================================
    echo   [SUCCESS] THOR Scan Complete!
    echo   ====================================================================
    echo.
    echo   Results saved to:
    echo   - Text log:  %EVIDENCE%\%COMPUTERNAME%_THOR\%COMPUTERNAME%.txt
    echo   - HTML report: %EVIDENCE%\%COMPUTERNAME%_THOR\%COMPUTERNAME%.html
    echo.
    echo   Review the HTML report for findings and alerts.
    echo   ====================================================================
    echo.
    pause
    goto MODERN_MODE
)

if /I "!MChoice!"=="3" goto FTK_MENU

if /I "!MChoice!"=="B" goto MAIN_MENU
goto MODERN_MODE

:: ============================================================================
::  KAPE SUB-MENU (Choose Your Collection)
:: ============================================================================
:KAPE_MENU
cls
echo.
echo   ========================================================================
echo   [ KAPE - EVIDENCE COLLECTOR ]
echo   ========================================================================
echo.
echo   WHAT KIND OF EVIDENCE DO YOU WANT TO COLLECT?
echo.
echo   [1] Quick Collection (RECOMMENDED - Fast and Essential)
echo       ^^
echo       ^|__ WHAT IT COLLECTS: The most important evidence files
echo       ^|__ INCLUDES: Registry files, Windows event logs, prefetch,
echo       ^|             file system journal, user activity traces
echo       ^|__ TIME: 5-10 minutes  ^|  SPACE: 500MB - 2GB
echo       ^|__ BEST FOR: Quick incident response, most cases
echo.
echo   [2] Full Collection (Everything + Server Files)
echo       ^^
echo       ^|__ WHAT IT COLLECTS: Everything from Quick + server logs
echo       ^|__ INCLUDES: All Quick items PLUS IIS logs, Exchange data,
echo       ^|             memory files, MOF files, BITS transfers
echo       ^|__ TIME: 15-30 minutes  ^|  SPACE: 2GB - 5GB
echo       ^|__ BEST FOR: Servers, comprehensive investigations
echo.
echo   [3] Disk-Only Collection (Files without RAM capture)
echo       ^^
echo       ^|__ WHAT IT COLLECTS: Same as Quick but NO memory files
echo       ^|__ INCLUDES: Registry, event logs, prefetch, MFT, USN journal
echo       ^|__ EXCLUDES: Memory/RAM files (pagefile, hiberfil, swapfile)
echo       ^|__ TIME: 3-8 minutes  ^|  SPACE: 300MB - 1.5GB (smaller)
echo       ^|__ BEST FOR: When you don't need memory analysis
echo.
echo   [4] RAM Memory Capture (Capture what's running NOW)
echo       ^^
echo       ^|__ WHAT IT DOES: Saves a copy of everything in RAM memory
echo       ^|__ CAPTURES: Running programs, passwords in memory, malware
echo       ^|__ TIME: 5-15 minutes  ^|  SPACE: Same size as your RAM
echo       ^|__ BEST FOR: Catching malware in memory, volatile data
echo       ^|__ EXAMPLE: If you have 8GB RAM, this creates an 8GB file
echo.
echo   [5] Custom Targets (For experts who know what they want)
echo       ^^
echo       ^|__ Lets you manually type which evidence types to collect
echo       ^|__ Requires knowledge of KAPE target names
echo.
echo   [B] Back - Return to tools menu
echo.
echo   ========================================================================
echo   HOW TO USE: Type a number (1-5) and press ENTER
echo   ========================================================================
set "KChoice="
set /p "KChoice=[?] Enter your choice: "

if /I "!KChoice!"=="1" (
    cls
    echo.
    echo   ====================================================================
    echo   QUICK TRIAGE COLLECTION
    echo   ====================================================================
    echo.
    echo   Collecting: !SANS_Triage
    echo   Output: %EVIDENCE%\%COMPUTERNAME%_KAPE_Quick
    echo.
    echo   [INFO] Starting KAPE...
    echo   [INFO] KAPE GUI will open in a new window.
    echo.

    setlocal DisableDelayedExpansion
    "%BIN%\KAPE\kape.exe" --tsource C: --tdest "%EVIDENCE%\%COMPUTERNAME%_KAPE_Quick" --tflush --target !SANS_Triage --gui
    endlocal

    echo.
    echo   ====================================================================
    echo   [SUCCESS] Quick Triage Complete!
    echo   ====================================================================
    echo.
    echo   Evidence Location: %EVIDENCE%\%COMPUTERNAME%_KAPE_Quick
    echo.
    pause
    goto KAPE_MENU
)

if /I "!KChoice!"=="2" (
    cls
    echo.
    echo   ====================================================================
    echo   FULL TRIAGE COLLECTION
    echo   ====================================================================
    echo.
    echo   Collecting: !SANS_Triage + IIS + Exchange + Memory + MOF + BITS
    echo   Output: %EVIDENCE%\%COMPUTERNAME%_KAPE_Full
    echo.
    echo   [INFO] This may take 15-30 minutes...
    echo   [INFO] KAPE GUI will open in a new window.
    echo.

    setlocal DisableDelayedExpansion
    "%BIN%\KAPE\kape.exe" --tsource C: --tdest "%EVIDENCE%\%COMPUTERNAME%_KAPE_Full" --tflush --target !SANS_Triage,IISLogFiles,Exchange,ExchangeCve-2021-26855,MemoryFiles,MOF,BITS --gui
    endlocal

    echo.
    echo   ====================================================================
    echo   [SUCCESS] Full Triage Complete!
    echo   ====================================================================
    echo.
    echo   Evidence Location: %EVIDENCE%\%COMPUTERNAME%_KAPE_Full
    echo.
    pause
    goto KAPE_MENU
)

if /I "!KChoice!"=="3" (
    cls
    echo.
    echo   ====================================================================
    echo   DISK-ONLY COLLECTION (No Memory Files)
    echo   ====================================================================
    echo.
    echo   Collecting: !SANS_Triage (excluding MemoryFiles)
    echo   Output: %EVIDENCE%\%COMPUTERNAME%_KAPE_DiskOnly
    echo.
    echo   [INFO] This collects the same files as Quick Triage but
    echo   [INFO] EXCLUDES large memory files (pagefile, hiberfil, swapfile)
    echo   [INFO] This is faster and uses less disk space.
    echo.
    echo   ====================================================================
    echo.
    set /p "Confirm=Continue with Disk-Only collection? (Y/N): "
    if /I not "!Confirm!"=="Y" goto KAPE_MENU

    echo.
    echo   [INFO] Starting KAPE collection...
    echo   [INFO] KAPE GUI will open in a new window.
    echo.

    setlocal DisableDelayedExpansion
    "%BIN%\KAPE\kape.exe" --tsource C: --tdest "%EVIDENCE%\%COMPUTERNAME%_KAPE_DiskOnly" --tflush --target !SANS_Triage --gui
    endlocal

    echo.
    echo   ====================================================================
    echo   [SUCCESS] Disk-Only Collection Complete!
    echo   ====================================================================
    echo.
    echo   Evidence Location: %EVIDENCE%\%COMPUTERNAME%_KAPE_DiskOnly
    echo.
    pause
    goto KAPE_MENU
)

if /I "!KChoice!"=="4" (
    cls
    echo.
    echo   ====================================================================
    echo   RAM MEMORY CAPTURE
    echo   ====================================================================
    echo.
    echo   Module: MagnetForensics_RAMCapture
    echo   Output: %EVIDENCE%\%COMPUTERNAME%_RAM
    echo.
    echo   [WARN] Output size will equal your installed RAM!
    echo   [INFO] Ensure you have enough free space before continuing.
    echo.
    echo   ====================================================================
    echo.
    set /p "Confirm=Continue with RAM capture? (Y/N): "
    if /I not "!Confirm!"=="Y" goto KAPE_MENU

    echo.
    echo   [INFO] Starting memory capture...
    echo   [INFO] KAPE GUI will open in a new window.
    echo.

    setlocal DisableDelayedExpansion
    "%BIN%\KAPE\kape.exe" --msource C:\ --mdest "%EVIDENCE%\%COMPUTERNAME%_RAM" --zm true --module MagnetForensics_RAMCapture --gui
    endlocal

    echo.
    echo   ====================================================================
    echo   [SUCCESS] RAM Capture Complete!
    echo   ====================================================================
    echo.
    echo   Memory Image: %EVIDENCE%\%COMPUTERNAME%_RAM
    echo.
    pause
    goto KAPE_MENU
)

if /I "!KChoice!"=="4" (
    cls
    echo.
    echo   ====================================================================
    echo   CUSTOM TARGET COLLECTION
    echo   ====================================================================
    echo.
    echo   Enter KAPE targets separated by commas (no spaces).
    echo.
    echo   Common targets:
    echo   - !SANS_Triage        Registry, logs, prefetch, MFT
    echo   - WebBrowsers         All browser history/cache
    echo   - RegistryHives       Registry hives only
    echo   - CloudStorage_All    OneDrive, Dropbox, etc.
    echo   - EventLogs           Windows Event Logs
    echo   - $MFT                Master File Table
    echo.
    echo   Example: !SANS_Triage,WebBrowsers,CloudStorage_All
    echo.
    echo   ====================================================================
    echo.
    set "CustomTargets="
    set /p "CustomTargets=Enter target list: "

    if "!CustomTargets!"=="" (
        echo.
        echo [ERROR] No targets entered.
        pause
        goto KAPE_MENU
    )

    echo.
    echo   [INFO] Custom Collection: !CustomTargets!
    echo   [INFO] Output: %EVIDENCE%\%COMPUTERNAME%_KAPE_Custom
    echo   [INFO] KAPE GUI will open in a new window.
    echo.

    setlocal DisableDelayedExpansion
    "%BIN%\KAPE\kape.exe" --tsource C: --tdest "%EVIDENCE%\%COMPUTERNAME%_KAPE_Custom" --tflush --target !CustomTargets! --gui
    endlocal

    echo.
    echo   ====================================================================
    echo   [SUCCESS] Custom Collection Complete!
    echo   ====================================================================
    echo.
    echo   Evidence Location: %EVIDENCE%\%COMPUTERNAME%_KAPE_Custom
    echo.
    pause
    goto KAPE_MENU
)

if /I "!KChoice!"=="B" goto MODERN_MODE
goto KAPE_MENU

:: ============================================================================
::  FTK IMAGER SUB-MENU (Disk or Memory)
:: ============================================================================
:FTK_MENU
cls
echo.
echo   ========================================================================
echo   [ FTK IMAGER - COMPLETE FORENSIC COPY TOOL ]
echo   ========================================================================
echo.
echo   WARNING: These are ADVANCED tools that take a LONG time!
echo            Only use if you know what you're doing.
echo.
echo   [1] Disk Image - Make EXACT copy of entire C: drive
echo       ^^
echo       ^|__ WHAT IT DOES: Creates bit-for-bit copy of your hard drive
echo       ^|__ CAPTURES: EVERYTHING on C: drive (deleted files too!)
echo       ^|__ TIME: 2-8 hours  ^|  SPACE: 20GB - 100GB+ (huge file!)
echo       ^|__ FILE FORMAT: RAW image, compressed, split into chunks
echo       ^|__ BEST FOR: Legal evidence, deep forensics, deleted file recovery
echo       ^|__ WARNING: This takes HOURS! Don't interrupt or turn off PC!
echo.
echo   [2] Memory Dump - Copy everything in RAM right NOW
echo       ^^
echo       ^|__ WHAT IT DOES: Captures snapshot of RAM memory
echo       ^|__ CAPTURES: Running programs, open files, passwords in memory
echo       ^|__ TIME: 5-15 minutes  ^|  SPACE: Same size as your RAM
echo       ^|__ FILE FORMAT: .mem file with compression
echo       ^|__ BEST FOR: Malware analysis, volatile data preservation
echo       ^|__ EXAMPLE: 16GB RAM = creates 16GB memory dump file
echo.
echo   [B] Back - Return to tools menu
echo.
echo   ========================================================================
echo   HOW TO USE: Type 1 or 2 and press ENTER (This takes a LONG time!)
echo   ========================================================================
set "FChoice="
set /p "FChoice=[?] Enter your choice: "

if /I "!FChoice!"=="1" (
    cls
    echo.
    echo   ====================================================================
    echo   DISK IMAGE ACQUISITION - C: DRIVE
    echo   ====================================================================
    echo.

    if not exist "%BIN%\FTK\x64\ftkimager.exe" (
        echo   [ERROR] FTK Imager (x64) not found!
        echo.
        echo   Expected location: %BIN%\FTK\x64\ftkimager.exe
        echo   Please verify the tool is installed correctly.
        echo.
        pause
        goto FTK_MENU
    )

    echo   Drive: C: (Logical Volume)
    echo   Output: %EVIDENCE%\%COMPUTERNAME%_Disk.raw
    echo   Format: RAW with maximum compression
    echo   Fragment Size: 1TB segments
    echo.
    echo   [WARN] This creates VERY LARGE files!
    echo   [WARN] Ensure you have 50GB+ free space.
    echo   [WARN] This will take 2-8 hours depending on disk size.
    echo.
    echo   ====================================================================
    echo.
    set /p "Confirm=Continue with disk imaging? (Y/N): "
    if /I not "!Confirm!"=="Y" goto FTK_MENU

    echo.
    echo   [INFO] Starting FTK Imager...
    echo   [INFO] Progress will be shown in the FTK window.
    echo   [WAIT] Do not close this window during imaging!
    echo.

    start /low /wait "" "%BIN%\FTK\x64\ftkimager.exe" C: "%EVIDENCE%\%COMPUTERNAME%_Disk.raw" --compress 9 --frag 1TB

    echo.
    echo   ====================================================================
    echo   [SUCCESS] Disk Image Complete!
    echo   ====================================================================
    echo.
    echo   Image Location: %EVIDENCE%\%COMPUTERNAME%_Disk.raw
    echo.
    echo   Note: If image is larger than 1TB, it will be split into:
    echo   - %COMPUTERNAME%_Disk.raw
    echo   - %COMPUTERNAME%_Disk.raw.001
    echo   - %COMPUTERNAME%_Disk.raw.002 (etc.)
    echo.
    pause
    goto FTK_MENU
)

if /I "!FChoice!"=="2" (
    cls
    echo.
    echo   ====================================================================
    echo   MEMORY DUMP ACQUISITION
    echo   ====================================================================
    echo.

    if not exist "%BIN%\FTK\x64\ftkimager.exe" (
        echo   [ERROR] FTK Imager (x64) not found!
        echo.
        echo   Expected location: %BIN%\FTK\x64\ftkimager.exe
        echo.
        pause
        goto FTK_MENU
    )

    echo   Output: %EVIDENCE%\%COMPUTERNAME%_Memory.mem
    echo   Format: .mem with light compression
    echo.
    echo   [INFO] Memory dump size will equal your installed RAM.
    echo   [INFO] Example: 16GB RAM = ~16GB file
    echo.
    echo   ====================================================================
    echo.
    set /p "Confirm=Continue with memory capture? (Y/N): "
    if /I not "!Confirm!"=="Y" goto FTK_MENU

    echo.
    echo   [INFO] Starting memory capture...
    echo   [INFO] Progress will be shown in the FTK window.
    echo.

    start /wait "" "%BIN%\FTK\x64\ftkimager.exe" --capture-memory "%EVIDENCE%\%COMPUTERNAME%_Memory.mem" --compress 1

    echo.
    echo   ====================================================================
    echo   [SUCCESS] Memory Capture Complete!
    echo   ====================================================================
    echo.
    echo   Memory Dump: %EVIDENCE%\%COMPUTERNAME%_Memory.mem
    echo.
    pause
    goto FTK_MENU
)

if /I "!FChoice!"=="B" goto MODERN_MODE
goto FTK_MENU

:: ============================================================================
::  LEGACY MODE (The Safe Lane)
::  * No PowerShell dependencies if possible *
::  * Uses start /low to protect fragile CPUs *
:: ============================================================================
:LEGACY_MODE
cls
echo.
echo   ========================================================================
echo   [ LEGACY MODE - For OLD Computers (XP/2003/2008/Vista) ]
echo   ========================================================================
echo.
echo   IMPORTANT - PLEASE READ:
echo   This mode uses SAFE tools designed for old, slow computers.
echo   All tools run at LOW priority so your computer won't freeze or crash.
echo.
echo   +----------------------------------------------------------------------+
echo   ^|  WHAT MAKES THIS SAFE FOR OLD COMPUTERS:                            ^|
echo   ^|  - Uses 32-bit (x86) programs that work on old systems              ^|
echo   ^|  - Runs at LOW CPU priority (won't slow down your computer)         ^|
echo   ^|  - No PowerShell required (old systems don't have it)               ^|
echo   ^|  - Takes longer but won't crash your system                         ^|
echo   +----------------------------------------------------------------------+
echo.
echo   [1] Memory Capture - Copy RAM (Safe for old systems)
echo       ^^
echo       ^|__ WHAT IT DOES: Captures what's in your computer's memory
echo       ^|__ RUNS: FTK Imager x86 (32-bit version)
echo       ^|__ TIME: 10-20 minutes (slower than modern mode)
echo       ^|__ SPACE: Same size as your RAM (example: 2GB RAM = 2GB file)
echo       ^|__ SAFETY: Runs at LOW priority - won't freeze your PC
echo.
echo   [2] Disk Image - Copy entire C: drive (Takes MANY hours!)
echo       ^^
echo       ^|__ WHAT IT DOES: Makes complete copy of C: drive
echo       ^|__ RUNS: FTK Imager x86 (32-bit version)
echo       ^|__ TIME: 3-10 hours (depends on hard drive size)
echo       ^|__ SPACE: 20GB - 100GB+ (needs LOTS of free space!)
echo       ^|__ SAFETY: Runs at LOW priority - safe but SLOW
echo       ^|__ WARNING: Do NOT turn off computer while running!
echo.
echo   [B] Back - Return to main menu
echo.
echo   ========================================================================
echo   HOW TO USE: Type 1 or 2 and press ENTER
echo   ========================================================================
set "LChoice="
set /p "LChoice=[?] Enter your choice: "

if /I "!LChoice!"=="1" (
    cls
    echo.
    echo   ====================================================================
    echo   LEGACY MEMORY CAPTURE
    echo   ====================================================================
    echo.

    if not exist "%BIN%\FTK\x86\ftkimager.exe" (
        echo   [ERROR] FTK x86 binary not found!
        echo.
        echo   Expected: %BIN%\FTK\x86\ftkimager.exe
        echo   Please verify the legacy version is installed.
        echo.
        pause
        goto LEGACY_MODE
    )

    echo   Tool: FTK Imager x86 (32-bit)
    echo   Output: %EVIDENCE%\%COMPUTERNAME%_Memory.mem
    echo   Priority: LOW (system-safe)
    echo.
    echo   [INFO] Memory size will equal installed RAM.
    echo   [INFO] Running at low priority to prevent system stress.
    echo.
    echo   ====================================================================
    echo.
    set /p "Confirm=Continue? (Y/N): "
    if /I not "!Confirm!"=="Y" goto LEGACY_MODE

    echo.
    echo   [INFO] Starting memory capture...
    echo   [INFO] Running with LOW CPU priority for system safety.
    echo.

    start /low /wait "" "%BIN%\FTK\x86\ftkimager.exe" --capture-memory "%EVIDENCE%\%COMPUTERNAME%_Memory.mem" --compress 1

    echo.
    echo   ====================================================================
    echo   [SUCCESS] Memory Capture Complete!
    echo   ====================================================================
    echo.
    echo   Memory Dump: %EVIDENCE%\%COMPUTERNAME%_Memory.mem
    echo.
    pause
    goto LEGACY_MODE
)

if /I "!LChoice!"=="2" (
    cls
    echo.
    echo   ====================================================================
    echo   LEGACY DISK IMAGE - C: DRIVE
    echo   ====================================================================
    echo.

    if not exist "%BIN%\FTK\x86\ftkimager.exe" (
        echo   [ERROR] FTK x86 binary not found!
        echo.
        echo   Expected: %BIN%\FTK\x86\ftkimager.exe
        echo.
        pause
        goto LEGACY_MODE
    )

    echo   Tool: FTK Imager x86 (32-bit)
    echo   Drive: C: (Logical Volume)
    echo   Output: %EVIDENCE%\%COMPUTERNAME%_Disk.raw
    echo   Priority: LOW (system-safe)
    echo   Format: RAW with maximum compression
    echo.
    echo   [WARN] This creates VERY LARGE files!
    echo   [WARN] Ensure 50GB+ free space on your USB drive.
    echo   [WARN] Expect 3-10 hours on older systems.
    echo.
    echo   ====================================================================
    echo.
    set /p "Confirm=Continue with disk imaging? (Y/N): "
    if /I not "!Confirm!"=="Y" goto LEGACY_MODE

    echo.
    echo   [INFO] Starting disk imaging...
    echo   [INFO] Running with LOW CPU priority for system safety.
    echo   [INFO] Do not interrupt or power off during imaging!
    echo.

    start /low /wait "" "%BIN%\FTK\x86\ftkimager.exe" C: "%EVIDENCE%\%COMPUTERNAME%_Disk.raw" --compress 9 --frag 1TB

    echo.
    echo   ====================================================================
    echo   [SUCCESS] Disk Image Complete!
    echo   ====================================================================
    echo.
    echo   Image Location: %EVIDENCE%\%COMPUTERNAME%_Disk.raw
    echo.
    pause
    goto LEGACY_MODE
)

if /I "!LChoice!"=="B" goto MAIN_MENU
goto LEGACY_MODE

:: ============================================================================
::  CLEANUP (Surgical)
:: ============================================================================
:CLEANUP
cls
echo.
echo   ========================================================================
echo   [ CLEANUP MODE ]
echo   ========================================================================
echo.
echo   This option cleans temporary files left by forensic tools.
echo.
echo   IMPORTANT NOTES:
echo   - Evidence folder is NEVER deleted (forensic integrity)
echo   - Only temporary working files are removed
echo   - KAPE/THOR/FTK typically self-clean
echo.
echo   ========================================================================
echo.
echo   [INFO] Checking for temporary files...
echo.

:: Check for KAPE temp directories
if exist "%BIN%\KAPE\Temp" (
    echo   [FOUND] KAPE Temp directory
    rmdir /s /q "%BIN%\KAPE\Temp" 2>nul
    echo   [CLEAN] KAPE Temp removed
)

:: Check for temporary log files in root (using proper for loop)
set "FOUND_TMP=0"
for %%i in ("%KIT_ROOT%*.tmp") do (
    if exist "%%i" (
        if "!FOUND_TMP!"=="0" echo   [FOUND] Temporary files in kit root
        set "FOUND_TMP=1"
        del /q "%%i" 2>nul
    )
)
if "!FOUND_TMP!"=="1" echo   [CLEAN] Temporary files removed

:: Check for Windows temp files created by tools (using proper for /d loop)
set "FOUND_KAPE=0"
for /d %%i in ("%TEMP%\KAPE*") do (
    if exist "%%i" (
        if "!FOUND_KAPE!"=="0" echo   [FOUND] KAPE files in Windows Temp
        set "FOUND_KAPE=1"
        rmdir /s /q "%%i" 2>nul
    )
)
if "!FOUND_KAPE!"=="1" echo   [CLEAN] KAPE temp cleaned

set "FOUND_THOR=0"
for /d %%i in ("%TEMP%\Thor*") do (
    if exist "%%i" (
        if "!FOUND_THOR!"=="0" echo   [FOUND] THOR files in Windows Temp
        set "FOUND_THOR=1"
        rmdir /s /q "%%i" 2>nul
    )
)
if "!FOUND_THOR!"=="1" echo   [CLEAN] THOR temp cleaned

echo.
echo   ========================================================================
echo   [SUCCESS] Cleanup Complete!
echo   ========================================================================
echo.
echo   Evidence preserved at: %EVIDENCE%
echo   Tools remain ready at: %BIN%
echo.
echo   Your forensic evidence is safe and untouched.
echo.
pause
goto MAIN_MENU

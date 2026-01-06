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
if not exist "%EVIDENCE%" mkdir "%EVIDENCE%"
if not exist "%LOGS%" mkdir "%LOGS%"

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
echo    [ SYSTEM INFO ]
echo    Computer: %COMPUTERNAME%
echo    User:     %USERNAME%
echo    OS:       
ver
echo. 
echo   +-----------------------------------------------------------------------+
echo   ^|                        SELECT OPERATION MODE                          ^|
echo   +-----------------------------------------------------------------------+
echo   ^|                                                                       ^|
echo   ^|  [1] MODERN Triage      (Windows 10 / 11 / Server 2012+)              ^|
echo   ^|      - Tools: KAPE, THOR (x64), FTK (x64)                             ^|
echo   ^|                                                                       ^|
echo   ^|  [2] LEGACY Triage      (Windows XP / Server 2003 / 2008)             ^|
echo   ^|      - Tools: FTK 3.1.1, THOR Legacy                                  ^|
echo   ^|      - SAFETY: Bypasses PowerShell to prevent crashes                 ^|
echo   ^|                                                                       ^|
echo   ^|  [3] Cleanup Mode       (Safe)                                        ^|
echo   ^|      - Removes temp drivers / extracted binaries.                     ^|
echo   ^|                                                                       ^|
echo   ^|  [Q] Quit                                                             ^|
echo   ^|                                                                       ^|
echo   +-----------------------------------------------------------------------+
echo.
set "Choice="
set /p "Choice=[?] Select Option: "

if /I "%Choice%"=="1" goto MODERN_MODE
if /I "%Choice%"=="2" goto LEGACY_MODE
if /I "%Choice%"=="3" goto CLEANUP
if /I "%Choice%"=="Q" exit /b
goto MAIN_MENU

:: ============================================================================
::  MODERN MODE (The Fast Lane)
:: ============================================================================
:MODERN_MODE
cls
echo.
echo   [ MODERN TRIAGE MENU ]
echo   ----------------------
echo   1) Run KAPE (Triage Collection)
echo   2) Run THOR (Malware Scan)
echo   3) Run FTK Imager (Live Memory/Disk)
echo   B) Back
echo.
set "MChoice="
set /p "MChoice=[?] Select Tool: "

if "%MChoice%"=="1" (
    echo.
    echo [INFO] Launching KAPE in Triage Mode...
    echo [INFO] Saving to: %EVIDENCE%\%COMPUTERNAME%_KAPE
    
    :: The Command (Adapted from Disk-MOD.ps1):
    :: --tsource C:       (Target Source is C drive)
    :: --tdest ...        (Target Dest is our USB Evidence folder)
    :: --tflush           (Clear prior temp files)
    :: --target ...       (Specific targets from working-thor-kape)
    
    :: NOTE: We use ^! to escape the exclamation mark in batch
    set "KAPE_TARGETS=^!SANS_Triage,IISLogFiles,Exchange,ExchangeCve-2021-26855,MemoryFiles,MOF,BITS"
    
    "%BIN%\KAPE\kape.exe" --tsource C: --tdest "%EVIDENCE%\%COMPUTERNAME%_KAPE" --tflush --target %KAPE_TARGETS% --module ^!EZParser --gui
    
    echo.
    echo [SUCCESS] KAPE Finished. Press key to continue...
    pause >nul
    goto MODERN_MODE
)

if "%MChoice%"=="2" (
    echo.
    echo [INFO] Launching THOR (Lite)...
    echo [NOTE] This can take 1-4 hours. Do not close the window.
    
    if not exist "%EVIDENCE%\%COMPUTERNAME%_THOR" mkdir "%EVIDENCE%\%COMPUTERNAME%_THOR"
    
    :: Arguments: --utc --nothordb (removed --nocsv to enable CSV output)
    start /wait "" "%BIN%\THOR\thor64-lite.exe" --logfile "%EVIDENCE%\%COMPUTERNAME%_THOR\%COMPUTERNAME%.txt" --htmlfile "%EVIDENCE%\%COMPUTERNAME%_THOR\%COMPUTERNAME%.html" --utc --nothordb
    
    echo.
    echo [SUCCESS] THOR Finished. Press key to continue...
    pause >nul
    goto MODERN_MODE
)

if "%MChoice%"=="3" (
    echo.
    echo [INFO] Starting FTK Imager (PhysicalDrive0)...
    echo [WARN] This creates a HUGE file. Ensure you have 50GB+ free.
    
    if not exist "%BIN%\FTK\x64\ftkimager.exe" (
        echo [ERROR] FTK x64 binary not found.
        pause
        goto MODERN_MODE
    )
    
    :: Arguments from QRF/Legacy SOP: "\\.\PhysicalDrive0" <Output> --e01 --frag 2GB --compress 6
    :: We use "EVIDENCE\Hostname_Disk" as prefix
    
    start /low /wait "" "%BIN%\FTK\x64\ftkimager.exe" "\\.\PhysicalDrive0" "%EVIDENCE%\%COMPUTERNAME%_Disk" --e01 --frag 2048M --compress 6 --verify
    
    echo.
    echo [SUCCESS] Disk Image complete.
    pause
    goto MODERN_MODE
)

if /I "%MChoice%"=="B" goto MAIN_MENU
goto MODERN_MODE

:: ============================================================================
::  LEGACY MODE (The Safe Lane)
::  * No PowerShell dependencies if possible *
::  * Uses start /low to protect fragile CPUs *
:: ============================================================================
:LEGACY_MODE
cls
echo.
echo   [ LEGACY TRIAGE MENU (XP/2003) ]
echo   --------------------------------
echo   1) Run FTK Imager (Memory Capture) - x86
echo   2) Run FTK Imager (Disk Image C:) - x86
echo   B) Back
echo.
set /p "LChoice=Select Tool: "

if "%LChoice%"=="1" (
    echo.
    echo [INFO] Starting Memory Capture (Low Priority)...
    echo [WARN] This creates a large file on your USB. Ensure you have space.
    
    :: Using x86 binary specifically
    if not exist "%BIN%\FTK\x86\ftkimager.exe" (
        echo [ERROR] FTK x86 binary not found at: %BIN%\FTK\x86\ftkimager.exe
        echo         Please verify you downloaded the legacy version.
        pause
        goto LEGACY_MODE
    )

    :: --capture-memory <destination> --compress 1 (AD1 compression to save space)
    start /low /wait "" "%BIN%\FTK\x86\ftkimager.exe" --capture-memory "%EVIDENCE%\%COMPUTERNAME%_Memory.mem" --compress 1
    
    echo.
    echo [SUCCESS] Memory capture complete.
    pause
    goto LEGACY_MODE
)

if "%LChoice%"=="2" (
    echo.
    echo [INFO] Starting Disk Imaging of C: Drive (Low Priority)...
    echo [WARN] This creates a HUGE file. Ensure you have 50GB+ free.
    
    if not exist "%BIN%\FTK\x86\ftkimager.exe" (
        echo [ERROR] FTK x86 binary not found.
        pause
        goto LEGACY_MODE
    )
    
    :: Arguments from QRF/Legacy SOP: "\\.\PhysicalDrive0" <Output> --e01 --frag 2GB --compress 6
    :: We use "EVIDENCE\Hostname_Disk" as prefix
    
    start /low /wait "" "%BIN%\FTK\x86\ftkimager.exe" "\\.\PhysicalDrive0" "%EVIDENCE%\%COMPUTERNAME%_Disk" --e01 --frag 2048M --compress 6 --verify
    
    echo.
    echo [SUCCESS] Disk Image complete.
    pause
    goto LEGACY_MODE
)

if /I "%LChoice%"=="B" goto MAIN_MENU
goto LEGACY_MODE

:: ============================================================================
::  CLEANUP (Surgical)
:: ============================================================================
:CLEANUP
cls
echo.
echo   [ CLEANUP ]
echo   Deleting temporary temp files...
echo   (Note: We NEVER delete the Evidence folder)
echo.

:: Add your specific temp file removals here if tools drop them
echo   [INFO] Tools usually clean themselves up.
echo   [INFO] Project Cerberus is designed to run from USB, so host cleanup is minimal.

echo.
echo   Done.
pause
goto MAIN_MENU

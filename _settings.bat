@echo off
:: ==========================================
:: PROJECT CERBERUS - LOCAL SETTINGS
:: ==========================================
:: Edit these values to change tool behavior.
:: ==========================================

:: [KAPE Settings]
:: Targets for Triage Mode (Option 1)
:: Ensure you use ^ before ! if using delayed expansion, but here standard assignment is safer.
set "KAPE_TARGETS=^!SANS_Triage,IISLogFiles,Exchange,ExchangeCve-2021-26855,MemoryFiles,MOF,BITS"
set "KAPE_MODULES=^!EZParser"

:: [THOR Settings]
:: Arguments for Malware Scan (Option 2)
:: Removed --nocsv to enable CSV output
set "THOR_ARGS=--utc --nothordb"

:: [FTK Settings]
:: Arguments for Disk Image (Modern & Legacy)
:: Format: RAW, 1TB chunks, Compression 9 (max)
set "FTK_ARGS=--compress 9 --frag 1TB"

:: ==========================================
:: END SETTINGS
:: ==========================================

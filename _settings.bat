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
:: Arguments for Disk Image (Legacy Option 2)
:: Format: E01, 2GB chunks, Compression 6
set "FTK_ARGS=--e01 --frag 2048M --compress 6 --verify"

:: ==========================================
:: END SETTINGS
:: ==========================================

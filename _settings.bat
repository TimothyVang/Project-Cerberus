@echo off
:: ==========================================
:: PROJECT CERBERUS - LOCAL SETTINGS
:: ==========================================
:: Edit these values to change tool behavior.
:: ==========================================

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

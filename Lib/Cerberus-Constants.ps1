# =============================================================================
# CERBERUS-CONSTANTS.PS1 - All settings and magic numbers in ONE place
# =============================================================================
# 
# WHAT IS THIS FILE?
# This file contains all the "magic numbers" used by Cerberus scripts.
# Instead of having "172800000" scattered throughout the code, we put all
# these values here with explanations.
#
# HOW TO USE:
# 1. Dot-source this file: . "$PSScriptRoot\Lib\Cerberus-Constants.ps1"
# 2. Access values like: $TIMEOUTS.Thor or $THRESHOLDS.MinSpaceGB
#
# WHY THIS MATTERS:
# - Easy to find and change settings
# - One place to update, changes apply everywhere
# - Clear documentation of what each value means
#
# =============================================================================

# -----------------------------------------------------------------------------
# TIMEOUTS - How long to wait before killing a "stuck" tool
# -----------------------------------------------------------------------------
# These are in MILLISECONDS because PowerShell's WaitForExit() uses ms.
#
# To convert hours to milliseconds:
#   hours x 60 x 60 x 1000 = milliseconds
#   Example: 48 hours = 48 x 60 x 60 x 1000 = 172,800,000
#
# WHY SO LONG?
# - THOR scans every file on disk looking for malware - takes hours
# - FTK copies every byte of the hard drive - takes many hours
# - KAPE is faster but still needs time for large systems
# -----------------------------------------------------------------------------

$TIMEOUTS = @{
    Thor    = 172800000    # 48 hours - THOR can take very long on large disks
    Kape    = 86400000     # 24 hours - KAPE artifact collection
    KapeRam = 7200000      # 2 hours  - RAM capture (depends on RAM size)
    Ftk     = 259200000    # 72 hours - Full disk imaging is slow!
}

# -----------------------------------------------------------------------------
# HEARTBEAT - How often to print "still running" messages
# -----------------------------------------------------------------------------
# When running via Elastic Defend, if a script produces no output for too
# long, Elastic thinks it's frozen and kills it. We print status messages
# every 60 seconds to prevent this.
# -----------------------------------------------------------------------------

$HEARTBEAT_MS = 60000    # 60 seconds = 1 minute between status updates

# -----------------------------------------------------------------------------
# THRESHOLDS - Size limits and disk space requirements
# -----------------------------------------------------------------------------

$THRESHOLDS = @{
    LargeFileBytes = 104857600    # 100 MB - Files bigger than this get zipped
    MinSpaceGB     = 10           # 10 GB  - Minimum free space for FTK/KAPE
    WarnSpaceGB    = 1            # 1 GB   - Warn if less than this free
}

# -----------------------------------------------------------------------------
# SPACE REQUIREMENTS - Per-tool disk space needs
# -----------------------------------------------------------------------------
# Each tool generates different amounts of data. These values are used in
# pre-flight checks to warn operators BEFORE a scan fills the disk.
# -----------------------------------------------------------------------------

$SPACE_REQUIREMENTS = @{
    ThorGB           = 1      # THOR logs are small (~500 MB), 1 GB with buffer
    KapeDiskGB       = 25     # KAPE disk collection can reach 20 GB on busy systems
    RamOverhead      = 1.1    # RAM capture needs RAM size + 10% overhead (1.1x multiplier)
    RamCompressRatio = 0.4    # RAM compresses to ~40% of original (50-70% compression)
}

# -----------------------------------------------------------------------------
# VERSION - Displayed in banners and logs
# -----------------------------------------------------------------------------

$CERBERUS_VERSION = "v2.4"

# -----------------------------------------------------------------------------
# CONFIG PLACEHOLDERS - Default template values that mean "not configured"
# -----------------------------------------------------------------------------
# When users copy Cerberus_Config.json.template, these are the placeholder
# values. We check for them during validation to catch unconfigured fields.
# -----------------------------------------------------------------------------

$CONFIG_PLACEHOLDERS = @{
    Server    = "YOUR_MINIO_SERVER:PORT"
    AccessKey = "YOUR_ACCESS_KEY"
    SecretKey = "YOUR_SECRET_KEY"
}

# -----------------------------------------------------------------------------
# PATHS - Common path patterns (relative to script root)
# -----------------------------------------------------------------------------

$PATHS = @{
    Bin      = "Bin"
    Evidence = "Evidence"
    Logs     = "Logs"
    Thor     = "Bin\THOR\thor64-lite.exe"
    Kape     = "Bin\KAPE\kape.exe"
    FtkX64   = "Bin\FTK\x64\ftkimager.exe"
    FtkX86   = "Bin\FTK\x86\ftkimager.exe"
    MinIO    = "Bin\MinIO\mc.exe"
}

# -----------------------------------------------------------------------------
# UPLOAD - Settings for MinIO uploads with resume and progress
# -----------------------------------------------------------------------------
# These control how large file uploads behave.
#
# RESUME LOGIC:
# - Before upload, check if file already exists on server
# - If sizes match, skip (already uploaded)
# - If sizes differ or not found, upload fresh
# - On failure, retry with exponential backoff
#
# PROGRESS DISPLAY:
# - Show progress bar every ProgressPercent (e.g., every 5%)
# - Display: percentage, bytes transferred, speed, ETA
# -----------------------------------------------------------------------------

$UPLOAD = @{
    MaxRetries       = 5           # Number of retry attempts before giving up
    RetryDelayMs     = 5000        # Initial retry delay (5 seconds)
    RetryBackoff     = 2           # Multiply delay by this on each retry (exponential)
    PartSize         = "64MiB"     # Part size for multipart upload
    ParallelParts    = 4           # Number of parallel part uploads
    ProgressPercent  = 5           # Update progress every N percent
    StateFileRetain  = $true       # Keep .upload-state file after successful upload
}

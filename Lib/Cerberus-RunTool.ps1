# =============================================================================
# CERBERUS-RUNTOOL.PS1 - Run a tool with heartbeat monitoring
# =============================================================================
#
# WHAT IS THIS FILE?
# This file contains ONE main function: Start-ToolWithMonitoring
# It runs a forensic tool (like THOR or FTK) and prints "still running"
# messages every 60 seconds.
#
# WHY DO WE NEED THIS?
# When running via Elastic Defend, if a script produces no output for too
# long, Elastic thinks it's frozen and kills it. By printing status messages
# every minute, we keep Elastic happy while long scans run.
#
# =============================================================================

function Start-ToolWithMonitoring {
    <#
    .SYNOPSIS
        Runs a tool with heartbeat monitoring to prevent Elastic timeouts
    
    .DESCRIPTION
        This function:
        1. Starts the tool as a background process
        2. Every 60 seconds, prints a status message
        3. Optionally monitors a log file for progress
        4. Kills the process if it exceeds the timeout
        5. Returns the exit code when done
    
    .PARAMETER ExePath
        Full path to the executable (e.g., "C:\Tools\thor64-lite.exe")
    
    .PARAMETER Arguments
        Command line arguments to pass to the tool
    
    .PARAMETER ToolName
        Name to show in log messages (e.g., "THOR")
    
    .PARAMETER TimeoutMs
        Maximum time to wait before killing the process (in milliseconds)
    
    .PARAMETER ProgressFile
        Optional file to monitor for progress (shows size changes)
    
    .EXAMPLE
        $exitCode = Start-ToolWithMonitoring `
            -ExePath "C:\THOR\thor64-lite.exe" `
            -Arguments "--logfile log.txt" `
            -ToolName "THOR" `
            -TimeoutMs 172800000
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Arguments,
        
        [Parameter(Mandatory = $true)]
        [string]$ToolName,
        
        [Parameter(Mandatory = $true)]
        [int]$TimeoutMs,
        
        [string]$ProgressFile = $null
    )
    
    # -------------------------------------------------------------------------
    # STEP 1: Start the process
    # -------------------------------------------------------------------------
    Write-Host "[$ToolName] Starting process..."
    Write-Host "[$ToolName] Command: $ExePath $Arguments"
    
    $process = Start-Process -FilePath $ExePath `
        -ArgumentList $Arguments `
        -PassThru `
        -NoNewWindow
    
    Write-Host "[$ToolName] Started with PID: $($process.Id)"
    
    # -------------------------------------------------------------------------
    # STEP 2: Monitor the process with heartbeat
    # -------------------------------------------------------------------------
    $startTime = Get-Date
    $lastProgressSize = 0
    $heartbeatMs = 60000  # 60 seconds
    
    while (-not $process.HasExited) {
        
        # Calculate elapsed time
        $elapsed = (Get-Date) - $startTime
        $elapsedMin = [math]::Round($elapsed.TotalMinutes, 1)
        $elapsedHours = [math]::Round($elapsed.TotalHours, 2)
        
        # ---------------------------------------------------------------------
        # CHECK: Has it been running too long?
        # ---------------------------------------------------------------------
        if ($elapsed.TotalMilliseconds -gt $TimeoutMs) {
            Write-Host ""
            Write-Host "[$ToolName] TIMEOUT after $elapsedHours hours!" -ForegroundColor Red
            Write-Host "[$ToolName] Killing process..."
            
            $process.Kill()
            
            return @{
                Success   = $false
                ExitCode  = -1
                Error     = "Timeout after $elapsedHours hours"
                ElapsedMs = $elapsed.TotalMilliseconds
            }
        }
        
        # ---------------------------------------------------------------------
        # WAIT: 60 seconds (or until process exits)
        # ---------------------------------------------------------------------
        $exited = $process.WaitForExit($heartbeatMs)
        
        # If process exited during wait, break out of loop
        if ($exited) { break }
        
        # ---------------------------------------------------------------------
        # HEARTBEAT: Print status message
        # ---------------------------------------------------------------------
        if ($ProgressFile -and (Test-Path $ProgressFile)) {
            # Show progress based on file size
            $currentSize = (Get-Item $ProgressFile).Length
            $sizeMB = [math]::Round($currentSize / 1MB, 2)
            
            if ($currentSize -gt $lastProgressSize) {
                Write-Host "[$ToolName] Progress: $sizeMB MB (elapsed: $elapsedMin min)"
                $lastProgressSize = $currentSize
            } else {
                Write-Host "[$ToolName] Still running... (elapsed: $elapsedMin min)"
            }
        } else {
            Write-Host "[$ToolName] Still running... (elapsed: $elapsedMin min)"
        }
    }
    
    # -------------------------------------------------------------------------
    # STEP 3: Process finished - check result
    # -------------------------------------------------------------------------
    $exitCode = $process.ExitCode
    $elapsed = (Get-Date) - $startTime
    $elapsedMin = [math]::Round($elapsed.TotalMinutes, 1)
    
    Write-Host ""
    Write-Host "[$ToolName] Finished in $elapsedMin minutes (exit code: $exitCode)"
    
    return @{
        Success   = ($exitCode -eq 0)
        ExitCode  = $exitCode
        Error     = if ($exitCode -ne 0) { "Exit code: $exitCode" } else { $null }
        ElapsedMs = $elapsed.TotalMilliseconds
    }
}


function Test-DiskSpace {
    <#
    .SYNOPSIS
        Checks if there's enough free disk space
    
    .DESCRIPTION
        Returns $true if enough space, $false if not.
        Prints a warning if low on space.
    
    .PARAMETER Path
        A path on the drive to check (e.g., "C:\Evidence")
    
    .PARAMETER RequiredGB
        Minimum required space in gigabytes
    
    .EXAMPLE
        if (-not (Test-DiskSpace -Path "C:\Evidence" -RequiredGB 10)) {
            exit 1
        }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [int]$RequiredGB
    )
    
    # Get drive letter from path
    $drive = (Get-Item $Path -ErrorAction SilentlyContinue)
    if (-not $drive) {
        # Path doesn't exist yet, use parent
        $drive = Split-Path $Path -Qualifier
    } else {
        $drive = $drive.PSDrive.Name + ":"
    }
    
    # Get free space
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$drive'"
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    
    Write-Host "[DISK] Free space on ${drive}: $freeGB GB"
    
    if ($freeGB -lt $RequiredGB) {
        Write-Host "[DISK] ERROR: Need at least $RequiredGB GB free!" -ForegroundColor Red
        return $false
    }
    
    return $true
}

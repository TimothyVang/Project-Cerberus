@ECHO OFF
SETLOCAL EnableDelayedExpansion

:: THOR Batch Execution
:: 
:: Florian Roth, August 2016
:: v0.2
:: This is the working template for the THOR execution via Windows batch script 

:: Some help
:: - You can select between an automatic and an interactive mode
:: - Adjust the configuration section to your needs and environment
:: - %~dp0 is an expression that expands the drive letter and path 

:: Configuration ---------------------------------------------------------------
:: LOG_PATH may be a UNC-Path (f.e. \\server\writeable-share) [optional]
SET LOG_PATH=\\server\share
:: Syslog server that receives the log messages on port 514/udp [optional]
SET SYSLOG_SERVER=127.0.0.1
:: General scan options
SET OPTS=--nocsv --nofirewall
:: Presets - not used by can be used in output names
:: THOR's default output format is %COMPUTERNAME%_thor_YYYY-MM-DD.ext
SET CUR_DATE=%date:~6,4%%date:~3,2%%date:~0,2%
SET LOGNAME=%COMPUTERNAME%-%CUR_DATE%.txt

:: Set a scan mode 
SET SMODE=Interactive

:: Program Run -----------------------------------------------------------------

:: Automatic Mode
IF "%SMODE%" == "Automatic" (
    :: Select a scan type for automatic scan mode
    :: LOGLOCAL - only writes .txt log and .htm report to the current working dir 
    :: SYSLOGONLY - only log to a syslog server and write no local log files
    :: LOGSHARE - write log files and 
    :: SYSLOGANDSHARE - send to syslog server and write log file to a network share
    ::
    :: Info: An error in one of the outputs doesn't disable the other output methods
    ::
    :: Uncomment the preferred method
    GOTO LOGLOCAL
    REM GOTO SYSLOGONLY
    REM GOTO LOGSHARE
    REM GOTO SYSLOGANDSHARE
    GOTO END
)

:: Interactive Mode 
IF "%SMODE%" == "Interactive" (
    COLOR 0B
    ECHO.
    ECHO =======================================================================
    ECHO  THOR SCAN 
    ECHO  Windows Batch Launcher
    ECHO =======================================================================
    :SELECTION
    ECHO Interactive scan mode selection
    ECHO.
    ECHO    1. Log to local working directory only
    ECHO        %~dp0
    ECHO. 
    ECHO    2. Log to syslog server only
    ECHO        %SYSLOG_SERVER%
    ECHO.    
    ECHO    3. Log to a network share only 
    ECHO        %LOG_PATH%
    ECHO.
    ECHO    4. Log to syslog server and network share
    ECHO        %SYSLOG_SERVER%
    ECHO        %LOG_PATH%
    ECHO.
    SET /P selection=Select your preferred scan method: 
    ECHO Selection: !selection!

    IF "!selection!"=="1" (
        ECHO Selected local log file only
        GOTO LOGLOCAL
    )
    IF "!selection!"=="2" (
        ECHO Selected syslog output only
        GOTO SYSLOGONLY
    )
    IF "!selection!"=="3" (
        ECHO Selected network share output only
        GOTO LOGSHARE
    )
    IF "!selection!"=="4" (
        ECHO Selected syslog and network share output
        GOTO SYSLOGANDSHARE
    )
    ECHO This is not a valid answer! Quit with CTRL+C
    ECHO.
    GOTO SELECTION
)

:: Scan Types ------------------------------------------------------------------

:: LOCAL LOG IN WORKING DIRECTORY
:LOGLOCAL
%~dp0\thor.exe %OPTS%
GOTO END

:: SYSLOG ONLY
:: Requirement: Network connectivity to target system
:SYSLOGONLY
%~dp0\thor.exe %OPTS% --nolog --nohtml --nocsv -s %SYSLOG_SERVER%
GOTO END

:: LOG TO NETWORK SHARE
:LOGSHARE
%~dp0\thor.exe %OPTS% -e %LOG_PATH%
GOTO END

:: SYSLOG AND NETWORK SHARE
:SYSLOGANDSHARE
%~dp0\thor.exe %OPTS% -s %SYSLOG_SERVER% -e %LOG_PATH%
GOTO END

:: END OF SCAN -----------------------------------------------------------------
:END
ECHO THOR Scan finished - you can close the window now
:: Wait 60 seconds
PING 127.0.0.1 -n 3600 >NUL 2>&1

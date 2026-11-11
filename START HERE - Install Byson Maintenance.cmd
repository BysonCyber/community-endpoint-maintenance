@echo off
setlocal

set "SCRIPT_DIR=%~dp0"

rem Recommended launch:
rem Right-click this file -> Run as administrator
rem
rem Some Smart App Control / App Control configurations may block a normal
rem Explorer -> cmd.exe launch chain before Byson starts.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%START HERE - Install Byson Maintenance.ps1"
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
    echo.
    echo Byson Maintenance launcher exited with code %EXITCODE%.
    echo.
    echo Recommended launch:
    echo   Right-click this file and choose "Run as administrator".
    echo.
    echo If Windows application control still blocks execution,
    echo use the PowerShell fallback documented in INSTALL.md.
    pause
)

exit /b %EXITCODE%

@echo off
rem ===========================================================================
rem  Install ParsVT.cmd - one-click launcher for parsvt.ps1 -Quick  (v2.5)
rem  Put this file in the same folder as parsvt.ps1 and preflight.ps1, then
rem  double-click it. parsvt.ps1 -Quick runs preflight.ps1 itself.
rem  Keep this file pure ASCII with Windows (CRLF) line endings.
rem ===========================================================================
setlocal
set "PARSVT_DIR=%~dp0"
title ParsVT CRM Installer

echo ######   #####  ######  ####### ##    ## #######
echo ##   ## ##   ## ##   ## ##      ##    ##    ##
echo ######  ####### ######  ####### ##    ##    ##
echo ##      ##   ## ##   ##      ##  ##  ##     ##
echo ##      ##   ## ##   ## #######   ####      ##
echo.
echo One-click installer for ParsVT CRM on Windows Server.
echo.

if not exist "%PARSVT_DIR%parsvt.ps1" (
    echo.
    echo  parsvt.ps1 was not found next to this file:
    echo    %PARSVT_DIR%
    echo.
    echo  If you opened this file from inside a ZIP, first extract the whole ZIP
    echo  to a local folder, for example C:\ParsVT-Setup, then run it from there.
    echo.
    pause
    exit /b 2
)

rem ---- Administrator rights ------------------------------------------------
rem "fltmc" works only for an elevated administrator (and, unlike "net session",
rem does not depend on the Server service). The --elevated marker stops a loop
rem if the elevated copy still cannot pass the check.
fltmc >nul 2>&1
if not errorlevel 1 goto :run
if /i "%~1"=="--elevated" (
    echo.
    echo  Administrator rights are still missing. Right-click this file and
    echo  choose "Run as administrator".
    echo.
    pause
    exit /b 2
)
echo  Requesting administrator rights...
set "PARSVT_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath $env:PARSVT_SELF -ArgumentList '--elevated' -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }"
if errorlevel 1 (
    echo.
    echo  Administrator rights were not granted, so ParsVT cannot be installed.
    echo  Run this file again and choose "Yes" in the Windows prompt.
    echo.
    pause
    exit /b 1
)
rem The elevated copy continues in a new window.
exit /b 0

:run
cd /d "%PARSVT_DIR%"
echo.
echo  Starting the ParsVT installer (quick mode)...
echo  First this server is checked (1-3 minutes), then only the license key
echo  is asked. Do not close this window.
echo.
rem -ExecutionPolicy Bypass applies to this PowerShell process only.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PARSVT_DIR%parsvt.ps1" -Quick
set "PARSVT_RC=%ERRORLEVEL%"
echo.
echo  ===========================================================================
if "%PARSVT_RC%"=="0" (
    echo  The installer finished. The CRM address and password are shown above
    echo  and saved in C:\parsvt-credentials.txt
) else (
    echo  The installer stopped with exit code %PARSVT_RC%.
    echo  A report file named ParsVT-Report-....zip was saved on your Desktop.
    echo  Please send that file to ParsVT support.
)
echo  ===========================================================================
echo.
pause
exit /b %PARSVT_RC%

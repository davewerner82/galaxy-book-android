@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tablet.ps1" -Action Arm
if errorlevel 1 echo Arm did not complete. Keep the message above.
pause

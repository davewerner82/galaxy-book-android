@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tablet.ps1" -Action Restore
if errorlevel 1 echo Restore did not complete. Keep the message above.
pause

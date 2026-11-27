@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tablet.ps1" -Action Check
if errorlevel 1 echo Check did not complete. Keep the message above.
pause

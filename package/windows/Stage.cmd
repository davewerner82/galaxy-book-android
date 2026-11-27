@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tablet.ps1" -Action Stage
if errorlevel 1 echo Stage did not complete. Keep the message above.
pause

@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BootAction.ps1" -Action Arm
if exist "%~dp0last-arm.txt" type "%~dp0last-arm.txt"
if errorlevel 1 echo Arm did not complete. Keep the message above.
pause

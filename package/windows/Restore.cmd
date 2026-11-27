@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BootAction.ps1" -Action Restore
if exist "%~dp0last-restore.txt" type "%~dp0last-restore.txt"
if errorlevel 1 echo Restore did not complete. Keep the message above.
pause

@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Sta -File "%~dp0helper\settings.ps1"
exit /b %errorlevel%

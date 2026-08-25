@echo off
chcp 65001 >nul
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "exit_code=%errorlevel%"
echo.
if not "%exit_code%"=="0" echo 安装没有完成，请查看上方错误信息。
pause
exit /b %exit_code%

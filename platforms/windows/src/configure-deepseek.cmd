@echo off
chcp 65001 >nul
setlocal
set "script=%LOCALAPPDATA%\InputTranslate\windows-rime\helper\configure-deepseek.ps1"
if not exist "%script%" (
  echo 尚未安装 inputeng，或后台助手文件缺失。
  echo 请先双击 install.cmd。
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%script%"
set "exit_code=%errorlevel%"
echo.
if not "%exit_code%"=="0" echo 配置没有完成，请查看上方错误信息。
pause
exit /b %exit_code%

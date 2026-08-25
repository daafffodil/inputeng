[CmdletBinding()]
param(
    [string]$StateRoot,
    [string]$RimeUserDir
)

$ErrorActionPreference = 'Stop'
if (-not $StateRoot) {
    if (-not $env:LOCALAPPDATA) { exit 0 }
    $StateRoot = Join-Path $env:LOCALAPPDATA 'InputTranslate\windows-rime'
}
if (-not $RimeUserDir) {
    $RimeUserDir = ''
    try {
        $RimeUserDir = [string](Get-ItemPropertyValue -Path 'HKCU:\Software\Rime\Weasel' -Name 'RimeUserDir' -ErrorAction SilentlyContinue)
    } catch { $RimeUserDir = '' }
    if (-not $RimeUserDir) {
        if (-not $env:APPDATA) { exit 0 }
        $RimeUserDir = Join-Path $env:APPDATA 'Rime'
    }
}

$worker = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'worker.ps1'
$configPath = Join-Path $StateRoot 'deepseek-config.json'
$keyPath = Join-Path $StateRoot 'deepseek.key.dpapi'
$enabledPath = Join-Path $RimeUserDir 'input_translate_ai_enabled'
if (-not (Test-Path -LiteralPath $worker) -or -not (Test-Path -LiteralPath $configPath) -or
    -not (Test-Path -LiteralPath $keyPath) -or -not (Test-Path -LiteralPath $enabledPath)) {
    exit 0
}

try {
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$config.enabled) { exit 0 }
} catch { exit 0 }

$stopPath = Join-Path $StateRoot 'worker.stop'
Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
$powershell = Join-Path $PSHOME 'powershell.exe'
$arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -StateRoot "{1}" -RimeUserDir "{2}"' -f $worker, $StateRoot, $RimeUserDir
Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden | Out-Null

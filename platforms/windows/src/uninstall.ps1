[CmdletBinding()]
param(
    [string]$RimeUserDir,
    [string]$StateRoot,
    [switch]$SkipDeploy,
    [switch]$PurgeData
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Get-Sha256 {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha256.ComputeHash($stream)
        return ([System.BitConverter]::ToString($bytes)).Replace('-', '')
    } finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

function Get-WeaselRoot {
    $views = @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)
    foreach ($view in $views) {
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $key = $base.OpenSubKey('Software\Rime\Weasel')
            if ($null -ne $key) {
                $root = [string]$key.GetValue('WeaselRoot', '')
                if (-not $root) { $root = [string]$key.GetValue('InstallDir', '') }
                $key.Dispose(); $base.Dispose()
                if ($root -and (Test-Path -LiteralPath (Join-Path $root 'WeaselDeployer.exe'))) { return $root }
                if ($root -and (Test-Path -LiteralPath $root)) {
                    $versioned = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'WeaselDeployer.exe') } |
                        Sort-Object Name -Descending | Select-Object -First 1
                    if ($null -ne $versioned) { return $versioned.FullName }
                }
            } else { $base.Dispose() }
        } catch { }
    }
    return $null
}

function Remove-MarkerBlock {
    param([string]$Content, [string]$Name)
    $escaped = [regex]::Escape($Name)
    $pattern = "(?ms)^[ \t]*# >>> input-translate:$escaped\r?\n.*?^[ \t]*# <<< input-translate:$escaped(?:\r?\n)?"
    return [regex]::Replace($Content, $pattern, '')
}

function Remove-InputTranslateConfigEntries {
    param([string]$Content, [string]$Name)
    $Content = Remove-MarkerBlock -Content $Content -Name $Name
    if ($Name -eq 'schema') {
        $Content = [regex]::Replace(
            $Content,
            '(?m)^[ \t]*["'']?schema_list/@next/schema["'']?[ \t]*:[ \t]*["'']?bilingual_(?:pinyin|sogou)["'']?[ \t]*(?:#.*)?\r?\n?',
            ''
        )
        $Content = [regex]::Replace(
            $Content,
            '(?m)^[ \t]*-[ \t]*(?:\{[ \t]*)?schema[ \t]*:[ \t]*["'']?bilingual_(?:pinyin|sogou)["'']?(?:[ \t]*\})?[ \t]*(?:#.*)?\r?\n?',
            ''
        )
    } elseif ($Name -eq 'theme') {
        foreach ($theme in @('input_translate_light', 'input_translate_dark')) {
            $escaped = [regex]::Escape($theme)
            $pattern = "(?m)^[ ]{2}[`"']?preset_color_schemes/$escaped[`"']?\s*:\s*\r?\n(?:^[ ]{4,}.*(?:\r?\n|$))*"
            $Content = [regex]::Replace($Content, $pattern, '')
        }
    }
    return $Content
}

if (-not $StateRoot) {
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is unavailable.' }
    $StateRoot = Join-Path $env:LOCALAPPDATA 'InputTranslate\windows-rime'
}
$StateRoot = [System.IO.Path]::GetFullPath($StateRoot)
$ManifestPath = Join-Path $StateRoot 'install-manifest.json'
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "inputeng installation manifest not found: $ManifestPath"
}
$manifest = Get-Content -Raw -LiteralPath $ManifestPath -Encoding UTF8 | ConvertFrom-Json
if (-not $RimeUserDir) { $RimeUserDir = [string]$manifest.rimeUserDir }
$RimeUserDir = [System.IO.Path]::GetFullPath($RimeUserDir)
$warnings = @()

$brandingProperty = $manifest.PSObject.Properties['branding']
if ($null -ne $brandingProperty -and $null -ne $brandingProperty.Value) {
    $branding = $brandingProperty.Value
    if ([bool]$branding.applied) {
        $brandScript = [string]$branding.helperPath
        if (-not $brandScript -or -not (Test-Path -LiteralPath $brandScript)) {
            $brandScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'helper\brand-weasel.ps1'
        }
        if (Test-Path -LiteralPath $brandScript) {
            try {
                $powershell = Join-Path $PSHOME 'powershell.exe'
                $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Restore' -f $brandScript
                $process = Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -Wait -PassThru -WindowStyle Hidden
                if ($process.ExitCode -ne 0) {
                    $warnings += "恢复小狼毫原始名称和图标返回代码 $($process.ExitCode)。"
                }
            } catch {
                $warnings += "未能恢复小狼毫原始名称和图标：$($_.Exception.Message)"
            }
        } else {
            $warnings += '未找到品牌恢复组件；Windows 输入法名称和图标保持不变。'
        }
    }
}

if ($null -ne $manifest.backgroundWorker) {
    [System.IO.File]::WriteAllText((Join-Path $StateRoot 'worker.stop'), 'stop', $Utf8NoBom)
    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $runName = [string]$manifest.backgroundWorker.runValueName
    if ($runName) {
        Remove-ItemProperty -Path $runPath -Name $runName -Force -ErrorAction SilentlyContinue
    }
    $shortcutPath = [string]$manifest.backgroundWorker.shortcutPath
    if ($shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue }
    $settingsShortcutPath = ''
    $settingsShortcutProperty = $manifest.backgroundWorker.PSObject.Properties['settingsShortcutPath']
    if ($null -ne $settingsShortcutProperty) {
        $settingsShortcutPath = [string]$settingsShortcutProperty.Value
    }
    if ($settingsShortcutPath) { Remove-Item -LiteralPath $settingsShortcutPath -Force -ErrorAction SilentlyContinue }
    $startMenuDir = [string]$manifest.backgroundWorker.startMenuDir
    if ($startMenuDir -and (Test-Path -LiteralPath $startMenuDir)) {
        if (-not (Get-ChildItem -LiteralPath $startMenuDir -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $startMenuDir -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Milliseconds 900
    $helperDir = [string]$manifest.backgroundWorker.helperDir
    $expectedHelperDir = [System.IO.Path]::GetFullPath((Join-Path $StateRoot 'helper'))
    if ($helperDir -and [System.IO.Path]::GetFullPath($helperDir) -eq $expectedHelperDir) {
        Remove-Item -LiteralPath $expectedHelperDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Remove-Item -LiteralPath (Join-Path $RimeUserDir 'input_translate_ai_enabled') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $RimeUserDir 'input_translate_missing.txt') -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $RimeUserDir -Filter 'input_translate_missing.work.*' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

foreach ($entry in $manifest.managedFiles) {
    $target = Join-Path $RimeUserDir ([string]$entry.relativePath)
    if (-not (Test-Path -LiteralPath $target)) { continue }
    $currentHash = Get-Sha256 $target
    if ($currentHash -ne ([string]$entry.installedSha256)) {
        $warnings += "保留已修改文件：$target"
        continue
    }
    if ($entry.backupPath -and (Test-Path -LiteralPath ([string]$entry.backupPath))) {
        Copy-Item -LiteralPath ([string]$entry.backupPath) -Destination $target -Force
    } else {
        Remove-Item -LiteralPath $target -Force
    }
}

foreach ($custom in $manifest.customFiles) {
    $path = Join-Path $RimeUserDir ([string]$custom.name)
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $content = [System.IO.File]::ReadAllText($path)
    $content = Remove-InputTranslateConfigEntries -Content $content -Name ([string]$custom.marker)
    $onlyEmptyPatchRemains = [regex]::IsMatch($content, '^\s*patch:\s*$')
    if ([bool]$custom.createdByInstaller -and $onlyEmptyPatchRemains) {
        Remove-Item -LiteralPath $path -Force
    } else {
        Write-Utf8File -Path $path -Content $content
    }
}

if (-not $SkipDeploy) {
    $weaselRoot = Get-WeaselRoot
    if ($weaselRoot) {
        $process = Start-Process -FilePath (Join-Path $weaselRoot 'WeaselDeployer.exe') -ArgumentList '/deploy' -Wait -PassThru
        if ($process.ExitCode -ne 0) { $warnings += "小狼毫重新部署返回代码 $($process.ExitCode)。" }
    } else {
        $warnings += '未找到小狼毫，已移除文件但未运行重新部署。'
    }
}

Remove-Item -LiteralPath $ManifestPath -Force
if ($PurgeData) {
    foreach ($path in @(
        (Join-Path $StateRoot 'deepseek.key.dpapi'),
        (Join-Path $StateRoot 'deepseek-config.json'),
        (Join-Path $StateRoot 'worker.log'),
        (Join-Path $StateRoot 'worker.log.old'),
        (Join-Path $StateRoot 'worker.stop'),
        (Join-Path $StateRoot 'settings.json'),
        (Join-Path $RimeUserDir 'input_translate_ai_cache.tsv'),
        (Join-Path $RimeUserDir 'input_translate_ai_cache.version'),
        (Join-Path $RimeUserDir 'input_translate_ai_chinese_cache.tsv'),
        (Join-Path $RimeUserDir 'input_translate_ai_chinese_cache.version'),
        (Join-Path $RimeUserDir 'input_translate_personal_phrases.tsv'),
        (Join-Path $RimeUserDir 'input_translate_personal_phrases.version'),
        (Join-Path $RimeUserDir 'input_translate_phrase_pending.tsv'),
        (Join-Path $RimeUserDir 'input_translate_frequency.tsv'),
        (Join-Path $RimeUserDir 'input_translate_frequency_events.tsv')
    )) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}
Write-Host 'inputeng Windows 配置已卸载。' -ForegroundColor Green
foreach ($warning in $warnings) { Write-Warning $warning }

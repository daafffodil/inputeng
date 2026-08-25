[CmdletBinding()]
param(
    [string]$StateRoot,
    [string]$RimeUserDir,
    [string]$ApplyAccent,
    [int]$ApplyCandidateFontPoint,
    [int]$ApplyCommentFontPoint,
    [ValidateSet('', 'inline', 'candidate')]
    [string]$ApplyPreeditPlacement,
    [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not $StateRoot) {
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is unavailable.' }
    $StateRoot = Join-Path $env:LOCALAPPDATA 'InputTranslate\windows-rime'
}
if (-not $RimeUserDir) {
    $RimeUserDir = ''
    try {
        $RimeUserDir = [string](Get-ItemPropertyValue -Path 'HKCU:\Software\Rime\Weasel' -Name 'RimeUserDir' -ErrorAction SilentlyContinue)
    } catch { $RimeUserDir = '' }
    if (-not $RimeUserDir) {
        if (-not $env:APPDATA) { throw 'APPDATA is unavailable.' }
        $RimeUserDir = Join-Path $env:APPDATA 'Rime'
    }
}

$StateRoot = [System.IO.Path]::GetFullPath($StateRoot)
$RimeUserDir = [System.IO.Path]::GetFullPath($RimeUserDir)
New-Item -ItemType Directory -Force -Path $StateRoot, $RimeUserDir | Out-Null

$SettingsPath = Join-Path $StateRoot 'settings.json'
$WeaselCustomPath = Join-Path $RimeUserDir 'weasel.custom.yaml'
$SchemaStyleCustomPath = Join-Path $RimeUserDir 'bilingual_pinyin.custom.yaml'
$DoubleSchemaStyleCustomPath = Join-Path $RimeUserDir 'bilingual_sogou.custom.yaml'
$OfflineDictionaryPath = Join-Path $RimeUserDir 'bilingual_english.tsv'
$OverrideDictionaryPath = Join-Path $RimeUserDir 'common_gloss_overrides.tsv'
$AiDictionaryPath = Join-Path $RimeUserDir 'input_translate_ai_cache.tsv'
$AiEnabledPath = Join-Path $RimeUserDir 'input_translate_ai_enabled'
$ConfigureDeepSeekPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'configure-deepseek.ps1'
$DeployRimePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'deploy-rime.ps1'

function Get-Accent {
    $accent = '#EC4899'
    if (Test-Path -LiteralPath $SettingsPath) {
        try {
            $settings = Get-Content -Raw -LiteralPath $SettingsPath -Encoding UTF8 | ConvertFrom-Json
            if ([string]$settings.accentColor -match '^#[0-9A-Fa-f]{6}$') {
                $accent = ([string]$settings.accentColor).ToUpperInvariant()
            }
        } catch { }
    }
    return $accent
}

function Save-Accent {
    param([string]$Accent)
    $fontPoints = Get-FontPoints
    $placement = Get-PreeditPlacement
    $payload = [ordered]@{
        accentColor = $Accent.ToUpperInvariant()
        candidateFontPoint = $fontPoints.Candidate
        commentFontPoint = $fontPoints.Comment
        preeditPlacement = $placement
        updatedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($SettingsPath, $payload, $Utf8NoBom)
}

function Get-FontPoints {
    $candidate = 12
    $comment = 9
    if (Test-Path -LiteralPath $SettingsPath) {
        try {
            $settings = Get-Content -Raw -LiteralPath $SettingsPath -Encoding UTF8 | ConvertFrom-Json
            $savedCandidate = 0
            if ([int]::TryParse([string]$settings.candidateFontPoint, [ref]$savedCandidate) -and
                $savedCandidate -ge 11 -and $savedCandidate -le 22) {
                $candidate = $savedCandidate
            }
            $savedComment = 0
            if ([int]::TryParse([string]$settings.commentFontPoint, [ref]$savedComment) -and
                $savedComment -ge 8 -and $savedComment -le 16) {
                $comment = $savedComment
            }
        } catch { }
    }
    return [pscustomobject]@{ Candidate = $candidate; Comment = $comment }
}

function Save-FontPoints {
    param([int]$Candidate, [int]$Comment)
    $payload = [ordered]@{
        accentColor = (Get-Accent)
        candidateFontPoint = $Candidate
        commentFontPoint = $Comment
        preeditPlacement = (Get-PreeditPlacement)
        updatedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($SettingsPath, $payload, $Utf8NoBom)
}

function Get-PreeditPlacement {
    return 'inline'
}

function Save-AppearanceSettings {
    param([int]$Candidate, [int]$Comment, [string]$Placement)
    $payload = [ordered]@{
        accentColor = (Get-Accent)
        candidateFontPoint = $Candidate
        commentFontPoint = $Comment
        preeditPlacement = 'inline'
        updatedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($SettingsPath, $payload, $Utf8NoBom)
}

function Update-CustomizationTimestamp {
    param([string]$Content)
    $timestamp = (Get-Date).ToString('ddd MMM dd HH:mm:ss yyyy', [Globalization.CultureInfo]::InvariantCulture)
    return [regex]::Replace(
        $Content,
        '(?m)^(?<prefix>[ \t]*modified_time[ \t]*:[ \t]*).*(?:\r)?$',
        { param($match) $match.Groups['prefix'].Value + '"' + $timestamp + '"' }
    )
}

function Update-RimeCustomMarker {
    param(
        [string]$Path,
        [string]$MarkerName,
        [string[]]$PatchLines
    )
    $content = if (Test-Path -LiteralPath $Path) { [System.IO.File]::ReadAllText($Path) } else { '' }
    $escaped = [regex]::Escape($MarkerName)
    $content = [regex]::Replace(
        $content,
        "(?ms)^[ \t]*# >>> input-translate:$escaped\r?\n.*?^[ \t]*# <<< input-translate:$escaped(?:\r?\n)?",
        ''
    )
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $blockLines = @("  # >>> input-translate:$MarkerName")
    foreach ($line in $PatchLines) { $blockLines += "  $line" }
    $blockLines += "  # <<< input-translate:$MarkerName"
    $block = $blockLines -join $newline
    $patch = [regex]::Match($content, '(?m)^patch:\s*(?:#.*)?\r?$')
    if ($patch.Success) {
        $insertAt = $patch.Index + $patch.Length
        $content = $content.Substring(0, $insertAt) + $newline + $block + $content.Substring($insertAt)
    } else {
        if ([regex]::IsMatch($content, '(?m)^patch\s*:')) {
            throw "不支持的 patch 格式：$Path"
        }
        if ($content.Length -gt 0 -and -not $content.EndsWith($newline)) { $content += $newline }
        if ($content.Trim().Length -gt 0) { $content += $newline }
        $content += 'patch:' + $newline + $block + $newline
    }
    $content = Update-CustomizationTimestamp -Content $content
    [System.IO.File]::WriteAllText($Path, $content, $Utf8NoBom)
}

function Get-WeaselRoot {
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $key = $base.OpenSubKey('Software\Rime\Weasel')
            if ($null -ne $key) {
                $root = [string]$key.GetValue('WeaselRoot', '')
                if (-not $root) { $root = [string]$key.GetValue('InstallDir', '') }
                $key.Dispose()
                $base.Dispose()
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
    foreach ($root in @((Join-Path $env:ProgramFiles 'Rime'), (Join-Path ${env:ProgramFiles(x86)} 'Rime'))) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $versioned = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'WeaselDeployer.exe') } |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($null -ne $versioned) { return $versioned.FullName }
    }
    return $null
}

function Invoke-WeaselDeploy {
    if ($SkipDeploy) { return }
    if (-not (Test-Path -LiteralPath $DeployRimePath)) {
        throw '重新部署组件缺失，设置已经保存，请重新安装 inputeng。'
    }
    & $DeployRimePath -StateRoot $StateRoot -RimeUserDir $RimeUserDir
}

function Apply-AccentColor {
    param([string]$Accent)
    if ($Accent -notmatch '^#[0-9A-Fa-f]{6}$') { throw '强调色必须是 #RRGGBB。' }
    if (-not (Test-Path -LiteralPath $WeaselCustomPath)) { throw '没有找到 weasel.custom.yaml。' }
    $content = [System.IO.File]::ReadAllText($WeaselCustomPath)
    $pattern = '(?ms)# >>> input-translate:theme\r?\n.*?# <<< input-translate:theme'
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success) { throw '没有找到 inputeng 主题配置块。' }
    $rgba = '0x' + $Accent.Substring(1).ToLowerInvariant() + 'ff'
    $block = [regex]::Replace(
        $match.Value,
        '(?m)(hilited_candidate_back_color:[ \t]*)0x[0-9A-Fa-f]{8}',
        { param($value) $value.Groups[1].Value + $rgba }
    )
    $updated = $content.Substring(0, $match.Index) + $block + $content.Substring($match.Index + $match.Length)
    $updated = Update-CustomizationTimestamp -Content $updated
    [System.IO.File]::WriteAllText($WeaselCustomPath, $updated, $Utf8NoBom)
    Save-Accent -Accent $Accent
    Invoke-WeaselDeploy
}

function Apply-AppearanceSettings {
    param([int]$Candidate, [int]$Comment, [string]$Placement)
    if ($Candidate -lt 11 -or $Candidate -gt 22) { throw '中文候选字号必须在 11 至 22 之间。' }
    if ($Comment -lt 8 -or $Comment -gt 16) { throw '英文小字字号必须在 8 至 16 之间。' }
    if ($Comment -gt $Candidate) { throw '英文小字不能大于中文候选字号。' }
    $Placement = 'inline'
    $inlinePreedit = 'true'
    foreach ($path in @($SchemaStyleCustomPath, $DoubleSchemaStyleCustomPath)) {
        Update-RimeCustomMarker -Path $path -MarkerName 'style' -PatchLines @(
            ('"style/font_point": ' + $Candidate)
            ('"style/comment_font_point": ' + $Comment)
            ('"style/inline_preedit": ' + $inlinePreedit)
        )
    }
    Save-AppearanceSettings -Candidate $Candidate -Comment $Comment -Placement $Placement
    Invoke-WeaselDeploy
}

function Apply-FontPoints {
    param([int]$Candidate, [int]$Comment)
    Apply-AppearanceSettings -Candidate $Candidate -Comment $Comment -Placement (Get-PreeditPlacement)
}

function Apply-PreeditPlacement {
    param([string]$Placement)
    $fonts = Get-FontPoints
    Apply-AppearanceSettings -Candidate $fonts.Candidate -Comment $fonts.Comment -Placement $Placement
}

if ($ApplyAccent) {
    Apply-AccentColor -Accent $ApplyAccent
    Write-Output $ApplyAccent.ToUpperInvariant()
    exit 0
}

if ($ApplyCandidateFontPoint -gt 0 -or $ApplyCommentFontPoint -gt 0 -or $ApplyPreeditPlacement) {
    $currentFonts = Get-FontPoints
    $candidate = if ($ApplyCandidateFontPoint -gt 0) { $ApplyCandidateFontPoint } else { $currentFonts.Candidate }
    $comment = if ($ApplyCommentFontPoint -gt 0) { $ApplyCommentFontPoint } else { $currentFonts.Comment }
    $placement = if ($ApplyPreeditPlacement) { $ApplyPreeditPlacement } else { Get-PreeditPlacement }
    Apply-AppearanceSettings -Candidate $candidate -Comment $comment -Placement $placement
    Write-Output ("{0}/{1}/{2}" -f $candidate, $comment, $placement)
    exit 0
}

$UiPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'settings-ui.ps1'
if (-not (Test-Path -LiteralPath $UiPath)) { throw '设置界面组件缺失，请重新安装 inputeng。' }
. $UiPath

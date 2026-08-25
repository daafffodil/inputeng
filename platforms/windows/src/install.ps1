[CmdletBinding()]
param(
    [string]$RimeUserDir,
    [string]$StateRoot,
    [switch]$SkipWeaselCheck,
    [switch]$SkipDeploy,
    [switch]$SkipBackgroundWorker,
    [switch]$SkipBranding,
    [switch]$InstallWeasel,
    [switch]$AcceptWeaselDownload,
    [switch]$SilentWeaselInstall,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProductName = 'inputeng'
$ProductVersion = '0.6.0'
$WeaselVersion = '0.17.4'
$WeaselInstallerName = 'weasel-0.17.4.0-installer.exe'
$WeaselInstallerUrl = 'https://github.com/rime/weasel/releases/download/0.17.4/weasel-0.17.4.0-installer.exe'
$WeaselInstallerSha256 = 'CF509534A8F5F8AF9C98ED7CBB8F135439F145A8CBE7E50EDE42BB5B5AB45C29'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

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
    $views = @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )
    foreach ($view in $views) {
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine,
                $view
            )
            $key = $base.OpenSubKey('Software\Rime\Weasel')
            if ($null -ne $key) {
                $root = [string]$key.GetValue('WeaselRoot', '')
                if (-not $root) {
                    $root = [string]$key.GetValue('InstallDir', '')
                }
                $key.Dispose()
                $base.Dispose()
                if ($root -and (Test-Path -LiteralPath (Join-Path $root 'WeaselDeployer.exe'))) {
                    return $root
                }
                if ($root) {
                    $versioned = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'WeaselDeployer.exe') } |
                        Sort-Object Name -Descending |
                        Select-Object -First 1
                    if ($null -ne $versioned) {
                        return $versioned.FullName
                    }
                }
            } else {
                $base.Dispose()
            }
        } catch {
            # Continue with the other registry view and filesystem fallbacks.
        }
    }

    $roots = @()
    if ($env:ProgramFiles) { $roots += (Join-Path $env:ProgramFiles 'Rime') }
    if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} 'Rime') }
    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        if (Test-Path -LiteralPath (Join-Path $root 'WeaselDeployer.exe')) { return $root }
        $versioned = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'WeaselDeployer.exe') } |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($null -ne $versioned) { return $versioned.FullName }
    }
    return $null
}

function Invoke-RimeWorkspaceDeploy {
    param(
        [string]$WeaselRoot,
        [string]$UserDataDir,
        [string]$LogDir
    )

    $rimeDll = Join-Path $WeaselRoot 'rime.dll'
    if (-not (Test-Path -LiteralPath $rimeDll)) {
        throw "rime.dll was not found under $WeaselRoot."
    }

    $server = Join-Path $WeaselRoot 'WeaselServer.exe'
    if (Test-Path -LiteralPath $server) {
        & $server /q
        Start-Sleep -Milliseconds 800
    }

    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $typeName = 'InputTranslateRimeDeploy' + $PID
    $dllLiteral = $rimeDll.Replace('"', '""')
    $source = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class $typeName {
  [StructLayout(LayoutKind.Sequential)]
  public struct RimeTraits {
    public int data_size;
    public IntPtr shared_data_dir;
    public IntPtr user_data_dir;
    public IntPtr distribution_name;
    public IntPtr distribution_code_name;
    public IntPtr distribution_version;
    public IntPtr app_name;
    public IntPtr modules;
    public int min_log_level;
    public IntPtr log_dir;
    public IntPtr prebuilt_data_dir;
    public IntPtr staging_dir;
  }

  [DllImport(@"$dllLiteral", CallingConvention=CallingConvention.Cdecl)]
  static extern void RimeSetup(ref RimeTraits traits);
  [DllImport(@"$dllLiteral", CallingConvention=CallingConvention.Cdecl)]
  static extern void RimeDeployerInitialize(ref RimeTraits traits);
  [DllImport(@"$dllLiteral", CallingConvention=CallingConvention.Cdecl)]
  static extern int RimeDeployWorkspace();
  [DllImport(@"$dllLiteral", CallingConvention=CallingConvention.Cdecl)]
  static extern int RimeDeployConfigFile(
      [MarshalAs(UnmanagedType.LPStr)] string fileName,
      [MarshalAs(UnmanagedType.LPStr)] string versionKey);
  [DllImport(@"$dllLiteral", CallingConvention=CallingConvention.Cdecl)]
  static extern void RimeFinalize();

  static IntPtr Utf8(string value) {
    byte[] bytes = Encoding.UTF8.GetBytes(value + "\0");
    IntPtr pointer = Marshal.AllocHGlobal(bytes.Length);
    Marshal.Copy(bytes, 0, pointer, bytes.Length);
    return pointer;
  }

  public static int Run(string shared, string user, string version, string logs) {
    var pointers = new List<IntPtr>();
    Func<string,IntPtr> p = value => {
      IntPtr pointer = Utf8(value);
      pointers.Add(pointer);
      return pointer;
    };
    var traits = new RimeTraits();
    traits.data_size = Marshal.SizeOf(typeof(RimeTraits)) - sizeof(int);
    traits.shared_data_dir = p(shared);
    traits.user_data_dir = p(user);
    traits.distribution_name = p("Weasel");
    traits.distribution_code_name = p("Weasel");
    traits.distribution_version = p(version);
    traits.app_name = p("rime.weasel");
    traits.min_log_level = 1;
    traits.log_dir = p(logs);
    try {
      RimeSetup(ref traits);
      RimeDeployerInitialize(ref traits);
      int workspace = RimeDeployWorkspace();
      int weasel = RimeDeployConfigFile("weasel.yaml", "config_version");
      return (workspace != 0 && weasel != 0) ? 1 : 0;
    } finally {
      RimeFinalize();
      foreach (IntPtr pointer in pointers) Marshal.FreeHGlobal(pointer);
    }
  }
}
"@

    try {
        $compiledTypes = Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop -PassThru
        $deployType = $compiledTypes | Where-Object { $_.FullName -eq $typeName } | Select-Object -First 1
        if ($null -eq $deployType) { throw 'Could not load the temporary Rime deployment helper.' }
        $sharedDataDir = Join-Path $WeaselRoot 'data'
        $version = if ((Split-Path -Leaf $WeaselRoot) -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { 'unknown' }
        $result = $deployType::Run($sharedDataDir, $UserDataDir, $version, $LogDir)
        if ($result -ne 1) { throw 'Rime reported that deployment failed.' }
    } finally {
        if (Test-Path -LiteralPath $server) {
            Start-Process -FilePath $server -WorkingDirectory $WeaselRoot -WindowStyle Hidden
        }
    }
}

function Install-WeaselDependency {
    if ($NonInteractive -and (-not $InstallWeasel -or -not $AcceptWeaselDownload -or -not $SilentWeaselInstall)) {
        throw (
            "Weasel is not installed. For an unattended installation, explicitly authorize the pinned dependency with " +
            "-InstallWeasel -AcceptWeaselDownload -SilentWeaselInstall, or install Weasel $WeaselVersion first."
        )
    }

    if (-not $InstallWeasel) {
        Write-Host ""
        Write-Host "未检测到小狼毫。inputeng Windows 版需要官方小狼毫 $WeaselVersion。" -ForegroundColor Yellow
        $answer = Read-Host '是否从 Rime 官方 GitHub 下载并启动小狼毫安装程序？[Y/n]'
        if ($answer -and $answer -notmatch '^[Yy]') {
            throw 'Installation cancelled. Weasel was not installed.'
        }
    }

    if (-not $AcceptWeaselDownload -and $InstallWeasel) {
        $answer = Read-Host '确认从 Rime 官方 GitHub 下载固定版本并校验 SHA-256？[Y/n]'
        if ($answer -and $answer -notmatch '^[Yy]') {
            throw 'Installation cancelled. The Weasel download was not authorized.'
        }
    }

    $downloadPath = Join-Path $env:TEMP $WeaselInstallerName
    Write-Host '正在下载官方小狼毫安装程序……'
    Invoke-WebRequest -Uri $WeaselInstallerUrl -OutFile $downloadPath -UseBasicParsing -Headers @{
        'User-Agent' = 'inputeng-installer'
    }
    $actualHash = Get-Sha256 $downloadPath
    if ($actualHash -ne $WeaselInstallerSha256) {
        Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
        throw "Weasel installer SHA-256 mismatch. Expected $WeaselInstallerSha256, got $actualHash."
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $downloadPath
    if ($signature.Status -ne 'Valid') {
        Write-Warning 'Rime 官方小狼毫安装包当前没有有效的 Authenticode 数字签名，Windows 可能显示“未知发布者”；inputeng 已按固定 SHA-256 验证文件完整性。'
    }

    if ($SilentWeaselInstall) {
        Write-Host '校验通过，正在静默安装官方小狼毫。可能会出现 Windows 管理员确认窗口。'
        $process = Start-Process -FilePath $downloadPath -ArgumentList '/S' -Wait -PassThru
    } else {
        Write-Host '校验通过，正在启动官方安装程序。可能会出现 Windows 管理员确认窗口。'
        $process = Start-Process -FilePath $downloadPath -Wait -PassThru
    }
    if ($process.ExitCode -ne 0) {
        throw "Weasel installer exited with code $($process.ExitCode)."
    }
    Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
}

function Install-InputEngBranding {
    $scriptPath = Join-Path $PackageRoot 'helper\brand-weasel.ps1'
    $iconPath = Join-Path $PackageRoot 'branding\inputeng.ico'
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Branding helper missing: $scriptPath" }
    if (-not (Test-Path -LiteralPath $iconPath)) { throw "Branding icon missing: $iconPath" }

    $powershell = Join-Path $PSHOME 'powershell.exe'
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Apply -IconSource "{1}" -BrandName "inputeng"' -f $scriptPath, $iconPath
    Write-Host '正在把 Windows 输入法名称改为 inputeng，并安装 E 图标。可能会出现一次管理员确认窗口。'
    $process = Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "Language-profile branding exited with code $($process.ExitCode)."
    }
    return [ordered]@{
        applied = $true
        name = 'inputeng'
        icon = 'E'
        helperPath = (Join-Path $StateRoot 'helper\brand-weasel.ps1')
    }
}

function Test-InputEngBrandingRegistry {
    $profilePath = 'HKLM:\SOFTWARE\Microsoft\CTF\TIP\{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}\LanguageProfile\0x00000804\{3D02CAB6-2B8E-4781-BA20-1C9267529467}'
    try {
        $profile = Get-ItemProperty -LiteralPath $profilePath
        $iconPath = [string]$profile.IconFile
        return (
            [string]$profile.Description -eq 'inputeng' -and
            $iconPath -and
            (Test-Path -LiteralPath $iconPath) -and
            (Test-Path -LiteralPath (Join-Path $env:ProgramData 'InputTranslate\weasel-profile-backup.json'))
        )
    } catch {
        return $false
    }
}

function Remove-MarkerBlock {
    param([string]$Content, [string]$Name)
    $escaped = [regex]::Escape($Name)
    $pattern = "(?ms)^[ \t]*# >>> input-translate:$escaped\r?\n.*?^[ \t]*# <<< input-translate:$escaped(?:\r?\n)?"
    return [regex]::Replace($Content, $pattern, '')
}

function Update-RimeCustomFile {
    param(
        [string]$Path,
        [string]$MarkerName,
        [string[]]$PatchLines
    )

    $created = -not (Test-Path -LiteralPath $Path)
    $content = if ($created) { '' } else { [System.IO.File]::ReadAllText($Path) }
    $content = Remove-MarkerBlock -Content $content -Name $MarkerName
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }

    $blockLines = @("  # >>> input-translate:$MarkerName")
    foreach ($line in $PatchLines) { $blockLines += "  $line" }
    $blockLines += "  # <<< input-translate:$MarkerName"
    $block = $blockLines -join $newline

    $mappingPattern = '(?m)^patch:\s*(?:#.*)?\r?$'
    $mappingMatch = [regex]::Match($content, $mappingPattern)
    if ($mappingMatch.Success) {
        $insertAt = $mappingMatch.Index + $mappingMatch.Length
        $content = $content.Substring(0, $insertAt) + $newline + $block + $content.Substring($insertAt)
    } else {
        if ([regex]::IsMatch($content, '(?m)^patch\s*:')) {
            throw "Unsupported inline or sequence patch syntax in $Path. The file was not changed."
        }
        if ($content.Length -gt 0 -and -not $content.EndsWith($newline)) { $content += $newline }
        if ($content.Trim().Length -gt 0) { $content += $newline }
        $content += 'patch:' + $newline + $block + $newline
    }

    Write-Utf8File -Path $Path -Content $content
    return $created
}

function Remove-SchemaAppendPatch {
    param([string]$Content)
    return [regex]::Replace(
        $Content,
        '(?m)^[ \t]*["'']?schema_list/@next/schema["'']?[ \t]*:[ \t]*["'']?bilingual_(?:pinyin|sogou)["'']?[ \t]*(?:#.*)?\r?\n?',
        ''
    )
}

function Test-ExplicitSchemaEntry {
    param([string]$Content, [string]$SchemaId = 'bilingual_pinyin')
    $escaped = [regex]::Escape($SchemaId)
    return [regex]::IsMatch(
        $Content,
        ('(?m)^[ \t]*-[ \t]*(?:\{[ \t]*)?schema[ \t]*:[ \t]*["'']?' + $escaped + '["'']?(?:[ \t]*\})?[ \t]*(?:#.*)?\r?$')
    )
}

function Ensure-SchemaListEntries {
    param([string]$Path, [string[]]$SchemaIds)
    $created = -not (Test-Path -LiteralPath $Path)
    $content = if ($created) { '' } else { [System.IO.File]::ReadAllText($Path) }
    $content = Remove-MarkerBlock -Content $content -Name 'schema'
    $content = Remove-SchemaAppendPatch -Content $content
    $missing = @($SchemaIds | Where-Object { -not (Test-ExplicitSchemaEntry -Content $content -SchemaId $_) })
    if ($missing.Count -eq 0) {
        if (-not $created) { Write-Utf8File -Path $Path -Content $content }
        return $created
    }

    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = @($content -split '\r?\n', -1)
    $listIndex = -1
    $parentIndent = ''
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $lineMatch = [regex]::Match($lines[$index], '^(?<indent>[ \t]*)["'']?schema_list["'']?[ \t]*:[ \t]*(?:#.*)?$')
        if ($lineMatch.Success) {
            $listIndex = $index
            $parentIndent = $lineMatch.Groups['indent'].Value
            break
        }
    }
    if ($listIndex -ge 0) {
        $insertIndex = $listIndex + 1
        while ($insertIndex -lt $lines.Count -and $lines[$insertIndex].Trim().Length -gt 0) {
            $leading = [regex]::Match($lines[$insertIndex], '^[ \t]*').Value
            if ($leading.Length -le $parentIndent.Length) { break }
            $insertIndex++
        }
        $childIndent = $parentIndent + '  '
        $addition = @($missing | ForEach-Object { $childIndent + '- {schema: ' + $_ + '}' })
        $before = if ($insertIndex -gt 0) { @($lines[0..($insertIndex - 1)]) } else { @() }
        $after = if ($insertIndex -lt $lines.Count) { @($lines[$insertIndex..($lines.Count - 1)]) } else { @() }
        $content = (@($before) + $addition + @($after)) -join $newline
        Write-Utf8File -Path $Path -Content $content
        return $created
    }

    [void](Update-RimeCustomFile -Path $Path -MarkerName 'schema' -PatchLines @(
        'schema_list:'
        ($SchemaIds | ForEach-Object { '  - {schema: ' + $_ + '}' })
    ))
    return $created
}

function Remove-GeneratedThemeEntries {
    param([string]$Content)
    foreach ($name in @('input_translate_light', 'input_translate_dark')) {
        $escaped = [regex]::Escape($name)
        $pattern = "(?m)^[ ]{2}[`"']?preset_color_schemes/$escaped[`"']?\s*:\s*\r?\n(?:^[ ]{4,}.*(?:\r?\n|$))*"
        $Content = [regex]::Replace($Content, $pattern, '')
    }
    return $Content
}

function Update-RimeCustomizationModifiedTime {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    $content = [System.IO.File]::ReadAllText($Path)
    $timestamp = (Get-Date).ToString(
        'ddd MMM dd HH:mm:ss yyyy',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    $pattern = '(?m)^(?<prefix>[ \t]*modified_time[ \t]*:[ \t]*).*(?:\r)?$'
    if (-not [regex]::IsMatch($content, $pattern)) { return $false }

    $updated = [regex]::Replace(
        $content,
        $pattern,
        { param($match) $match.Groups['prefix'].Value + '"' + $timestamp + '"' }
    )
    if ($updated -eq $content) { return $false }
    Write-Utf8File -Path $Path -Content $updated
    return $true
}

function Normalize-DefaultCustomAfterDeploy {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $content = [System.IO.File]::ReadAllText($Path)
    if (-not (Test-ExplicitSchemaEntry -Content $content)) { return $false }
    $cleaned = Remove-MarkerBlock -Content $content -Name 'schema'
    $cleaned = Remove-SchemaAppendPatch -Content $cleaned
    if ($cleaned -eq $content) { return $false }
    Write-Utf8File -Path $Path -Content $cleaned
    [void](Update-RimeCustomizationModifiedTime -Path $Path)
    return $true
}

function Get-ExistingManifest {
    param([string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath)) { return $null }
    try { return (Get-Content -Raw -LiteralPath $ManifestPath -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

function Find-OldManagedFile {
    param($Manifest, [string]$RelativePath)
    if ($null -eq $Manifest -or $null -eq $Manifest.managedFiles) { return $null }
    return $Manifest.managedFiles | Where-Object { $_.relativePath -eq $RelativePath } | Select-Object -First 1
}

function Install-BackgroundHelper {
    param(
        [string]$StateRoot,
        [string]$RimeUserDir
    )

    $sourceDir = Join-Path $PackageRoot 'helper'
    foreach ($name in @('worker.ps1', 'start-worker.ps1', 'configure-deepseek.ps1', 'settings.ps1', 'settings-ui.ps1', 'deploy-rime.ps1', 'brand-weasel.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $name))) {
            throw "Background helper file missing: $name"
        }
    }

    $helperDir = Join-Path $StateRoot 'helper'
    $stopPath = Join-Path $StateRoot 'worker.stop'
    [System.IO.File]::WriteAllText($stopPath, 'stop', $Utf8NoBom)
    Start-Sleep -Milliseconds 800
    New-Item -ItemType Directory -Force -Path $helperDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceDir 'worker.ps1') -Destination $helperDir -Force
    Copy-Item -LiteralPath (Join-Path $sourceDir 'start-worker.ps1') -Destination $helperDir -Force
    Copy-Item -LiteralPath (Join-Path $sourceDir 'configure-deepseek.ps1') -Destination $helperDir -Force
    Copy-Item -LiteralPath (Join-Path $sourceDir 'settings.ps1') -Destination $helperDir -Force
    Copy-Item -LiteralPath (Join-Path $sourceDir 'settings-ui.ps1') -Destination $helperDir -Force
    Copy-Item -LiteralPath (Join-Path $sourceDir 'deploy-rime.ps1') -Destination $helperDir -Force
    Copy-Item -LiteralPath (Join-Path $sourceDir 'brand-weasel.ps1') -Destination $helperDir -Force

    $powershell = Join-Path $PSHOME 'powershell.exe'
    $startScript = Join-Path $helperDir 'start-worker.ps1'
    $configureScript = Join-Path $helperDir 'configure-deepseek.ps1'
    $settingsScript = Join-Path $helperDir 'settings.ps1'
    $workerArguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -StateRoot "{1}" -RimeUserDir "{2}"' -f $startScript, $StateRoot, $RimeUserDir
    $runCommand = '"{0}" {1}' -f $powershell, $workerArguments
    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $runPath -Force | Out-Null
    New-ItemProperty -Path $runPath -Name 'InputTranslateDeepSeekWorker' -Value $runCommand -PropertyType String -Force | Out-Null

    $programs = [Environment]::GetFolderPath('Programs')
    $legacyStartMenuDir = Join-Path $programs 'Input Translate'
    if (Test-Path -LiteralPath $legacyStartMenuDir) {
        foreach ($legacyShortcut in @('配置 DeepSeek.lnk', 'Input Translate 设置.lnk')) {
            Remove-Item -LiteralPath (Join-Path $legacyStartMenuDir $legacyShortcut) -Force -ErrorAction SilentlyContinue
        }
        if (-not (Get-ChildItem -LiteralPath $legacyStartMenuDir -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $legacyStartMenuDir -Force -ErrorAction SilentlyContinue
        }
    }
    $startMenuDir = Join-Path $programs 'inputeng'
    New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null
    $shortcutPath = Join-Path $startMenuDir '配置 DeepSeek.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -StateRoot "{1}" -RimeUserDir "{2}"' -f $configureScript, $StateRoot, $RimeUserDir
    $shortcut.WorkingDirectory = $helperDir
    $shortcut.Description = '配置 inputeng 的 DeepSeek 缺词补全'
    $shortcut.Save()

    $settingsShortcutPath = Join-Path $startMenuDir 'inputeng 设置.lnk'
    $settingsShortcut = $shell.CreateShortcut($settingsShortcutPath)
    $settingsShortcut.TargetPath = $powershell
    $settingsShortcut.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Sta -File "{0}" -StateRoot "{1}" -RimeUserDir "{2}"' -f $settingsScript, $StateRoot, $RimeUserDir
    $settingsShortcut.WorkingDirectory = $helperDir
    $settingsShortcut.Description = '配置 inputeng 外观、词库与 AI 翻译'
    $settingsShortcut.Save()

    Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
    & $startScript -StateRoot $StateRoot -RimeUserDir $RimeUserDir

    return [ordered]@{
        helperDir = $helperDir
        runValueName = 'InputTranslateDeepSeekWorker'
        startMenuDir = $startMenuDir
        shortcutPath = $shortcutPath
        settingsShortcutPath = $settingsShortcutPath
    }
}

if (-not $StateRoot) {
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is unavailable.' }
    $StateRoot = Join-Path $env:LOCALAPPDATA 'InputTranslate\windows-rime'
}
$StateRoot = [System.IO.Path]::GetFullPath($StateRoot)
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
$ManifestPath = Join-Path $StateRoot 'install-manifest.json'
$OldManifest = Get-ExistingManifest -ManifestPath $ManifestPath

$WeaselRoot = Get-WeaselRoot
if (-not $SkipWeaselCheck -and -not $WeaselRoot) {
    Install-WeaselDependency
    $WeaselRoot = Get-WeaselRoot
    if (-not $WeaselRoot) {
        throw 'Weasel installation finished, but WeaselDeployer.exe could not be found.'
    }
}

if (-not $RimeUserDir) {
    $customUserDir = ''
    try {
        $customUserDir = [string](Get-ItemPropertyValue -Path 'HKCU:\Software\Rime\Weasel' -Name 'RimeUserDir' -ErrorAction SilentlyContinue)
    } catch { $customUserDir = '' }
    if ($customUserDir) {
        $RimeUserDir = $customUserDir
    } else {
        if (-not $env:APPDATA) { throw 'APPDATA is unavailable.' }
        $RimeUserDir = Join-Path $env:APPDATA 'Rime'
    }
}
$RimeUserDir = [System.IO.Path]::GetFullPath($RimeUserDir)
New-Item -ItemType Directory -Force -Path $RimeUserDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RimeUserDir 'lua') | Out-Null

$backupStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path (Join-Path $StateRoot 'backups') $backupStamp
$managedSources = @(
    @{ RelativePath = 'bilingual_pinyin.schema.yaml'; Source = (Join-Path $PackageRoot 'bilingual_pinyin.schema.yaml') },
    @{ RelativePath = 'bilingual_sogou.schema.yaml'; Source = (Join-Path $PackageRoot 'bilingual_sogou.schema.yaml') },
    @{ RelativePath = 'input_translate_core.dict.yaml'; Source = (Join-Path $PackageRoot 'input_translate_core.dict.yaml') },
    @{ RelativePath = 'cn_dicts\8105.dict.yaml'; Source = (Join-Path $PackageRoot 'cn_dicts\8105.dict.yaml') },
    @{ RelativePath = 'cn_dicts\base.dict.yaml'; Source = (Join-Path $PackageRoot 'cn_dicts\base.dict.yaml') },
    @{ RelativePath = 'cn_dicts\modern.dict.yaml'; Source = (Join-Path $PackageRoot 'cn_dicts\modern.dict.yaml') },
    @{ RelativePath = 'bilingual_english.tsv'; Source = (Join-Path $PackageRoot 'bilingual_english.tsv') },
    @{ RelativePath = 'common_gloss_overrides.tsv'; Source = (Join-Path $PackageRoot 'common_gloss_overrides.tsv') },
    @{ RelativePath = 'english_chinese.tsv'; Source = (Join-Path $PackageRoot 'english_chinese.tsv') },
    @{ RelativePath = 'lua\bilingual_comment.lua'; Source = (Join-Path $PackageRoot 'lua\bilingual_comment.lua') },
    @{ RelativePath = 'lua\english_comment_translator.lua'; Source = (Join-Path $PackageRoot 'lua\english_comment_translator.lua') },
    @{ RelativePath = 'lua\english_mode_filter.lua'; Source = (Join-Path $PackageRoot 'lua\english_mode_filter.lua') },
    @{ RelativePath = 'lua\personal_phrase_processor.lua'; Source = (Join-Path $PackageRoot 'lua\personal_phrase_processor.lua') },
    @{ RelativePath = 'lua\personal_phrase_translator.lua'; Source = (Join-Path $PackageRoot 'lua\personal_phrase_translator.lua') },
    @{ RelativePath = 'lua\schema_toggle_processor.lua'; Source = (Join-Path $PackageRoot 'lua\schema_toggle_processor.lua') }
)

$managedManifest = @()
foreach ($item in $managedSources) {
    if (-not (Test-Path -LiteralPath $item.Source)) { throw "Package file missing: $($item.Source)" }
    $target = Join-Path $RimeUserDir $item.RelativePath
    $targetParent = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
    $sourceHash = Get-Sha256 $item.Source
    $oldEntry = Find-OldManagedFile -Manifest $OldManifest -RelativePath $item.RelativePath
    $backupPath = $null

    if (Test-Path -LiteralPath $target) {
        $targetHash = Get-Sha256 $target
        $isPreviousManagedCopy = $null -ne $oldEntry -and $targetHash -eq ([string]$oldEntry.installedSha256)
        if ($isPreviousManagedCopy -and $oldEntry.backupPath) {
            $backupPath = [string]$oldEntry.backupPath
        } elseif ($targetHash -ne $sourceHash) {
            $backupPath = Join-Path $backupRoot $item.RelativePath
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
            Copy-Item -LiteralPath $target -Destination $backupPath -Force
        }
    }

    Copy-Item -LiteralPath $item.Source -Destination $target -Force
    $managedManifest += [ordered]@{
        relativePath = $item.RelativePath
        installedSha256 = $sourceHash
        backupPath = $backupPath
    }
}

$defaultCustomPath = Join-Path $RimeUserDir 'default.custom.yaml'
$weaselCustomPath = Join-Path $RimeUserDir 'weasel.custom.yaml'
$schemaStyleCustomPath = Join-Path $RimeUserDir 'bilingual_pinyin.custom.yaml'
$doubleSchemaStyleCustomPath = Join-Path $RimeUserDir 'bilingual_sogou.custom.yaml'
$oldDefaultCustom = if ($null -ne $OldManifest) { $OldManifest.customFiles | Where-Object { $_.name -eq 'default.custom.yaml' } | Select-Object -First 1 } else { $null }
$oldWeaselCustom = if ($null -ne $OldManifest) { $OldManifest.customFiles | Where-Object { $_.name -eq 'weasel.custom.yaml' } | Select-Object -First 1 } else { $null }
$oldSchemaStyleCustom = if ($null -ne $OldManifest) { $OldManifest.customFiles | Where-Object { $_.name -eq 'bilingual_pinyin.custom.yaml' } | Select-Object -First 1 } else { $null }
$oldDoubleSchemaStyleCustom = if ($null -ne $OldManifest) { $OldManifest.customFiles | Where-Object { $_.name -eq 'bilingual_sogou.custom.yaml' } | Select-Object -First 1 } else { $null }

$defaultExistedBefore = Test-Path -LiteralPath $defaultCustomPath
if ($defaultExistedBefore) {
    $defaultRaw = [System.IO.File]::ReadAllText($defaultCustomPath)
    $defaultClean = Remove-MarkerBlock -Content $defaultRaw -Name 'schema'
    $defaultClean = Remove-MarkerBlock -Content $defaultClean -Name 'hotkeys'
    $defaultClean = Remove-SchemaAppendPatch -Content $defaultClean
    if ($defaultClean -ne $defaultRaw) { Write-Utf8File -Path $defaultCustomPath -Content $defaultClean }
} else {
    $defaultClean = ''
}
$defaultCreatedNow = Ensure-SchemaListEntries -Path $defaultCustomPath -SchemaIds @('bilingual_pinyin', 'bilingual_sogou')
[void](Update-RimeCustomFile -Path $defaultCustomPath -MarkerName 'hotkeys' -PatchLines @(
    '"switcher/hotkeys": [Control+grave]'
))

$weaselExistedBefore = Test-Path -LiteralPath $weaselCustomPath
if ($weaselExistedBefore) {
    $weaselRaw = [System.IO.File]::ReadAllText($weaselCustomPath)
    $weaselClean = Remove-MarkerBlock -Content $weaselRaw -Name 'theme'
    $weaselClean = Remove-GeneratedThemeEntries -Content $weaselClean
    if ($weaselClean -ne $weaselRaw) { Write-Utf8File -Path $weaselCustomPath -Content $weaselClean }
}
$accentLight = '0xec4899ff'
$accentDark = '0xdb2777ff'
$candidateFontPoint = 12
$commentFontPoint = 9
$preeditPlacement = 'inline'
$settingsPath = Join-Path $StateRoot 'settings.json'
if (Test-Path -LiteralPath $settingsPath) {
    try {
        $savedSettings = Get-Content -Raw -LiteralPath $settingsPath -Encoding UTF8 | ConvertFrom-Json
        $savedAccent = [string]$savedSettings.accentColor
        if ($savedAccent -match '^#[0-9A-Fa-f]{6}$') {
            $customRgba = '0x' + $savedAccent.Substring(1).ToLowerInvariant() + 'ff'
            $accentLight = $customRgba
            $accentDark = $customRgba
        }
        $savedCandidateFontPoint = 0
        if ([int]::TryParse([string]$savedSettings.candidateFontPoint, [ref]$savedCandidateFontPoint) -and
            $savedCandidateFontPoint -ge 11 -and $savedCandidateFontPoint -le 22) {
            $candidateFontPoint = $savedCandidateFontPoint
        }
        $savedCommentFontPoint = 0
        if ([int]::TryParse([string]$savedSettings.commentFontPoint, [ref]$savedCommentFontPoint) -and
            $savedCommentFontPoint -ge 8 -and $savedCommentFontPoint -le 16) {
            $commentFontPoint = $savedCommentFontPoint
        }
        # v0.5.3 always keeps preedit in the application input field. This
        # avoids the extra candidate-window header row.
    } catch { }
}
$inlinePreedit = 'true'
$schemaStyleCreatedNow = Update-RimeCustomFile -Path $schemaStyleCustomPath -MarkerName 'style' -PatchLines @(
    ('"style/font_point": ' + $candidateFontPoint)
    ('"style/comment_font_point": ' + $commentFontPoint)
    ('"style/inline_preedit": ' + $inlinePreedit)
)
$doubleSchemaStyleCreatedNow = Update-RimeCustomFile -Path $doubleSchemaStyleCustomPath -MarkerName 'style' -PatchLines @(
    ('"style/font_point": ' + $candidateFontPoint)
    ('"style/comment_font_point": ' + $commentFontPoint)
    ('"style/inline_preedit": ' + $inlinePreedit)
)
$weaselCreatedNow = Update-RimeCustomFile -Path $weaselCustomPath -MarkerName 'theme' -PatchLines @(
    '"preset_color_schemes/input_translate_light":',
    '  name: "inputeng Light"',
    '  color_format: rgba',
    '  back_color: 0xffffffff',
    '  border_color: 0xe5e7ebff',
    '  text_color: 0x111827ff',
    '  candidate_text_color: 0x111827ff',
    '  label_color: 0x9ca3afff',
    '  comment_text_color: 0x8a8f98ff',
    '  hilited_text_color: 0x111827ff',
    '  hilited_back_color: 0xffffffff',
    '  hilited_candidate_text_color: 0xffffffff',
    '  hilited_label_color: 0xffffffff',
    '  hilited_comment_text_color: 0xffffffff',
    "  hilited_candidate_back_color: $accentLight",
    '  shadow_color: 0x00000020',
    '"preset_color_schemes/input_translate_dark":',
    '  name: "inputeng Dark"',
    '  color_format: rgba',
    '  back_color: 0x202124ff',
    '  border_color: 0x3c4043ff',
    '  text_color: 0xf1f3f4ff',
    '  candidate_text_color: 0xf1f3f4ff',
    '  label_color: 0x9aa0a6ff',
    '  comment_text_color: 0x9aa0a6ff',
    '  hilited_text_color: 0xf1f3f4ff',
    '  hilited_back_color: 0x202124ff',
    '  hilited_candidate_text_color: 0xffffffff',
    '  hilited_label_color: 0xffffffff',
    '  hilited_comment_text_color: 0xffffffff',
    "  hilited_candidate_back_color: $accentDark",
    '  shadow_color: 0x00000060'
)

# Weasel's settings UI writes a customization timestamp into generated custom
# files. Refresh it after our edits so Rime does not mistake a newer file for an
# already-deployed configuration merely because that embedded timestamp stayed
# unchanged.
[void](Update-RimeCustomizationModifiedTime -Path $defaultCustomPath)
[void](Update-RimeCustomizationModifiedTime -Path $weaselCustomPath)
[void](Update-RimeCustomizationModifiedTime -Path $schemaStyleCustomPath)
[void](Update-RimeCustomizationModifiedTime -Path $doubleSchemaStyleCustomPath)

$defaultCreated = if ($null -ne $oldDefaultCustom) { [bool]$oldDefaultCustom.createdByInstaller } else { [bool]$defaultCreatedNow }
$weaselCreated = if ($null -ne $oldWeaselCustom) { [bool]$oldWeaselCustom.createdByInstaller } else { [bool]$weaselCreatedNow }
$schemaStyleCreated = if ($null -ne $oldSchemaStyleCustom) { [bool]$oldSchemaStyleCustom.createdByInstaller } else { [bool]$schemaStyleCreatedNow }
$doubleSchemaStyleCreated = if ($null -ne $oldDoubleSchemaStyleCustom) { [bool]$oldDoubleSchemaStyleCustom.createdByInstaller } else { [bool]$doubleSchemaStyleCreatedNow }

$backgroundWorker = $null
if (-not $SkipBackgroundWorker) {
    $backgroundWorker = Install-BackgroundHelper -StateRoot $StateRoot -RimeUserDir $RimeUserDir
}

$branding = $null
if (-not $SkipWeaselCheck -and (Test-InputEngBrandingRegistry)) {
    $branding = [ordered]@{
        applied = $true
        name = 'inputeng'
        icon = 'E'
        helperPath = (Join-Path $StateRoot 'helper\brand-weasel.ps1')
        mayRequireSignOut = $true
    }
} elseif (-not $SkipBranding -and -not $SkipWeaselCheck) {
    try {
        $branding = Install-InputEngBranding
    } catch {
        Write-Warning "inputeng 名称和 E 图标未能应用：$($_.Exception.Message)"
    }
}

$manifest = [ordered]@{
    product = $ProductName
    version = $ProductVersion
    installedAt = (Get-Date).ToString('o')
    rimeUserDir = $RimeUserDir
    managedFiles = $managedManifest
    customFiles = @(
        [ordered]@{ name = 'default.custom.yaml'; marker = 'schema'; createdByInstaller = $defaultCreated },
        [ordered]@{ name = 'default.custom.yaml'; marker = 'hotkeys'; createdByInstaller = $defaultCreated },
        [ordered]@{ name = 'weasel.custom.yaml'; marker = 'theme'; createdByInstaller = $weaselCreated },
        [ordered]@{ name = 'bilingual_pinyin.custom.yaml'; marker = 'style'; createdByInstaller = $schemaStyleCreated },
        [ordered]@{ name = 'bilingual_sogou.custom.yaml'; marker = 'style'; createdByInstaller = $doubleSchemaStyleCreated }
    )
    backgroundWorker = $backgroundWorker
    branding = $branding
}
Write-Utf8File -Path $ManifestPath -Content ($manifest | ConvertTo-Json -Depth 6)

if (-not $SkipDeploy) {
    if (-not $WeaselRoot) { $WeaselRoot = Get-WeaselRoot }
    if (-not $WeaselRoot) { throw 'Weasel installation was not found; files were installed but deployment did not run.' }
    Write-Host '正在重新部署小狼毫……'
    Invoke-RimeWorkspaceDeploy `
        -WeaselRoot $WeaselRoot `
        -UserDataDir $RimeUserDir `
        -LogDir (Join-Path $StateRoot 'logs')
}

Write-Host ""
Write-Host "$ProductName $ProductVersion 安装完成。" -ForegroundColor Green
Write-Host "Rime 用户目录：$RimeUserDir"
if (-not $SkipDeploy) {
    Write-Host 'inputeng 已启用；按 F4 可在全拼与搜狗双拼之间直接切换。Ctrl+` 仍可打开完整方案菜单。'
}
if (-not $SkipBackgroundWorker) {
Write-Host '外观、词库与 AI 翻译设置入口：开始菜单 → inputeng → inputeng 设置。'
    Write-Host 'DeepSeek 缺词补全入口：开始菜单 → inputeng → 配置 DeepSeek。'
}
if ($null -ne $branding) {
    Write-Host 'inputeng 名称和 E 图标已写入 Windows 语言配置。' -ForegroundColor Green
    Write-Warning 'Windows 可能继续显示已缓存的“小狼毫”名称或旧图标。若 Win + Space 未立即更新，请注销当前 Windows 账户并重新登录；安装器不会强制结束 ctfmon.exe、TextInputHost.exe 或 explorer.exe。'
}

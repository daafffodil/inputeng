[CmdletBinding()]
param(
    [string]$StateRoot,
    [string]$RimeUserDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

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
                if ($root -and (Test-Path -LiteralPath (Join-Path $root 'rime.dll'))) { return $root }
                if ($root -and (Test-Path -LiteralPath $root)) {
                    $versioned = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'rime.dll') } |
                        Sort-Object Name -Descending | Select-Object -First 1
                    if ($null -ne $versioned) { return $versioned.FullName }
                }
            } else {
                $base.Dispose()
            }
        } catch { }
    }
    return $null
}

if (-not $StateRoot) {
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is unavailable.' }
    $StateRoot = Join-Path $env:LOCALAPPDATA 'InputTranslate\windows-rime'
}
if (-not $RimeUserDir) {
    if (-not $env:APPDATA) { throw 'APPDATA is unavailable.' }
    $RimeUserDir = Join-Path $env:APPDATA 'Rime'
}

$StateRoot = [System.IO.Path]::GetFullPath($StateRoot)
$RimeUserDir = [System.IO.Path]::GetFullPath($RimeUserDir)
$root = Get-WeaselRoot
if (-not $root) { throw 'Weasel was not found.' }
$rimeDll = Join-Path $root 'rime.dll'
$server = Join-Path $root 'WeaselServer.exe'
$logDir = Join-Path $StateRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if (Test-Path -LiteralPath $server) {
    & $server /q | Out-Null
    Start-Sleep -Milliseconds 800
}

$typeName = 'InputTranslateSettingsDeploy' + $PID
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
    if ($null -eq $deployType) { throw 'Could not load the Rime deployment helper.' }
    $sharedDataDir = Join-Path $root 'data'
    $version = if ((Split-Path -Leaf $root) -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { 'unknown' }
    $result = $deployType::Run($sharedDataDir, $RimeUserDir, $version, $logDir)
    if ($result -ne 1) { throw 'Rime reported that deployment failed.' }
} finally {
    if (Test-Path -LiteralPath $server) {
        Start-Process -FilePath $server -WorkingDirectory $root -WindowStyle Hidden | Out-Null
    }
}


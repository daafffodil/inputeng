[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Restore')]
    [string]$Action,
    [string]$IconSource,
    [string]$BrandName = 'inputeng'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator privileges are required to brand the Windows language profile.'
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$TipGuid = '{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}'
$ProfileGuid = '{3D02CAB6-2B8E-4781-BA20-1C9267529467}'
$ProfilePath = "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$TipGuid\LanguageProfile\0x00000804\$ProfileGuid"
$BrandRoot = Join-Path $env:ProgramData 'InputTranslate'
$InstalledIcon = Join-Path $BrandRoot 'inputeng.ico'
$BackupPath = Join-Path $BrandRoot 'weasel-profile-backup.json'

if (-not (Test-Path -LiteralPath $ProfilePath)) {
    throw "The Simplified Chinese Weasel language profile was not found: $ProfilePath"
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temporary = "$Path.tmp"
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 5), $Utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

if ($Action -eq 'Apply') {
    if (-not $IconSource -or -not (Test-Path -LiteralPath $IconSource)) {
        throw "Brand icon was not found: $IconSource"
    }

    New-Item -ItemType Directory -Force -Path $BrandRoot | Out-Null
    if (-not (Test-Path -LiteralPath $BackupPath)) {
        $profile = Get-ItemProperty -LiteralPath $ProfilePath
        $backup = [ordered]@{
            profilePath = $ProfilePath
            description = [string]$profile.Description
            iconFile = [string]$profile.IconFile
            iconIndex = [int]$profile.IconIndex
            capturedAt = (Get-Date).ToString('o')
        }
        Write-JsonAtomic -Path $BackupPath -Value $backup
    }

    Copy-Item -LiteralPath $IconSource -Destination $InstalledIcon -Force
    Set-ItemProperty -LiteralPath $ProfilePath -Name Description -Value $BrandName -Type String
    Set-ItemProperty -LiteralPath $ProfilePath -Name IconFile -Value $InstalledIcon -Type String
    Set-ItemProperty -LiteralPath $ProfilePath -Name IconIndex -Value 0 -Type DWord
    Write-Host "Windows language profile branded as $BrandName."
    exit 0
}

if (-not (Test-Path -LiteralPath $BackupPath)) {
    Write-Host 'No inputeng language-profile backup was found; nothing to restore.'
    exit 0
}

$backup = Get-Content -Raw -LiteralPath $BackupPath -Encoding UTF8 | ConvertFrom-Json
$restorePath = [string]$backup.profilePath
if (-not $restorePath -or -not (Test-Path -LiteralPath $restorePath)) {
    $restorePath = $ProfilePath
}
Set-ItemProperty -LiteralPath $restorePath -Name Description -Value ([string]$backup.description) -Type String
Set-ItemProperty -LiteralPath $restorePath -Name IconFile -Value ([string]$backup.iconFile) -Type String
Set-ItemProperty -LiteralPath $restorePath -Name IconIndex -Value ([int]$backup.iconIndex) -Type DWord
Remove-Item -LiteralPath $InstalledIcon -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
if ((Test-Path -LiteralPath $BrandRoot) -and -not (Get-ChildItem -LiteralPath $BrandRoot -Force -ErrorAction SilentlyContinue)) {
    Remove-Item -LiteralPath $BrandRoot -Force -ErrorAction SilentlyContinue
}
Write-Host 'The original Weasel Windows language profile branding was restored.'

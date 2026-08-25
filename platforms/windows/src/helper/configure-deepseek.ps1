[CmdletBinding()]
param(
    [string]$StateRoot,
    [string]$RimeUserDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$exitCode = 0

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
$ConfigPath = Join-Path $StateRoot 'deepseek-config.json'
$KeyPath = Join-Path $StateRoot 'deepseek.key.dpapi'
$StopPath = Join-Path $StateRoot 'worker.stop'
$EnabledPath = Join-Path $RimeUserDir 'input_translate_ai_enabled'
$StartScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'start-worker.ps1'

function Write-Config {
    param([bool]$Enabled)
    $config = [ordered]@{
        enabled = $Enabled
        provider = 'deepseek'
        endpoint = 'https://api.deepseek.com/chat/completions'
        model = 'deepseek-v4-flash'
        thinking = 'disabled'
        maxGlossCharacters = 24
    } | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($ConfigPath, $config, $Utf8NoBom)
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$cuttingBoardPath = Join-Path $env:LOCALAPPDATA 'CuttingBoard\app\CuttingBoard.exe'
$restartCuttingBoard = $false
$cuttingBoardProcesses = @(Get-Process CuttingBoard -ErrorAction SilentlyContinue)
if ($cuttingBoardProcesses.Count -gt 0) {
    $cuttingBoardProcesses | Stop-Process -Force
    $restartCuttingBoard = Test-Path -LiteralPath $cuttingBoardPath
    Start-Sleep -Milliseconds 300
}

try {
    $configured = (Test-Path -LiteralPath $KeyPath) -and (Test-Path -LiteralPath $EnabledPath)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'inputeng - DeepSeek'
    $form.ClientSize = New-Object System.Drawing.Size(430, 225)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $true
    $form.TopMost = $true
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = 'DeepSeek 缺词翻译'
    $titleLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
    $titleLabel.AutoSize = $true
    $titleLabel.Location = New-Object System.Drawing.Point(22, 18)
    $form.Controls.Add($titleLabel)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = '当前状态：' + $(if ($configured) { '已启用' } else { '未启用' })
    $statusLabel.AutoSize = $true
    $statusLabel.ForeColor = if ($configured) { [System.Drawing.Color]::SeaGreen } else { [System.Drawing.Color]::DimGray }
    $statusLabel.Location = New-Object System.Drawing.Point(24, 52)
    $form.Controls.Add($statusLabel)

    $keyLabel = New-Object System.Windows.Forms.Label
    $keyLabel.Text = if ($configured) { '粘贴新 API Key（留空则不修改）' } else { '粘贴 DeepSeek API Key' }
    $keyLabel.AutoSize = $true
    $keyLabel.Location = New-Object System.Drawing.Point(24, 82)
    $form.Controls.Add($keyLabel)

    $keyBox = New-Object System.Windows.Forms.TextBox
    $keyBox.Location = New-Object System.Drawing.Point(26, 105)
    $keyBox.Size = New-Object System.Drawing.Size(378, 28)
    $keyBox.UseSystemPasswordChar = $true
    $keyBox.ShortcutsEnabled = $true
    $form.Controls.Add($keyBox)

    $privacyLabel = New-Object System.Windows.Forms.Label
    $privacyLabel.Text = 'Key 仅以 Windows DPAPI 加密保存；只发送本地词典未命中的简体候选词。'
    $privacyLabel.AutoSize = $true
    $privacyLabel.ForeColor = [System.Drawing.Color]::DimGray
    $privacyLabel.Location = New-Object System.Drawing.Point(24, 139)
    $form.Controls.Add($privacyLabel)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = '保存并启用'
    $saveButton.Size = New-Object System.Drawing.Size(98, 32)
    $saveButton.Location = New-Object System.Drawing.Point(306, 178)
    $saveButton.Add_Click({
        $candidate = $keyBox.Text.Trim()
        if ($candidate.Length -eq 0 -and $configured) {
            $form.Tag = 'keep'
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
            return
        }
        if ($candidate.Length -lt 8) {
            [void][System.Windows.Forms.MessageBox]::Show(
                $form,
                'API Key 为空或过短，请重新粘贴。',
                'inputeng',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            $keyBox.Focus()
            return
        }
        $form.Tag = 'save|' + $candidate
        $keyBox.Clear()
        $candidate = $null
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($saveButton)
    $form.AcceptButton = $saveButton

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = '取消'
    $cancelButton.Size = New-Object System.Drawing.Size(74, 32)
    $cancelButton.Location = New-Object System.Drawing.Point(218, 178)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    if ($configured) {
        $disableButton = New-Object System.Windows.Forms.Button
        $disableButton.Text = '停用联网补全'
        $disableButton.Size = New-Object System.Drawing.Size(112, 32)
        $disableButton.Location = New-Object System.Drawing.Point(26, 178)
        $disableButton.Add_Click({
            $form.Tag = 'disable'
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        })
        $form.Controls.Add($disableButton)
    }

    $form.Add_Shown({ $keyBox.Focus() })
    $result = $form.ShowDialog()
    $action = if ($null -eq $form.Tag) { '' } else { [string]$form.Tag }
    $form.Tag = $null
    $keyBox.Clear()
    try { [System.Windows.Forms.Clipboard]::Clear() } catch { }
    $form.Dispose()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK -or -not $action) {
        # User cancelled. Leave the existing configuration unchanged.
    } elseif ($action -eq 'keep') {
        # Existing configuration stays active.
    } elseif ($action -eq 'disable') {
        Write-Config -Enabled $false
        Remove-Item -LiteralPath $EnabledPath -Force -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllText($StopPath, 'stop', $Utf8NoBom)
        [void][System.Windows.Forms.MessageBox]::Show(
            '已停用 DeepSeek 联网补全；现有本机翻译缓存继续可用。',
            'inputeng',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } elseif ($action.StartsWith('save|')) {
        $plain = $action.Substring(5)
        $action = $null
        $secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
        $plain = $null
        try {
            $encrypted = ConvertFrom-SecureString -SecureString $secure
            [System.IO.File]::WriteAllText($KeyPath, $encrypted, [System.Text.Encoding]::ASCII)
        } finally {
            if ($secure -is [System.IDisposable]) { $secure.Dispose() }
        }

        Write-Config -Enabled $true
        [System.IO.File]::WriteAllText($EnabledPath, 'enabled', $Utf8NoBom)
        Remove-Item -LiteralPath $StopPath -Force -ErrorAction SilentlyContinue

        if (Test-Path -LiteralPath $StartScript) {
            & $StartScript -StateRoot $StateRoot -RimeUserDir $RimeUserDir
        }
        [void][System.Windows.Forms.MessageBox]::Show(
            '保存成功，DeepSeek 缺词翻译已启用。',
            'inputeng',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } else {
        throw 'Unknown configuration action.'
    }
} catch {
    $exitCode = 1
    $message = '配置没有完成。' + [Environment]::NewLine + $_.Exception.Message
    try {
        [void][System.Windows.Forms.MessageBox]::Show(
            $message,
            'inputeng',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    } catch { }
} finally {
    try { [System.Windows.Forms.Clipboard]::Clear() } catch { }
    if ($restartCuttingBoard -and (Test-Path -LiteralPath $cuttingBoardPath)) {
        Start-Process -FilePath $cuttingBoardPath | Out-Null
    }
}

exit $exitCode

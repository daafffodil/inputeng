# WPF settings UI. This script is dot-sourced by settings.ps1 and deliberately
# shares its paths and apply functions.

function Get-DataRowCount {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $count = 0
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        $value = $line.Trim()
        if (-not $value -or $value.StartsWith('#') -or $value -eq '---' -or $value -eq '...') { continue }
        if ($line.Contains("`t")) { $count++ }
    }
    return $count
}

function Format-Count {
    param([long]$Value)
    return $Value.ToString('N0', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-ResourceSnapshot {
    $baseCount = Get-DataRowCount (Join-Path $RimeUserDir 'cn_dicts\base.dict.yaml')
    $singleCount = Get-DataRowCount (Join-Path $RimeUserDir 'cn_dicts\8105.dict.yaml')
    $modernCount = Get-DataRowCount (Join-Path $RimeUserDir 'cn_dicts\modern.dict.yaml')
    $zhEnOffline = Get-DataRowCount $OfflineDictionaryPath
    $enZhOffline = Get-DataRowCount (Join-Path $RimeUserDir 'english_chinese.tsv')
    return [pscustomobject]@{
        ChineseSummary = ('中文核心词库：{0} 条' -f (Format-Count ($baseCount + $singleCount + $modernCount)))
        ChineseDetail = '筛选依据：基于雾凇拼音公开词库，按词频权重保留简体常用词和规范单字。'
        EnglishSummary = ('离线双语释义：中译英 {0} 条｜英译中 {1} 条' -f
            (Format-Count $zhEnOffline), (Format-Count $enZhOffline))
        EnglishDetail = '筛选依据：中译英来自 CC-CEDICT 并按中文核心词库裁剪；英译中来自 ECDICT，只保留适合候选窗显示的短释义。'
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:accent = Get-Accent
$script:fontPoints = Get-FontPoints
$script:resourceSnapshot = Get-ResourceSnapshot

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="inputeng 设置" Width="760" Height="620"
        MinWidth="700" MinHeight="560" WindowStartupLocation="CenterScreen"
        FontFamily="Microsoft YaHei UI" FontSize="13" Background="#F7F8FA">
  <Window.Resources>
    <SolidColorBrush x:Key="AccentBrush" Color="#EC4899"/>
    <SolidColorBrush x:Key="TextBrush" Color="#202124"/>
    <SolidColorBrush x:Key="MutedBrush" Color="#8A8F98"/>
    <Style x:Key="ModernButton" TargetType="Button">
      <Setter Property="Background" Value="White"/>
      <Setter Property="Foreground" Value="#3F444D"/>
      <Setter Property="BorderBrush" Value="#E5E7EB"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.82"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
      <Setter Property="Background" Value="{DynamicResource AccentBrush}"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="StepButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
      <Setter Property="Width" Value="34"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="FontSize" Value="16"/>
    </Style>
    <Style TargetType="TabItem">
      <Setter Property="Foreground" Value="#7A8089"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Padding" Value="22,14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="TabBorder" Background="Transparent" BorderBrush="Transparent" BorderThickness="0,0,0,2">
              <ContentPresenter ContentSource="Header" Margin="{TemplateBinding Padding}"
                                HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True">
                <Setter Property="Foreground" Value="{DynamicResource AccentBrush}"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
                <Setter TargetName="TabBorder" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="64"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <Border Grid.Row="0" Background="White" BorderBrush="#ECEEF1" BorderThickness="0,0,0,1">
      <TextBlock Text="inputeng" Margin="24,0" VerticalAlignment="Center"
                 FontSize="18" FontWeight="SemiBold" Foreground="{StaticResource TextBrush}"/>
    </Border>

    <TabControl Grid.Row="1" Background="Transparent" BorderThickness="0" Margin="16,0,16,16">
      <TabItem Header="外观">
        <Border Background="White" BorderBrush="#ECEEF1" BorderThickness="1" CornerRadius="12">
          <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="24">
            <StackPanel>
              <Border Background="#FAFAFB" BorderBrush="#ECEEF1" BorderThickness="1" CornerRadius="12" Padding="20" Margin="0,0,0,16">
                <StackPanel>
                  <TextBlock Text="候选强调色" FontSize="16" FontWeight="SemiBold" Foreground="{StaticResource TextBrush}"/>
                  <TextBlock Text="选中候选和设置按钮使用这一颜色。" Margin="0,6,0,16" Foreground="{StaticResource MutedBrush}"/>
                  <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Border x:Name="ColorSwatch" Width="54" Height="34" CornerRadius="9" Background="{DynamicResource AccentBrush}"/>
                    <TextBlock x:Name="ColorValue" Margin="12,0,20,0" VerticalAlignment="Center" FontFamily="Consolas"/>
                    <Button x:Name="ChooseColorButton" Content="选择颜色" Style="{StaticResource ModernButton}" Margin="0,0,10,0"/>
                    <Button x:Name="ResetColorButton" Content="恢复默认" Style="{StaticResource ModernButton}"/>
                  </StackPanel>
                </StackPanel>
              </Border>

              <Border Background="#FAFAFB" BorderBrush="#ECEEF1" BorderThickness="1" CornerRadius="12" Padding="20">
                <StackPanel>
                  <TextBlock Text="候选字号" FontSize="16" FontWeight="SemiBold" Foreground="{StaticResource TextBrush}"/>
                  <Grid Margin="0,18,0,12">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="110"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="54"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <TextBlock Text="中文候选" VerticalAlignment="Center"/>
                    <Button x:Name="CandidateMinusButton" Grid.Column="1" Content="−" Style="{StaticResource StepButton}"/>
                    <Border Grid.Column="2" Margin="6,0" Background="White" BorderBrush="#E5E7EB" BorderThickness="1" CornerRadius="6">
                      <TextBlock x:Name="CandidateValue" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource AccentBrush}" FontWeight="SemiBold"/>
                    </Border>
                    <Button x:Name="CandidatePlusButton" Grid.Column="3" Content="+" Style="{StaticResource StepButton}"/>
                  </Grid>
                  <Grid Margin="0,0,0,18">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="110"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="54"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <TextBlock Text="英文小字" VerticalAlignment="Center"/>
                    <Button x:Name="CommentMinusButton" Grid.Column="1" Content="−" Style="{StaticResource StepButton}"/>
                    <Border Grid.Column="2" Margin="6,0" Background="White" BorderBrush="#E5E7EB" BorderThickness="1" CornerRadius="6">
                      <TextBlock x:Name="CommentValue" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource AccentBrush}" FontWeight="SemiBold"/>
                    </Border>
                    <Button x:Name="CommentPlusButton" Grid.Column="3" Content="+" Style="{StaticResource StepButton}"/>
                  </Grid>
                  <StackPanel Orientation="Horizontal">
                    <Button x:Name="ApplyAppearanceButton" Content="保存并应用" Style="{StaticResource PrimaryButton}" Margin="0,0,10,0"/>
                    <Button x:Name="ResetAppearanceButton" Content="恢复默认" Style="{StaticResource ModernButton}"/>
                  </StackPanel>
                </StackPanel>
              </Border>
            </StackPanel>
          </ScrollViewer>
        </Border>
      </TabItem>

      <TabItem Header="词库">
        <Border Background="White" BorderBrush="#ECEEF1" BorderThickness="1" CornerRadius="12">
          <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="24">
            <StackPanel>
              <Border Background="#FAFAFB" BorderBrush="#ECEEF1" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,0,0,12">
                <StackPanel><TextBlock x:Name="ChineseStatusText" FontWeight="SemiBold" Foreground="{StaticResource TextBrush}"/><TextBlock x:Name="ChineseDetailText" Margin="0,7,0,0" Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap"/></StackPanel>
              </Border>
              <Border Background="#FAFAFB" BorderBrush="#ECEEF1" BorderThickness="1" CornerRadius="12" Padding="18">
                <StackPanel><TextBlock x:Name="EnglishStatusText" FontWeight="SemiBold" Foreground="{StaticResource TextBrush}"/><TextBlock x:Name="EnglishDetailText" Margin="0,7,0,0" Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap"/></StackPanel>
              </Border>
            </StackPanel>
          </ScrollViewer>
        </Border>
      </TabItem>

      <TabItem Header="AI 翻译">
        <Border Background="White" BorderBrush="#ECEEF1" BorderThickness="1" CornerRadius="12" Padding="24">
          <Border Background="#FAFAFB" BorderBrush="#ECEEF1" BorderThickness="1" CornerRadius="12" Padding="20" VerticalAlignment="Top">
            <StackPanel>
              <TextBlock Text="DeepSeek 缺词翻译" FontSize="16" FontWeight="SemiBold" Foreground="{StaticResource TextBrush}"/>
              <TextBlock Text="停止输入约半秒后，后台翻译离线词典仍然缺失的短词；不会发送应用正文。" Margin="0,6,0,14" Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap"/>
              <TextBlock x:Name="AiStatusText" Margin="0,0,0,16" FontWeight="SemiBold"/>
              <Button x:Name="ConfigureAiButton" Content="配置 DeepSeek" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left"/>
            </StackPanel>
          </Border>
        </Border>
      </TabItem>
    </TabControl>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Close()

function Find-UiElement {
    param([string]$Name)
    return $window.FindName($Name)
}

$colorSwatch = Find-UiElement 'ColorSwatch'
$colorValue = Find-UiElement 'ColorValue'
$chooseColorButton = Find-UiElement 'ChooseColorButton'
$resetColorButton = Find-UiElement 'ResetColorButton'
$candidateMinusButton = Find-UiElement 'CandidateMinusButton'
$candidatePlusButton = Find-UiElement 'CandidatePlusButton'
$commentMinusButton = Find-UiElement 'CommentMinusButton'
$commentPlusButton = Find-UiElement 'CommentPlusButton'
$candidateValue = Find-UiElement 'CandidateValue'
$commentValue = Find-UiElement 'CommentValue'
$applyAppearanceButton = Find-UiElement 'ApplyAppearanceButton'
$resetAppearanceButton = Find-UiElement 'ResetAppearanceButton'
$chineseStatusText = Find-UiElement 'ChineseStatusText'
$chineseDetailText = Find-UiElement 'ChineseDetailText'
$englishStatusText = Find-UiElement 'EnglishStatusText'
$englishDetailText = Find-UiElement 'EnglishDetailText'
$aiStatusText = Find-UiElement 'AiStatusText'
$configureAiButton = Find-UiElement 'ConfigureAiButton'

function Convert-HexToMediaColor {
    param([string]$Hex)
    return [System.Windows.Media.Color]::FromRgb(
        [Convert]::ToByte($Hex.Substring(1, 2), 16),
        [Convert]::ToByte($Hex.Substring(3, 2), 16),
        [Convert]::ToByte($Hex.Substring(5, 2), 16)
    )
}

function Convert-HexToDrawingColor {
    param([string]$Hex)
    return [System.Drawing.Color]::FromArgb(
        [Convert]::ToInt32($Hex.Substring(1, 2), 16),
        [Convert]::ToInt32($Hex.Substring(3, 2), 16),
        [Convert]::ToInt32($Hex.Substring(5, 2), 16)
    )
}

function New-Brush {
    param([System.Windows.Media.Color]$Color)
    $brush = New-Object System.Windows.Media.SolidColorBrush($Color)
    $brush.Freeze()
    return $brush
}

function Update-AccentResources {
    $color = Convert-HexToMediaColor -Hex $script:accent
    $brush = New-Brush -Color $color
    [void]$window.Resources.Remove('AccentBrush')
    $window.Resources.Add('AccentBrush', $brush)
    $colorSwatch.Background = $brush
    $colorValue.Text = $script:accent
}

function Update-AiStatus {
    $enabled = Test-Path -LiteralPath $AiEnabledPath
    $aiStatusText.Text = if ($enabled) { '状态：已启用' } else { '状态：未启用' }
    $aiStatusText.Foreground = if ($enabled) {
        $window.Resources['AccentBrush']
    } else {
        New-Brush -Color ([System.Windows.Media.Color]::FromRgb(138, 143, 152))
    }
}

function Update-ResourceStatus {
    $script:resourceSnapshot = Get-ResourceSnapshot
    $chineseStatusText.Text = $script:resourceSnapshot.ChineseSummary
    $chineseDetailText.Text = $script:resourceSnapshot.ChineseDetail
    $englishStatusText.Text = $script:resourceSnapshot.EnglishSummary
    $englishDetailText.Text = $script:resourceSnapshot.EnglishDetail
    Update-AiStatus
}

function Show-UiError {
    param([string]$Message)
    [void][System.Windows.MessageBox]::Show($window, $Message, 'inputeng', 'OK', 'Error')
}

function Set-FontEditorValues {
    param([int]$Candidate, [int]$Comment)
    $Candidate = [Math]::Max(11, [Math]::Min(22, $Candidate))
    $Comment = [Math]::Max(8, [Math]::Min(16, $Comment))
    if ($Comment -gt $Candidate) { $Comment = $Candidate }
    $script:fontPoints = [pscustomobject]@{ Candidate = $Candidate; Comment = $Comment }
    $candidateValue.Text = [string]$Candidate
    $commentValue.Text = [string]$Comment
}

function Set-UiAccent {
    param([string]$Accent)
    try {
        Apply-AccentColor -Accent $Accent
        $script:accent = $Accent.ToUpperInvariant()
        Update-AccentResources
        Update-AiStatus
    } catch { Show-UiError -Message $_.Exception.Message }
}

function Save-UiAppearance {
    try {
        Apply-AppearanceSettings -Candidate $script:fontPoints.Candidate -Comment $script:fontPoints.Comment -Placement 'inline'
    } catch { Show-UiError -Message $_.Exception.Message }
}

$candidateMinusButton.Add_Click({ Set-FontEditorValues -Candidate ($script:fontPoints.Candidate - 1) -Comment $script:fontPoints.Comment })
$candidatePlusButton.Add_Click({ Set-FontEditorValues -Candidate ($script:fontPoints.Candidate + 1) -Comment $script:fontPoints.Comment })
$commentMinusButton.Add_Click({ Set-FontEditorValues -Candidate $script:fontPoints.Candidate -Comment ($script:fontPoints.Comment - 1) })
$commentPlusButton.Add_Click({ Set-FontEditorValues -Candidate $script:fontPoints.Candidate -Comment ($script:fontPoints.Comment + 1) })
$chooseColorButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.ColorDialog
    $dialog.FullOpen = $true
    $dialog.Color = Convert-HexToDrawingColor -Hex $script:accent
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $hex = '#{0:X2}{1:X2}{2:X2}' -f $dialog.Color.R, $dialog.Color.G, $dialog.Color.B
        Set-UiAccent -Accent $hex
    }
    $dialog.Dispose()
})
$resetColorButton.Add_Click({ Set-UiAccent -Accent '#EC4899' })
$applyAppearanceButton.Add_Click({ Save-UiAppearance })
$resetAppearanceButton.Add_Click({
    Set-FontEditorValues -Candidate 12 -Comment 9
    Save-UiAppearance
})
$configureAiButton.Add_Click({
    if (-not (Test-Path -LiteralPath $ConfigureDeepSeekPath)) { return }
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -StateRoot "{1}" -RimeUserDir "{2}"' -f $ConfigureDeepSeekPath, $StateRoot, $RimeUserDir
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden | Out-Null
})

Update-AccentResources
Set-FontEditorValues -Candidate $script:fontPoints.Candidate -Comment $script:fontPoints.Comment
Update-ResourceStatus
[void]$window.ShowDialog()

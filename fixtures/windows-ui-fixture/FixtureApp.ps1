param([ValidateSet('clean', 'defects')][string]$Mode = 'defects')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Set-Identity {
    param([System.Windows.Forms.Control]$Control, [string]$Name, [string]$AccessibleName = $Name)
    $Control.Name = $Name
    $Control.AccessibleName = $AccessibleName
    if ($Control -is [System.Windows.Forms.ButtonBase]) {
        $Control.AccessibleRole = [System.Windows.Forms.AccessibleRole]::PushButton
    }
    elseif ($Control -is [System.Windows.Forms.Label]) {
        $Control.AccessibleRole = [System.Windows.Forms.AccessibleRole]::StaticText
    }
    elseif ($Control -is [System.Windows.Forms.Panel]) {
        $Control.AccessibleRole = [System.Windows.Forms.AccessibleRole]::Grouping
    }
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'Mac-to-Windows Fixture'
$form.Name = 'FixtureMainWindow'
$form.AccessibleName = 'Mac-to-Windows Fixture'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = [System.Drawing.Size]::new(920, 620)
$form.MinimumSize = [System.Drawing.Size]::new(760, 520)
$form.Font = [System.Drawing.Font]::new('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 252)

$title = [System.Windows.Forms.Label]::new()
Set-Identity $title 'FixtureTitle' 'Fixture title'
$title.Text = if ($Mode -eq 'clean') { 'Precision Lab - clean control' } else { 'Precision Lab - intentional defects' }
$title.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 21)
$title.Location = [System.Drawing.Point]::new(36, 28)
$title.AutoSize = $true
$form.Controls.Add($title)

$subtitle = [System.Windows.Forms.Label]::new()
Set-Identity $subtitle 'FixtureSubtitle' 'Fixture subtitle'
$subtitle.Text = 'Each card has a stable UI Automation identity and reproducible geometry.'
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
$subtitle.Location = [System.Drawing.Point]::new(40, 76)
$subtitle.AutoSize = $true
$form.Controls.Add($subtitle)

$panel = [System.Windows.Forms.Panel]::new()
Set-Identity $panel 'FixtureContent' 'Fixture content'
$panel.Location = [System.Drawing.Point]::new(36, 120)
$panel.Size = [System.Drawing.Size]::new(848, 432)
$panel.BackColor = [System.Drawing.Color]::White
$panel.BorderStyle = 'FixedSingle'
$form.Controls.Add($panel)

function Add-CardLabel {
    param([string]$Text, [int]$X, [int]$Y)
    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.Location = [System.Drawing.Point]::new($X, $Y)
    $label.Size = [System.Drawing.Size]::new(370, 28)
    $label.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 11)
    $panel.Controls.Add($label)
}

Add-CardLabel 'A. Typography and geometry' 26 22
Add-CardLabel 'B. State and response' 438 22

$clipped = [System.Windows.Forms.Label]::new()
Set-Identity $clipped 'ClippedDescription' 'Complete deployment status description'
$clipped.Text = 'All Windows runner evidence has been captured successfully.'
$clipped.Location = [System.Drawing.Point]::new(28, 68)
$clipped.AutoEllipsis = $false
$clipped.BorderStyle = 'FixedSingle'
$clipped.Size = if ($Mode -eq 'clean') { [System.Drawing.Size]::new(365, 34) } else { [System.Drawing.Size]::new(150, 22) }
$panel.Controls.Add($clipped)

$leftButton = [System.Windows.Forms.Button]::new()
Set-Identity $leftButton 'PrimaryAction' 'Run validation'
$leftButton.Text = 'Run validation'
$leftButton.Location = [System.Drawing.Point]::new(28, 132)
$leftButton.Size = [System.Drawing.Size]::new(160, 42)
$panel.Controls.Add($leftButton)

$overlapButton = [System.Windows.Forms.Button]::new()
Set-Identity $overlapButton 'SecondaryAction' 'Open evidence'
$overlapButton.Text = 'Open evidence'
$overlapButton.Location = if ($Mode -eq 'clean') { [System.Drawing.Point]::new(208, 132) } else { [System.Drawing.Point]::new(150, 145) }
$overlapButton.Size = [System.Drawing.Size]::new(160, 42)
$panel.Controls.Add($overlapButton)

$offscreen = [System.Windows.Forms.Button]::new()
Set-Identity $offscreen 'OffscreenAction' 'Export report'
$offscreen.Text = 'Export report'
$offscreen.Location = if ($Mode -eq 'clean') { [System.Drawing.Point]::new(28, 206) } else { [System.Drawing.Point]::new(790, 206) }
$offscreen.Size = [System.Drawing.Size]::new(180, 42)
$panel.Controls.Add($offscreen)

$script:settingsWindow = $null
$settingsButton = [System.Windows.Forms.Button]::new()
Set-Identity $settingsButton 'SettingsAction' 'Open settings'
$settingsButton.Text = 'Open settings'
$settingsButton.Location = [System.Drawing.Point]::new(228, 206)
$settingsButton.Size = [System.Drawing.Size]::new(165, 42)
$settingsButton.Add_Click({
    if (-not $script:settingsWindow -or $script:settingsWindow.IsDisposed) {
        $script:settingsWindow = [System.Windows.Forms.Form]::new()
        $script:settingsWindow.Text = 'Fixture settings'
        $script:settingsWindow.Name = 'FixtureSettingsWindow'
        $script:settingsWindow.AccessibleName = 'Fixture settings'
        $script:settingsWindow.StartPosition = 'CenterParent'
        $script:settingsWindow.ClientSize = [System.Drawing.Size]::new(420, 210)
        $script:settingsWindow.Font = [System.Drawing.Font]::new('Segoe UI', 10)

        $settingsText = [System.Windows.Forms.Label]::new()
        Set-Identity $settingsText 'SettingsSummary' 'Settings summary'
        $settingsText.Text = 'Safe exploration opened this non-destructive window.'
        $settingsText.Location = [System.Drawing.Point]::new(32, 40)
        $settingsText.AutoSize = $true
        $script:settingsWindow.Controls.Add($settingsText)

        $closeSettings = [System.Windows.Forms.Button]::new()
        Set-Identity $closeSettings 'CloseSettings' 'Close settings'
        $closeSettings.Text = 'Close'
        $closeSettings.Location = [System.Drawing.Point]::new(276, 132)
        $closeSettings.Size = [System.Drawing.Size]::new(110, 38)
        $closeSettings.Add_Click({ $script:settingsWindow.Close() })
        $script:settingsWindow.Controls.Add($closeSettings)
        $script:settingsWindow.Show($form)
    }
    else {
        $script:settingsWindow.Activate()
    }
})
$panel.Controls.Add($settingsButton)

$disabled = [System.Windows.Forms.Button]::new()
Set-Identity $disabled 'ExpectedEnabledAction' 'Continue test'
$disabled.Text = 'Continue test'
$disabled.Location = [System.Drawing.Point]::new(440, 68)
$disabled.Size = [System.Drawing.Size]::new(170, 42)
$disabled.Enabled = $Mode -eq 'clean'
$panel.Controls.Add($disabled)

$response = [System.Windows.Forms.Label]::new()
Set-Identity $response 'ResponseStatus'
$response.AccessibleName = $null
$response.Text = 'Waiting'
$response.Location = [System.Drawing.Point]::new(440, 155)
$response.Size = [System.Drawing.Size]::new(280, 30)
$panel.Controls.Add($response)

$responseButton = [System.Windows.Forms.Button]::new()
Set-Identity $responseButton 'ResponseAction' 'Update status'
$responseButton.Text = 'Update status'
$responseButton.Location = [System.Drawing.Point]::new(440, 112)
$responseButton.Size = [System.Drawing.Size]::new(170, 38)
$responseButton.Add_Click({ if ($Mode -eq 'clean') { $response.Text = 'Completed' } })
$panel.Controls.Add($responseButton)

$blankPanel = [System.Windows.Forms.Panel]::new()
Set-Identity $blankPanel 'BlankRegion' 'Results region'
$blankPanel.Location = [System.Drawing.Point]::new(440, 210)
$blankPanel.Size = [System.Drawing.Size]::new(360, 150)
$blankPanel.BorderStyle = 'FixedSingle'
$blankPanel.BackColor = [System.Drawing.Color]::FromArgb(249, 250, 251)
$panel.Controls.Add($blankPanel)
if ($Mode -eq 'clean') {
    $ready = [System.Windows.Forms.Label]::new()
    Set-Identity $ready 'ContentReady' 'Content ready'
    $ready.Text = 'Evidence summary is ready.'
    $ready.Location = [System.Drawing.Point]::new(28, 34)
    $ready.AutoSize = $true
    $blankPanel.Controls.Add($ready)
}

$footer = [System.Windows.Forms.Label]::new()
Set-Identity $footer 'FixtureFooter' 'Fixture mode'
$footer.Text = "Fixture mode: $Mode"
$footer.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
$footer.Location = [System.Drawing.Point]::new(40, 570)
$footer.AutoSize = $true
$form.Controls.Add($footer)

[void]$form.ShowDialog()

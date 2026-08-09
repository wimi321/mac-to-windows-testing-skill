Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-M2WValue {
    param($Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
        return $Object[$Name]
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Initialize-M2WUiAutomation {
    if ($env:OS -ne 'Windows_NT') {
        throw 'Windows UI Automation is available only on Windows.'
    }
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if (-not ('M2W.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace M2W {
  public static class NativeMethods {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
    public const uint LEFTDOWN = 0x0002;
    public const uint LEFTUP = 0x0004;
  }
}
'@
    }
}

function Get-M2WCurrentSessionId {
    return [System.Diagnostics.Process]::GetCurrentProcess().SessionId
}

function Get-M2WSessionState {
    Initialize-M2WUiAutomation
    $sessionId = Get-M2WCurrentSessionId
    $logonUi = Get-Process -Name LogonUI -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sessionId } |
        Select-Object -First 1
    $interactive = [Environment]::UserInteractive
    $screens = @([System.Windows.Forms.Screen]::AllScreens)
    $blocked = (-not $interactive) -or [bool]$logonUi -or $screens.Count -eq 0
    return [pscustomobject]@{
        Interactive = $interactive
        Locked = [bool]$logonUi
        SessionId = $sessionId
        ScreenCount = $screens.Count
        Status = $(if ($blocked) { 'BLOCKED' } else { 'READY' })
        Blocker = $(if (-not $interactive) { 'BLOCKED_NON_INTERACTIVE_SESSION' }
            elseif ($logonUi) { 'BLOCKED_DESKTOP_LOCKED' }
            elseif ($screens.Count -eq 0) { 'BLOCKED_NO_DISPLAY' }
            else { $null })
    }
}

function Get-M2WEnvironment {
    Initialize-M2WUiAutomation
    $session = Get-M2WSessionState
    $screens = @([System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
        [pscustomobject]@{
            DeviceName = $_.DeviceName
            Primary = $_.Primary
            Bounds = [pscustomobject]@{ X = $_.Bounds.X; Y = $_.Bounds.Y; Width = $_.Bounds.Width; Height = $_.Bounds.Height }
            WorkingArea = [pscustomobject]@{ X = $_.WorkingArea.X; Y = $_.WorkingArea.Y; Width = $_.WorkingArea.Width; Height = $_.WorkingArea.Height }
        }
    })
    $video = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name
            DriverVersion = $_.DriverVersion
            AdapterRAM = $_.AdapterRAM
            Status = $_.Status
        }
    })
    $dpi = 96
    try {
        $graphics = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
        try { $dpi = [int][Math]::Round($graphics.DpiX) } finally { $graphics.Dispose() }
    }
    catch { }
    return [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        OsVersion = [Environment]::OSVersion.VersionString
        Architecture = $env:PROCESSOR_ARCHITECTURE
        PowerShell = $PSVersionTable.PSVersion.ToString()
        Dpi = $dpi
        ScalePercent = [int][Math]::Round(($dpi / 96.0) * 100)
        Session = $session
        Screens = $screens
        VideoControllers = $video
    }
}

function Get-M2WControlType {
    param([string]$Name)
    if (-not $Name) { return $null }
    switch ($Name.ToLowerInvariant()) {
        'button' { return [System.Windows.Automation.ControlType]::Button }
        'calendar' { return [System.Windows.Automation.ControlType]::Calendar }
        'checkbox' { return [System.Windows.Automation.ControlType]::CheckBox }
        'combobox' { return [System.Windows.Automation.ControlType]::ComboBox }
        'custom' { return [System.Windows.Automation.ControlType]::Custom }
        'datagrid' { return [System.Windows.Automation.ControlType]::DataGrid }
        'dataitem' { return [System.Windows.Automation.ControlType]::DataItem }
        'document' { return [System.Windows.Automation.ControlType]::Document }
        'edit' { return [System.Windows.Automation.ControlType]::Edit }
        'group' { return [System.Windows.Automation.ControlType]::Group }
        'header' { return [System.Windows.Automation.ControlType]::Header }
        'headeritem' { return [System.Windows.Automation.ControlType]::HeaderItem }
        'hyperlink' { return [System.Windows.Automation.ControlType]::Hyperlink }
        'image' { return [System.Windows.Automation.ControlType]::Image }
        'list' { return [System.Windows.Automation.ControlType]::List }
        'listitem' { return [System.Windows.Automation.ControlType]::ListItem }
        'menu' { return [System.Windows.Automation.ControlType]::Menu }
        'menubar' { return [System.Windows.Automation.ControlType]::MenuBar }
        'menuitem' { return [System.Windows.Automation.ControlType]::MenuItem }
        'pane' { return [System.Windows.Automation.ControlType]::Pane }
        'progressbar' { return [System.Windows.Automation.ControlType]::ProgressBar }
        'radiobutton' { return [System.Windows.Automation.ControlType]::RadioButton }
        'scrollbar' { return [System.Windows.Automation.ControlType]::ScrollBar }
        'slider' { return [System.Windows.Automation.ControlType]::Slider }
        'spinner' { return [System.Windows.Automation.ControlType]::Spinner }
        'splitbutton' { return [System.Windows.Automation.ControlType]::SplitButton }
        'statusbar' { return [System.Windows.Automation.ControlType]::StatusBar }
        'tab' { return [System.Windows.Automation.ControlType]::Tab }
        'tabitem' { return [System.Windows.Automation.ControlType]::TabItem }
        'table' { return [System.Windows.Automation.ControlType]::Table }
        'text' { return [System.Windows.Automation.ControlType]::Text }
        'thumb' { return [System.Windows.Automation.ControlType]::Thumb }
        'titlebar' { return [System.Windows.Automation.ControlType]::TitleBar }
        'toolbar' { return [System.Windows.Automation.ControlType]::ToolBar }
        'tree' { return [System.Windows.Automation.ControlType]::Tree }
        'treeitem' { return [System.Windows.Automation.ControlType]::TreeItem }
        'window' { return [System.Windows.Automation.ControlType]::Window }
        default { return $null }
    }
}

function New-M2WTargetCondition {
    param([Parameter(Mandatory)]$Target)
    $conditions = New-Object System.Collections.Generic.List[System.Windows.Automation.Condition]
    $name = Get-M2WValue -Object $Target -Name 'name'
    $automationId = Get-M2WValue -Object $Target -Name 'automationId'
    $controlTypeName = Get-M2WValue -Object $Target -Name 'controlType'
    if ($name) {
        $conditions.Add([System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::NameProperty,
            [string]$name
        ))
    }
    if ($automationId) {
        $conditions.Add([System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            [string]$automationId
        ))
    }
    if ($controlTypeName) {
        $controlType = Get-M2WControlType -Name ([string]$controlTypeName)
        if (-not $controlType) { throw "Unknown control type: $controlTypeName" }
        $conditions.Add([System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            $controlType
        ))
    }
    if ($conditions.Count -eq 0) { return [System.Windows.Automation.Condition]::TrueCondition }
    if ($conditions.Count -eq 1) { return $conditions[0] }
    return [System.Windows.Automation.AndCondition]::new($conditions.ToArray())
}

function Find-M2WElement {
    param(
        [Parameter(Mandatory)]$Target,
        [System.Windows.Automation.AutomationElement]$Root = [System.Windows.Automation.AutomationElement]::RootElement,
        [int]$TimeoutSeconds = 10
    )
    Initialize-M2WUiAutomation
    $condition = New-M2WTargetCondition -Target $Target
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            $element = $Root.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $condition)
            if ($element) { return $element }
        }
        catch { }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    return $null
}

function Convert-M2WElement {
    param([Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Element)
    try { $bounds = $Element.Current.BoundingRectangle } catch { $bounds = [System.Windows.Rect]::Empty }
    $name = ''; try { $name = $Element.Current.Name } catch { }
    $automationId = ''; try { $automationId = $Element.Current.AutomationId } catch { }
    $controlType = ''; try { $controlType = $Element.Current.ControlType.ProgrammaticName.Replace('ControlType.', '') } catch { }
    $className = ''; try { $className = $Element.Current.ClassName } catch { }
    $isEnabled = $false; try { $isEnabled = $Element.Current.IsEnabled } catch { }
    $isOffscreen = $true; try { $isOffscreen = $Element.Current.IsOffscreen } catch { }
    $isKeyboardFocusable = $false; try { $isKeyboardFocusable = $Element.Current.IsKeyboardFocusable } catch { }
    $hasKeyboardFocus = $false; try { $hasKeyboardFocus = $Element.Current.HasKeyboardFocus } catch { }
    $processId = 0; try { $processId = $Element.Current.ProcessId } catch { }
    return [pscustomobject]@{
        Name = $name
        AutomationId = $automationId
        ControlType = $controlType
        ClassName = $className
        IsEnabled = $isEnabled
        IsOffscreen = $isOffscreen
        IsKeyboardFocusable = $isKeyboardFocusable
        HasKeyboardFocus = $hasKeyboardFocus
        ProcessId = $processId
        Bounds = [pscustomobject]@{
            X = [int][Math]::Round($bounds.X)
            Y = [int][Math]::Round($bounds.Y)
            Width = [int][Math]::Round($bounds.Width)
            Height = [int][Math]::Round($bounds.Height)
        }
    }
}

function Export-M2WUiTree {
    param(
        [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Root,
        [Parameter(Mandatory)][string]$Path,
        [int]$Limit = 5000
    )
    Initialize-M2WUiAutomation
    $output = New-Object System.Collections.Generic.List[object]
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue([pscustomobject]@{ Element = $Root; Depth = 0; Parent = -1 })
    while ($queue.Count -gt 0 -and $output.Count -lt $Limit) {
        $entry = $queue.Dequeue()
        $index = $output.Count
        $converted = Convert-M2WElement -Element $entry.Element
        $converted | Add-Member -NotePropertyName Index -NotePropertyValue $index
        $converted | Add-Member -NotePropertyName Parent -NotePropertyValue $entry.Parent
        $converted | Add-Member -NotePropertyName Depth -NotePropertyValue $entry.Depth
        $output.Add($converted)
        try {
            $children = $entry.Element.FindAll(
                [System.Windows.Automation.TreeScope]::Children,
                [System.Windows.Automation.Condition]::TrueCondition
            )
            foreach ($child in $children) {
                $queue.Enqueue([pscustomobject]@{ Element = $child; Depth = $entry.Depth + 1; Parent = $index })
            }
        }
        catch { }
    }
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $output | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $output
}

function Export-M2WInteractionGraph {
    param(
        [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Root,
        [Parameter(Mandatory)][string]$Path,
        [int]$Limit = 5000
    )
    $treePath = [IO.Path]::ChangeExtension($Path, '.tree.json')
    $tree = @(Export-M2WUiTree -Root $Root -Path $treePath -Limit $Limit)
    $actionableTypes = @('Button', 'CheckBox', 'ComboBox', 'Edit', 'Hyperlink', 'ListItem', 'MenuItem', 'RadioButton', 'TabItem', 'TreeItem')
    $nodes = @($tree | Where-Object { $actionableTypes -contains $_.ControlType } | ForEach-Object {
        $target = [pscustomobject]@{ name = $_.Name; automationId = $_.AutomationId }
        $dangerous = Test-M2WDangerousTarget -Target $target
        [pscustomobject]@{
            Index = $_.Index
            Parent = $_.Parent
            Name = $_.Name
            AutomationId = $_.AutomationId
            ControlType = $_.ControlType
            Bounds = $_.Bounds
            Enabled = $_.IsEnabled
            Offscreen = $_.IsOffscreen
            KeyboardFocusable = $_.IsKeyboardFocusable
            Dangerous = $dangerous
            SuggestedAction = $(if ($dangerous) { 'skip' } elseif ($_.ControlType -eq 'Edit') { 'inspect' } else { 'invoke' })
        }
    })
    $graph = [pscustomobject]@{
        CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
        Root = Convert-M2WElement -Element $Root
        Nodes = $nodes
        DeniedDangerous = @($nodes | Where-Object Dangerous | Select-Object -ExpandProperty Index)
    }
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $graph | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
    Remove-Item -LiteralPath $treePath -Force -ErrorAction SilentlyContinue
    return $graph
}

function Save-M2WScreenshot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [System.Windows.Automation.AutomationElement]$Window,
        [switch]$FullScreen
    )
    Initialize-M2WUiAutomation
    if ($FullScreen -or -not $Window) {
        $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    }
    else {
        $rect = $Window.Current.BoundingRectangle
        $bounds = [System.Drawing.Rectangle]::FromLTRB(
            [int][Math]::Floor($rect.Left),
            [int][Math]::Floor($rect.Top),
            [int][Math]::Ceiling($rect.Right),
            [int][Math]::Ceiling($rect.Bottom)
        )
    }
    if ($bounds.Width -le 0 -or $bounds.Height -le 0) { throw 'Screenshot bounds are empty.' }
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
        }
        finally { $graphics.Dispose() }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $bitmap.Dispose() }
    return [pscustomobject]@{ Path = $Path; X = $bounds.X; Y = $bounds.Y; Width = $bounds.Width; Height = $bounds.Height }
}

function Invoke-M2WPhysicalClick {
    param([Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Element)
    $point = [System.Windows.Point]::new()
    if (-not $Element.TryGetClickablePoint([ref]$point)) {
        $bounds = $Element.Current.BoundingRectangle
        $point = [System.Windows.Point]::new($bounds.X + ($bounds.Width / 2), $bounds.Y + ($bounds.Height / 2))
    }
    [M2W.NativeMethods]::SetCursorPos([int]$point.X, [int]$point.Y) | Out-Null
    [M2W.NativeMethods]::mouse_event([M2W.NativeMethods]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    [M2W.NativeMethods]::mouse_event([M2W.NativeMethods]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
}

function Invoke-M2WElementClick {
    param([Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Element)
    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        ([System.Windows.Automation.InvokePattern]$pattern).Invoke()
        return
    }
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
        ([System.Windows.Automation.SelectionItemPattern]$pattern).Select()
        return
    }
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) {
        ([System.Windows.Automation.TogglePattern]$pattern).Toggle()
        return
    }
    Invoke-M2WPhysicalClick -Element $Element
}

function Test-M2WRectContained {
    param($Child, $Parent, [int]$Tolerance = 2)
    return $Child.Left -ge ($Parent.Left - $Tolerance) -and
        $Child.Top -ge ($Parent.Top - $Tolerance) -and
        $Child.Right -le ($Parent.Right + $Tolerance) -and
        $Child.Bottom -le ($Parent.Bottom + $Tolerance)
}

function Get-M2WRectOverlapArea {
    param($First, $Second)
    $width = [Math]::Max(0, [Math]::Min($First.Right, $Second.Right) - [Math]::Max($First.Left, $Second.Left))
    $height = [Math]::Max(0, [Math]::Min($First.Bottom, $Second.Bottom) - [Math]::Max($First.Top, $Second.Top))
    return [double]($width * $height)
}

function Get-M2WElementText {
    param([Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Element)
    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
        return [string]([System.Windows.Automation.ValuePattern]$pattern).Current.Value
    }
    return [string]$Element.Current.Name
}

function Test-M2WAssertion {
    param(
        [Parameter(Mandatory)]$Step,
        [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Window
    )
    $target = Get-M2WValue -Object $Step -Name 'target' -Default $Step
    $condition = [string](Get-M2WValue -Object $Step -Name 'condition' -Default 'exists')
    $element = Find-M2WElement -Target $target -Root $Window -TimeoutSeconds 5
    switch ($condition) {
        'exists' { return [pscustomobject]@{ Passed = [bool]$element; Detail = $(if ($element) { 'Element exists.' } else { 'Element not found.' }) } }
        'notExists' { return [pscustomobject]@{ Passed = -not $element; Detail = $(if ($element) { 'Unexpected element exists.' } else { 'Element is absent.' }) } }
        'enabled' { return [pscustomobject]@{ Passed = [bool]($element -and $element.Current.IsEnabled); Detail = 'Checked enabled state.' } }
        'focusable' { return [pscustomobject]@{ Passed = [bool]($element -and $element.Current.IsKeyboardFocusable); Detail = 'Checked keyboard focusability.' } }
        'focused' { return [pscustomobject]@{ Passed = [bool]($element -and $element.Current.HasKeyboardFocus); Detail = 'Checked keyboard focus.' } }
        'visible' { return [pscustomobject]@{ Passed = [bool]($element -and -not $element.Current.IsOffscreen); Detail = 'Checked visible state.' } }
        'textEquals' {
            $expected = [string](Get-M2WValue -Object $Step -Name 'value' -Default '')
            $actual = if ($element) { Get-M2WElementText -Element $element } else { '' }
            return [pscustomobject]@{ Passed = [bool]($element -and $actual -eq $expected); Detail = "Expected '$expected'; received '$actual'." }
        }
        'withinWindow' {
            $passed = [bool]($element -and (Test-M2WRectContained -Child $element.Current.BoundingRectangle -Parent $Window.Current.BoundingRectangle))
            return [pscustomobject]@{ Passed = $passed; Detail = 'Checked element bounds against owning window.' }
        }
        'noOverlap' {
            $otherTarget = Get-M2WValue -Object $Step -Name 'otherTarget'
            if (-not $otherTarget) { throw 'noOverlap requires otherTarget.' }
            $other = Find-M2WElement -Target $otherTarget -Root $Window -TimeoutSeconds 5
            $tolerance = [double](Get-M2WValue -Object $Step -Name 'tolerancePixels' -Default 2)
            $area = if ($element -and $other) { Get-M2WRectOverlapArea -First $element.Current.BoundingRectangle -Second $other.Current.BoundingRectangle } else { -1 }
            return [pscustomobject]@{ Passed = [bool]($element -and $other -and $area -le ($tolerance * $tolerance)); Detail = "Overlap area: $area pixel(s)." }
        }
        default { throw "Unknown assertion condition: $condition" }
    }
}

function Test-M2WDangerousTarget {
    param($Target)
    $text = @(
        (Get-M2WValue -Object $Target -Name 'name'),
        (Get-M2WValue -Object $Target -Name 'automationId')
    ) -join ' '
    return $text -match '(?i)delete|remove|uninstall|publish|release|purchase|payment|pay now|factory reset|drop database|清空|删除|卸载|发布|付款|购买|重置'
}

function Invoke-M2WStep {
    param(
        [Parameter(Mandatory)]$Step,
        [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Window,
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$ScenarioId,
        [Parameter(Mandatory)][int]$Index,
        [switch]$AllowDestructiveActions
    )
    $action = [string](Get-M2WValue -Object $Step -Name 'action')
    $checkpoint = Get-M2WValue -Object $Step -Name 'checkpoint'
    $prefix = '{0:D2}-{1}' -f $Index, (($checkpoint, $action) | Where-Object { $_ } | Select-Object -First 1)
    switch ($action) {
        'wait' {
            $seconds = [double](Get-M2WValue -Object $Step -Name 'seconds' -Default 1)
            Start-Sleep -Milliseconds ([int]($seconds * 1000))
            return [pscustomobject]@{ Status = 'PASS'; Action = $action; Summary = "Waited $seconds second(s)." }
        }
        'screenshot' {
            $shot = Join-Path $RunDirectory "screenshots\$ScenarioId-$prefix.png"
            $tree = Join-Path $RunDirectory "ui-trees\$ScenarioId-$prefix.json"
            Save-M2WScreenshot -Path $shot -Window $Window | Out-Null
            Export-M2WUiTree -Path $tree -Root $Window | Out-Null
            return [pscustomobject]@{ Status = 'PASS'; Action = $action; Screenshot = $shot; UiTree = $tree; Summary = 'Captured native evidence.' }
        }
        'discover' {
            $graphPath = Join-Path $RunDirectory "interaction-graphs\$ScenarioId-$prefix.json"
            $graph = Export-M2WInteractionGraph -Root $Window -Path $graphPath
            return [pscustomobject]@{
                Status = 'PASS'
                Action = $action
                InteractionGraph = $graphPath
                DiscoveredControls = @($graph.Nodes).Count
                Summary = 'Discovered actionable controls without invoking unknown targets.'
            }
        }
        'assert' {
            $assertion = Test-M2WAssertion -Step $Step -Window $Window
            return [pscustomobject]@{ Status = $(if ($assertion.Passed) { 'PASS' } else { 'FAIL' }); Action = $action; Summary = $assertion.Detail }
        }
        'click' {
            $target = Get-M2WValue -Object $Step -Name 'target'
            if ((Test-M2WDangerousTarget -Target $target) -and -not $AllowDestructiveActions) {
                return [pscustomobject]@{ Status = 'BLOCKED'; Action = $action; Summary = 'Dangerous target denied by profile policy.'; Blocker = 'BLOCKED_DANGEROUS_ACTION' }
            }
            $element = Find-M2WElement -Target $target -Root $Window -TimeoutSeconds 10
            if (-not $element) { return [pscustomobject]@{ Status = 'FAIL'; Action = $action; Summary = 'Click target not found.' } }
            Invoke-M2WElementClick -Element $element
            Start-Sleep -Milliseconds 350
            return [pscustomobject]@{ Status = 'PASS'; Action = $action; Summary = 'Invoked target.' }
        }
        'type' {
            $target = Get-M2WValue -Object $Step -Name 'target'
            $element = Find-M2WElement -Target $target -Root $Window -TimeoutSeconds 10
            if (-not $element) { return [pscustomobject]@{ Status = 'FAIL'; Action = $action; Summary = 'Text target not found.' } }
            $text = [string](Get-M2WValue -Object $Step -Name 'text' -Default '')
            $pattern = $null
            if ($element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern) -and -not ([System.Windows.Automation.ValuePattern]$pattern).Current.IsReadOnly) {
                ([System.Windows.Automation.ValuePattern]$pattern).SetValue($text)
            }
            else {
                $element.SetFocus()
                [System.Windows.Forms.SendKeys]::SendWait('^a')
                $escaped = $text.Replace('{', '{{}').Replace('}', '{}}').Replace('+', '{+}').Replace('^', '{^}').Replace('%', '{%}').Replace('~', '{~}')
                [System.Windows.Forms.SendKeys]::SendWait($escaped)
            }
            return [pscustomobject]@{ Status = 'PASS'; Action = $action; Summary = 'Entered text.' }
        }
        'shortcut' {
            $Window.SetFocus()
            [System.Windows.Forms.SendKeys]::SendWait([string](Get-M2WValue -Object $Step -Name 'keys' -Default ''))
            Start-Sleep -Milliseconds 250
            return [pscustomobject]@{ Status = 'PASS'; Action = $action; Summary = 'Sent keyboard shortcut.' }
        }
        'close' {
            $pattern = $null
            if ($Window.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$pattern)) {
                ([System.Windows.Automation.WindowPattern]$pattern).Close()
            }
            else {
                $Window.SetFocus(); [System.Windows.Forms.SendKeys]::SendWait('%{F4}')
            }
            return [pscustomobject]@{ Status = 'PASS'; Action = $action; Summary = 'Closed window.' }
        }
        default { return [pscustomobject]@{ Status = 'BLOCKED'; Action = $action; Summary = "Unsupported action: $action"; Blocker = 'BLOCKED_UNSUPPORTED_ACTION' } }
    }
}

Export-ModuleMember -Function @(
    'Initialize-M2WUiAutomation',
    'Get-M2WValue',
    'Get-M2WSessionState',
    'Get-M2WEnvironment',
    'Find-M2WElement',
    'Convert-M2WElement',
    'Export-M2WUiTree',
    'Export-M2WInteractionGraph',
    'Save-M2WScreenshot',
    'Invoke-M2WStep',
    'Test-M2WAssertion',
    'Test-M2WDangerousTarget',
    'Test-M2WRectContained',
    'Get-M2WRectOverlapArea',
    'Get-M2WControlType'
)

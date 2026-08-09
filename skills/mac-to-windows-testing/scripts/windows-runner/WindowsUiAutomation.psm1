Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'JavaAccessBridge.psm1') -Force

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

function Get-M2WRootNativeHandle {
    param([Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Root)
    try { return [IntPtr]([int64]$Root.Current.NativeWindowHandle) } catch { return [IntPtr]::Zero }
}

function Get-M2WRootProcessId {
    param([Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Root)
    try { return [int]$Root.Current.ProcessId } catch { return 0 }
}

function Test-M2WJavaUiRoot {
    param([Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Root)
    $className = ''
    try { $className = [string]$Root.Current.ClassName } catch { }
    return $className -match '^(?:SunAwt|javax\.swing|java\.awt)'
}

function Initialize-M2WUiAutomation {
    if ($env:OS -ne 'Windows_NT') {
        throw 'Windows UI Automation is available only on Windows.'
    }
    Add-Type -AssemblyName WindowsBase
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
    $accessibilityProperties = Join-Path $HOME '.accessibility.properties'
    $javaAccessBridgeCandidates = @(Get-M2WJavaAccessBridgeCandidates)
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
        JavaAccessBridge = [pscustomobject]@{
            UserConfigurationPresent = Test-Path -LiteralPath $accessibilityProperties -PathType Leaf
            DllAvailable = $javaAccessBridgeCandidates.Count -gt 0
            DllCandidates = @($javaAccessBridgeCandidates | ForEach-Object { Split-Path -Leaf $_ })
        }
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

function Test-M2WTargetName {
    param([string]$ActualName, [Parameter(Mandatory)]$Target)
    $contains = Get-M2WValue -Object $Target -Name 'nameContains'
    $pattern = Get-M2WValue -Object $Target -Name 'nameRegex'
    if ($contains -and $ActualName.IndexOf([string]$contains, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        return $false
    }
    if ($pattern) {
        try {
            if (-not [regex]::IsMatch($ActualName, [string]$pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                return $false
            }
        }
        catch {
            throw "Invalid target nameRegex '$pattern': $($_.Exception.Message)"
        }
    }
    return $true
}

function Find-M2WElement {
    param(
        [Parameter(Mandatory)]$Target,
        [System.Windows.Automation.AutomationElement]$Root = [System.Windows.Automation.AutomationElement]::RootElement,
        [int]$TimeoutSeconds = 10
    )
    Initialize-M2WUiAutomation
    $condition = New-M2WTargetCondition -Target $Target
    $requiresNameFilter = [bool](
        (Get-M2WValue -Object $Target -Name 'nameContains') -or
        (Get-M2WValue -Object $Target -Name 'nameRegex')
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            if (-not $requiresNameFilter) {
                $element = $Root.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $condition)
                if ($element) { return $element }
            }
            else {
                $elements = $Root.FindAll([System.Windows.Automation.TreeScope]::Subtree, $condition)
                foreach ($element in $elements) {
                    $actualName = ''; try { $actualName = [string]$element.Current.Name } catch { }
                    if (Test-M2WTargetName -ActualName $actualName -Target $Target) { return $element }
                }
            }
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

function Convert-M2WJavaNode {
    param([Parameter(Mandatory)]$Node)
    return [pscustomobject]@{
        Provider = 'JavaAccessBridge'
        Name = [string]$Node.Name
        Description = [string]$Node.Description
        AutomationId = ''
        ControlType = [string]$Node.ControlType
        ClassName = [string]$Node.Role
        Role = [string]$Node.Role
        LocalizedRole = [string]$Node.LocalizedRole
        States = [string]$Node.States
        LocalizedStates = [string]$Node.LocalizedStates
        IsEnabled = [bool]$Node.Enabled
        IsOffscreen = [bool]$Node.Offscreen
        IsKeyboardFocusable = [bool]$Node.KeyboardFocusable
        HasKeyboardFocus = [bool]$Node.HasKeyboardFocus
        Actionable = [bool]$Node.Actionable
        Index = [int]$Node.Index
        Parent = [int]$Node.Parent
        Depth = [int]$Node.Depth
        Bounds = [pscustomobject]@{
            X = [int]$Node.X
            Y = [int]$Node.Y
            Width = [int]$Node.Width
            Height = [int]$Node.Height
        }
    }
}

function Export-M2WAccessibleTrees {
    param(
        [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Root,
        [Parameter(Mandatory)][string]$UiAutomationPath,
        [int]$Limit = 5000
    )
    $uiNodes = @(Export-M2WUiTree -Root $Root -Path $UiAutomationPath -Limit $Limit)
    $javaPath = $UiAutomationPath -replace '\.json$', '.java.json'
    $handle = Get-M2WRootNativeHandle -Root $Root
    $processId = Get-M2WRootProcessId -Root $Root
    $javaSnapshot = $null
    if ($handle -ne [IntPtr]::Zero) {
        $javaSnapshot = Export-M2WJavaAccessibilityTree -WindowHandle $handle -ProcessId $processId -Path $javaPath -Limit $Limit
    }
    if (-not $javaSnapshot) {
        $javaSnapshot = [pscustomobject]@{ Status = 'BLOCKED'; Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_UNAVAILABLE'; Detail = 'No native window handle was available.'; Nodes = @() }
        $javaSnapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $javaPath -Encoding UTF8
    }
    return [pscustomobject]@{
        UiAutomationPath = $UiAutomationPath
        UiAutomationNodes = $uiNodes
        JavaAccessBridgePath = $javaPath
        JavaAccessBridge = $javaSnapshot
    }
}

function Test-M2WJavaNodeTarget {
    param([Parameter(Mandatory)]$Node, [Parameter(Mandatory)]$Target)
    $automationId = Get-M2WValue -Object $Target -Name 'automationId'
    if ($automationId) { return $false }
    $includeOffscreen = [bool](Get-M2WValue -Object $Target -Name 'includeOffscreen' -Default $false)
    if (-not $includeOffscreen -and ($Node.Offscreen -or $Node.Width -le 0 -or $Node.Height -le 0)) { return $false }
    $expectedName = Get-M2WValue -Object $Target -Name 'name'
    if ($null -ne $expectedName -and [string]$Node.Name -ne [string]$expectedName) { return $false }
    $contains = Get-M2WValue -Object $Target -Name 'nameContains'
    if ($contains -and ([string]$Node.Name).IndexOf([string]$contains, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
    $pattern = Get-M2WValue -Object $Target -Name 'nameRegex'
    if ($pattern -and -not [regex]::IsMatch([string]$Node.Name, [string]$pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) { return $false }
    $controlType = Get-M2WValue -Object $Target -Name 'controlType'
    if ($controlType -and [string]$Node.ControlType -ne [string]$controlType) { return $false }
    return $true
}

function Find-M2WJavaElement {
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Root,
        [int]$TimeoutSeconds = 10
    )
    $handle = Get-M2WRootNativeHandle -Root $Root
    if ($handle -eq [IntPtr]::Zero) { return $null }
    $processId = Get-M2WRootProcessId -Root $Root
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $snapshot = Get-M2WJavaAccessibilitySnapshot -WindowHandle $handle -ProcessId $processId
        if ($snapshot.Status -eq 'READY') {
            foreach ($node in @($snapshot.Nodes)) {
                if (Test-M2WJavaNodeTarget -Node $node -Target $Target) { return $node }
            }
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    return $null
}

function Find-M2WUnifiedElement {
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Root,
        [int]$TimeoutSeconds = 10
    )
    $uiaTimeout = if (Test-M2WJavaUiRoot -Root $Root) { [Math]::Min(1, $TimeoutSeconds) } else { $TimeoutSeconds }
    $element = Find-M2WElement -Target $Target -Root $Root -TimeoutSeconds $uiaTimeout
    if ($element) {
        return [pscustomobject]@{ Provider = 'UIAutomation'; Element = $element; Node = $null }
    }
    $node = Find-M2WJavaElement -Target $Target -Root $Root -TimeoutSeconds $TimeoutSeconds
    if ($node) {
        return [pscustomobject]@{ Provider = 'JavaAccessBridge'; Element = $null; Node = $node }
    }
    return $null
}

function Get-M2WUnifiedBounds {
    param([Parameter(Mandatory)]$Match)
    if ($Match.Provider -eq 'UIAutomation') { return $Match.Element.Current.BoundingRectangle }
    return [System.Windows.Rect]::new([double]$Match.Node.X, [double]$Match.Node.Y, [double]$Match.Node.Width, [double]$Match.Node.Height)
}

function Get-M2WUnifiedText {
    param([Parameter(Mandatory)]$Match)
    if ($Match.Provider -eq 'UIAutomation') { return Get-M2WElementText -Element $Match.Element }
    return [string]$Match.Node.Name
}

function Invoke-M2WPointClick {
    param([Parameter(Mandatory)][double]$X, [Parameter(Mandatory)][double]$Y)
    [M2W.NativeMethods]::SetCursorPos([int][Math]::Round($X), [int][Math]::Round($Y)) | Out-Null
    [M2W.NativeMethods]::mouse_event([M2W.NativeMethods]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    [M2W.NativeMethods]::mouse_event([M2W.NativeMethods]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
}

function Invoke-M2WUnifiedClick {
    param([Parameter(Mandatory)]$Match)
    if ($Match.Provider -eq 'UIAutomation') {
        Invoke-M2WElementClick -Element $Match.Element
        return
    }
    $bounds = Get-M2WUnifiedBounds -Match $Match
    if ($bounds.Width -le 0 -or $bounds.Height -le 0 -or $Match.Node.Offscreen) {
        throw 'Java accessible target does not have visible clickable bounds.'
    }
    Invoke-M2WPointClick -X ($bounds.X + ($bounds.Width / 2)) -Y ($bounds.Y + ($bounds.Height / 2))
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
    $evidence = Export-M2WAccessibleTrees -Root $Root -UiAutomationPath $treePath -Limit $Limit
    $tree = @($evidence.UiAutomationNodes)
    $actionableTypes = @('Button', 'CheckBox', 'ComboBox', 'Edit', 'Hyperlink', 'ListItem', 'MenuItem', 'RadioButton', 'TabItem', 'TreeItem')
    $uiNodes = @($tree | Where-Object { $actionableTypes -contains $_.ControlType } | ForEach-Object {
        $target = [pscustomobject]@{ name = $_.Name; automationId = $_.AutomationId }
        $dangerous = Test-M2WDangerousTarget -Target $target
        [pscustomobject]@{
            Id = "uia:$($_.Index)"
            Provider = 'UIAutomation'
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
    $javaNodes = @($evidence.JavaAccessBridge.Nodes | Where-Object {
        $_.Actionable -or $actionableTypes -contains $_.ControlType
    } | ForEach-Object {
        $target = [pscustomobject]@{ name = $_.Name; automationId = '' }
        $dangerous = Test-M2WDangerousTarget -Target $target
        [pscustomobject]@{
            Id = "jab:$($_.Index)"
            Provider = 'JavaAccessBridge'
            Index = $_.Index
            Parent = $_.Parent
            Name = $_.Name
            Description = $_.Description
            AutomationId = ''
            ControlType = $_.ControlType
            Role = $_.Role
            Bounds = [pscustomobject]@{ X = $_.X; Y = $_.Y; Width = $_.Width; Height = $_.Height }
            Enabled = $_.Enabled
            Offscreen = $_.Offscreen
            KeyboardFocusable = $_.KeyboardFocusable
            Dangerous = $dangerous
            SuggestedAction = $(if ($dangerous) { 'skip' } elseif ($_.ControlType -eq 'Edit') { 'inspect' } else { 'invoke' })
        }
    })
    $nodes = @($uiNodes) + @($javaNodes)
    $javaRoot = Test-M2WJavaUiRoot -Root $Root
    $blocker = $null
    if ($javaRoot -and @($javaNodes).Count -eq 0) {
        $blocker = if ($evidence.JavaAccessBridge.Blocker) { [string]$evidence.JavaAccessBridge.Blocker } else { 'BLOCKED_JAVA_ACCESS_BRIDGE_UNAVAILABLE' }
    }
    elseif (@($nodes).Count -eq 0) {
        $blocker = 'BLOCKED_INTERACTION_GRAPH_EMPTY'
    }
    $graph = [pscustomobject]@{
        CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
        Status = $(if ($blocker) { 'BLOCKED' } else { 'READY' })
        Blocker = $blocker
        Root = Convert-M2WElement -Element $Root
        Nodes = $nodes
        Providers = [pscustomobject]@{
            UIAutomation = [pscustomobject]@{ Tree = $evidence.UiAutomationPath; Nodes = @($tree).Count; Actionable = @($uiNodes).Count }
            JavaAccessBridge = [pscustomobject]@{
                Tree = $evidence.JavaAccessBridgePath
                Status = $evidence.JavaAccessBridge.Status
                Blocker = $evidence.JavaAccessBridge.Blocker
                Detail = $evidence.JavaAccessBridge.Detail
                Nodes = @($evidence.JavaAccessBridge.Nodes).Count
                Actionable = @($javaNodes).Count
            }
        }
        DeniedDangerous = @($nodes | Where-Object Dangerous | Select-Object -ExpandProperty Id)
    }
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $graph | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
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
    $point = [System.Windows.Point]::new(0, 0)
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
    $match = Find-M2WUnifiedElement -Target $target -Root $Window -TimeoutSeconds 5
    switch ($condition) {
        'exists' { return [pscustomobject]@{ Passed = [bool]$match; Detail = $(if ($match) { "Element exists through $($match.Provider)." } else { 'Element not found.' }) } }
        'notExists' { return [pscustomobject]@{ Passed = -not $match; Detail = $(if ($match) { 'Unexpected element exists.' } else { 'Element is absent.' }) } }
        'enabled' {
            $enabled = [bool]($match -and $(if ($match.Provider -eq 'UIAutomation') { $match.Element.Current.IsEnabled } else { $match.Node.Enabled }))
            return [pscustomobject]@{ Passed = $enabled; Detail = 'Checked enabled state.' }
        }
        'focusable' {
            $focusable = [bool]($match -and $(if ($match.Provider -eq 'UIAutomation') { $match.Element.Current.IsKeyboardFocusable } else { $match.Node.KeyboardFocusable }))
            return [pscustomobject]@{ Passed = $focusable; Detail = 'Checked keyboard focusability.' }
        }
        'focused' {
            $focused = [bool]($match -and $(if ($match.Provider -eq 'UIAutomation') { $match.Element.Current.HasKeyboardFocus } else { $match.Node.HasKeyboardFocus }))
            return [pscustomobject]@{ Passed = $focused; Detail = 'Checked keyboard focus.' }
        }
        'visible' {
            $visible = [bool]($match -and -not $(if ($match.Provider -eq 'UIAutomation') { $match.Element.Current.IsOffscreen } else { $match.Node.Offscreen }))
            return [pscustomobject]@{ Passed = $visible; Detail = 'Checked visible state.' }
        }
        'textEquals' {
            $expected = [string](Get-M2WValue -Object $Step -Name 'value' -Default '')
            $actual = if ($match) { Get-M2WUnifiedText -Match $match } else { '' }
            return [pscustomobject]@{ Passed = [bool]($match -and $actual -eq $expected); Detail = "Expected '$expected'; received '$actual'." }
        }
        'withinWindow' {
            $passed = [bool]($match -and (Test-M2WRectContained -Child (Get-M2WUnifiedBounds -Match $match) -Parent $Window.Current.BoundingRectangle))
            return [pscustomobject]@{ Passed = $passed; Detail = 'Checked element bounds against owning window.' }
        }
        'noOverlap' {
            $otherTarget = Get-M2WValue -Object $Step -Name 'otherTarget'
            if (-not $otherTarget) { throw 'noOverlap requires otherTarget.' }
            $other = Find-M2WUnifiedElement -Target $otherTarget -Root $Window -TimeoutSeconds 5
            if (-not $match -or -not $other) {
                return [pscustomobject]@{ Passed = $false; Detail = 'One or both overlap targets were not found.' }
            }
            $tolerance = [double](Get-M2WValue -Object $Step -Name 'tolerancePixels' -Default 2)
            $area = Get-M2WRectOverlapArea -First (Get-M2WUnifiedBounds -Match $match) -Second (Get-M2WUnifiedBounds -Match $other)
            return [pscustomobject]@{ Passed = [bool]($area -le ($tolerance * $tolerance)); Detail = "Overlap area: $area pixel(s)." }
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
    # Keep the module ASCII-only so Windows PowerShell 5.1 parses it identically on every locale.
    return $text -match '(?i)delete|remove|uninstall|publish|release|purchase|payment|pay now|factory reset|drop database|\u6e05\u7a7a|\u5220\u9664|\u5378\u8f7d|\u53d1\u5e03|\u4ed8\u6b3e|\u8d2d\u4e70|\u91cd\u7f6e'
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
            $trees = Export-M2WAccessibleTrees -Root $Window -UiAutomationPath $tree
            return [pscustomobject]@{
                Status = 'PASS'
                Action = $action
                Screenshot = $shot
                UiTree = $tree
                JavaUiTree = $trees.JavaAccessBridgePath
                Summary = 'Captured native screenshot, UI Automation, and Java accessibility evidence.'
            }
        }
        'discover' {
            $graphPath = Join-Path $RunDirectory "interaction-graphs\$ScenarioId-$prefix.json"
            $graph = Export-M2WInteractionGraph -Root $Window -Path $graphPath
            return [pscustomobject]@{
                Status = $(if ($graph.Status -eq 'READY') { 'PASS' } else { 'BLOCKED' })
                Action = $action
                InteractionGraph = $graphPath
                DiscoveredControls = @($graph.Nodes).Count
                Blocker = $graph.Blocker
                Summary = $(if ($graph.Status -eq 'READY') { 'Discovered actionable controls without invoking unknown targets.' } else { "Interaction graph is incomplete: $($graph.Blocker)" })
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
            $match = Find-M2WUnifiedElement -Target $target -Root $Window -TimeoutSeconds 10
            if (-not $match) { return [pscustomobject]@{ Status = 'FAIL'; Action = $action; Summary = 'Click target not found.' } }
            Invoke-M2WUnifiedClick -Match $match
            Start-Sleep -Milliseconds 350
            return [pscustomobject]@{ Status = 'PASS'; Action = $action; Summary = "Invoked target through $($match.Provider)." }
        }
        'type' {
            $target = Get-M2WValue -Object $Step -Name 'target'
            $match = Find-M2WUnifiedElement -Target $target -Root $Window -TimeoutSeconds 10
            if (-not $match) { return [pscustomobject]@{ Status = 'FAIL'; Action = $action; Summary = 'Text target not found.' } }
            $text = [string](Get-M2WValue -Object $Step -Name 'text' -Default '')
            $pattern = $null
            if ($match.Provider -eq 'UIAutomation' -and $match.Element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern) -and -not ([System.Windows.Automation.ValuePattern]$pattern).Current.IsReadOnly) {
                ([System.Windows.Automation.ValuePattern]$pattern).SetValue($text)
            }
            else {
                if ($match.Provider -eq 'UIAutomation') { $match.Element.SetFocus() } else { Invoke-M2WUnifiedClick -Match $match }
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
    'Test-M2WTargetName',
    'Find-M2WElement',
    'Convert-M2WElement',
    'Export-M2WUiTree',
    'Export-M2WAccessibleTrees',
    'Export-M2WInteractionGraph',
    'Save-M2WScreenshot',
    'Find-M2WUnifiedElement',
    'Find-M2WJavaElement',
    'Invoke-M2WStep',
    'Test-M2WAssertion',
    'Test-M2WDangerousTarget',
    'Test-M2WRectContained',
    'Get-M2WRectOverlapArea',
    'Get-M2WControlType'
)

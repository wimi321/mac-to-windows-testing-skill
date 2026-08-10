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
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint attach, uint attachTo, bool value);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr SetFocus(IntPtr window);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    public const uint LEFTDOWN = 0x0002;
    public const uint LEFTUP = 0x0004;
    public const int SW_RESTORE = 9;

    public static bool ActivateWindow(IntPtr window) {
      if (window == IntPtr.Zero) { return false; }
      IntPtr foreground = GetForegroundWindow();
      uint ignored;
      uint currentThread = GetCurrentThreadId();
      uint foregroundThread = foreground == IntPtr.Zero ? 0 : GetWindowThreadProcessId(foreground, out ignored);
      uint targetThread = GetWindowThreadProcessId(window, out ignored);
      bool attachedForeground = false;
      bool attachedTarget = false;
      try {
        if (foregroundThread != 0 && foregroundThread != currentThread) {
          attachedForeground = AttachThreadInput(currentThread, foregroundThread, true);
        }
        if (targetThread != 0 && targetThread != currentThread && targetThread != foregroundThread) {
          attachedTarget = AttachThreadInput(currentThread, targetThread, true);
        }
        ShowWindowAsync(window, SW_RESTORE);
        BringWindowToTop(window);
        bool activated = SetForegroundWindow(window);
        SetFocus(window);
        return activated || GetForegroundWindow() == window;
      }
      finally {
        if (attachedTarget) { AttachThreadInput(currentThread, targetThread, false); }
        if (attachedForeground) { AttachThreadInput(currentThread, foregroundThread, false); }
      }
    }
  }
}
'@
    }
    if (-not ('M2W.WindowActivationV1' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace M2W {
  // Versioned separately so an already-running worker can load activation fixes after an update.
  public static class WindowActivationV1 {
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint attach, uint attachTo, bool value);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr SetFocus(IntPtr window);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();

    public static bool ActivateWindow(IntPtr window) {
      if (window == IntPtr.Zero) { return false; }
      IntPtr foreground = GetForegroundWindow();
      uint ignored;
      uint currentThread = GetCurrentThreadId();
      uint foregroundThread = foreground == IntPtr.Zero ? 0 : GetWindowThreadProcessId(foreground, out ignored);
      uint targetThread = GetWindowThreadProcessId(window, out ignored);
      bool attachedForeground = false;
      bool attachedTarget = false;
      try {
        if (foregroundThread != 0 && foregroundThread != currentThread) {
          attachedForeground = AttachThreadInput(currentThread, foregroundThread, true);
        }
        if (targetThread != 0 && targetThread != currentThread && targetThread != foregroundThread) {
          attachedTarget = AttachThreadInput(currentThread, targetThread, true);
        }
        ShowWindowAsync(window, 9);
        BringWindowToTop(window);
        bool activated = SetForegroundWindow(window);
        SetFocus(window);
        return activated || GetForegroundWindow() == window;
      }
      finally {
        if (attachedTarget) { AttachThreadInput(currentThread, targetThread, false); }
        if (attachedForeground) { AttachThreadInput(currentThread, foregroundThread, false); }
      }
    }
  }
}
'@
    }
    if (-not ('M2W.WindowEnumerationV1' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
namespace M2W {
  public sealed class NativeWindowInfoV1 {
    public long Handle { get; set; }
    public int ProcessId { get; set; }
    public string Title { get; set; }
    public string ClassName { get; set; }
    public int X { get; set; }
    public int Y { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
  }

  public static class WindowEnumerationV1 {
    private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);
    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int maximum);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLength(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder className, int maximum);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out RECT rectangle);

    public static NativeWindowInfoV1[] GetVisibleWindows(int requestedProcessId) {
      List<NativeWindowInfoV1> windows = new List<NativeWindowInfoV1>();
      EnumWindows(delegate(IntPtr window, IntPtr ignored) {
        if (!IsWindowVisible(window)) { return true; }
        uint processId;
        GetWindowThreadProcessId(window, out processId);
        if (requestedProcessId > 0 && processId != (uint)requestedProcessId) { return true; }
        RECT rectangle;
        if (!GetWindowRect(window, out rectangle)) { return true; }
        int width = rectangle.Right - rectangle.Left;
        int height = rectangle.Bottom - rectangle.Top;
        if (width <= 0 || height <= 0) { return true; }

        int titleLength = Math.Max(0, GetWindowTextLength(window));
        StringBuilder title = new StringBuilder(titleLength + 1);
        GetWindowText(window, title, title.Capacity);
        StringBuilder className = new StringBuilder(256);
        GetClassName(window, className, className.Capacity);
        windows.Add(new NativeWindowInfoV1 {
          Handle = window.ToInt64(),
          ProcessId = (int)processId,
          Title = title.ToString(),
          ClassName = className.ToString(),
          X = rectangle.Left,
          Y = rectangle.Top,
          Width = width,
          Height = height
        });
        return true;
      }, IntPtr.Zero);
      return windows.ToArray();
    }
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

function Test-M2WTopLevelWindowCandidate {
    param(
        [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Element,
        [Parameter(Mandatory)]$Target
    )
    try {
        $name = [string]$Element.Current.Name
        $className = [string]$Element.Current.ClassName
        $controlType = [string]$Element.Current.ControlType.ProgrammaticName.Replace('ControlType.', '')
        $bounds = $Element.Current.BoundingRectangle
        if ($Element.Current.IsOffscreen -or $bounds.Width -le 0 -or $bounds.Height -le 0) { return $false }
    }
    catch { return $false }

    $expectedName = Get-M2WValue -Object $Target -Name 'name'
    if ($null -ne $expectedName -and $name -ne [string]$expectedName) { return $false }
    if (-not (Test-M2WTargetName -ActualName $name -Target $Target)) { return $false }

    $requestedType = [string](Get-M2WValue -Object $Target -Name 'controlType' -Default 'Window')
    if ($requestedType -and $requestedType -ne 'Window' -and $controlType -ne $requestedType) { return $false }
    if ($requestedType -eq 'Window') {
        $isSwingTopLevel = $className -match '^(?:SunAwt|javax\.swing|java\.awt).*(?:Frame|Dialog|Window)'
        if ($controlType -ne 'Window' -and -not $isSwingTopLevel) { return $false }
    }
    return $true
}

function Test-M2WNativeWindowCandidate {
    param(
        [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)]$Target
    )
    if ([double]$Window.Width -le 0 -or [double]$Window.Height -le 0) { return $false }
    $title = [string]$Window.Title
    $expectedName = Get-M2WValue -Object $Target -Name 'name'
    if ($null -ne $expectedName -and $title -ne [string]$expectedName) { return $false }
    if (-not (Test-M2WTargetName -ActualName $title -Target $Target)) { return $false }
    $requestedType = [string](Get-M2WValue -Object $Target -Name 'controlType' -Default 'Window')
    return -not $requestedType -or $requestedType -eq 'Window'
}

function Get-M2WNativeVisibleWindows {
    param([int]$ProcessId = 0)
    Initialize-M2WUiAutomation
    return @([M2W.WindowEnumerationV1]::GetVisibleWindows($ProcessId))
}

function Find-M2WTopLevelWindow {
    param(
        [Parameter(Mandatory)]$Target,
        [int]$TimeoutSeconds = 20
    )
    Initialize-M2WUiAutomation
    $desktop = [System.Windows.Automation.AutomationElement]::RootElement
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            $candidates = $desktop.FindAll(
                [System.Windows.Automation.TreeScope]::Children,
                [System.Windows.Automation.Condition]::TrueCondition
            )
            foreach ($candidate in $candidates) {
                if (Test-M2WTopLevelWindowCandidate -Element $candidate -Target $Target) { return $candidate }
            }
            # Never scan every desktop descendant: one stalled UIA provider can block the
            # entire runner. Win32 enumeration includes owned Swing dialogs and remains
            # independent from other applications' accessibility implementations.
            foreach ($nativeWindow in @(Get-M2WNativeVisibleWindows)) {
                if (-not (Test-M2WNativeWindowCandidate -Window $nativeWindow -Target $Target)) { continue }
                try {
                    $candidate = [System.Windows.Automation.AutomationElement]::FromHandle(
                        [IntPtr]([int64]$nativeWindow.Handle)
                    )
                    if ($candidate) { return $candidate }
                }
                catch { }
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
    if ((Test-M2WJavaUiRoot -Root $Root) -and $handle -ne [IntPtr]::Zero) {
        $javaSnapshot = Export-M2WJavaAccessibilityTree -WindowHandle $handle -ProcessId $processId -Path $javaPath -Limit $Limit
    }
    if (-not $javaSnapshot) {
        $javaSnapshot = [pscustomobject]@{
            Status = $(if (Test-M2WJavaUiRoot -Root $Root) { 'BLOCKED' } else { 'NOT_APPLICABLE' })
            Blocker = $(if (Test-M2WJavaUiRoot -Root $Root) { 'BLOCKED_JAVA_ACCESS_BRIDGE_UNAVAILABLE' } else { $null })
            Detail = $(if (Test-M2WJavaUiRoot -Root $Root) { 'No native Java window handle was available.' } else { 'The target window is not a Java AWT or Swing root.' })
            Nodes = @()
        }
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
    $lastBlocker = $null
    $lastDetail = $null
    do {
        $snapshot = Get-M2WJavaAccessibilitySnapshot -WindowHandle $handle -ProcessId $processId
        if ($snapshot.Status -eq 'READY') {
            foreach ($node in @($snapshot.Nodes)) {
                if (Test-M2WJavaNodeTarget -Node $node -Target $Target) { return $node }
            }
        }
        elseif ($snapshot.Status -eq 'BLOCKED') {
            $lastBlocker = [string]$snapshot.Blocker
            $lastDetail = [string]$snapshot.Detail
            break
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($lastBlocker) {
        return [pscustomobject]@{
            M2WLookupBlocked = $true
            Blocker = $lastBlocker
            Detail = $lastDetail
        }
    }
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
        return [pscustomobject]@{ Status = 'READY'; Provider = 'UIAutomation'; Element = $element; Node = $null; Root = $Root; Blocker = $null; Detail = $null }
    }
    if (Test-M2WJavaUiRoot -Root $Root) {
        $node = Find-M2WJavaElement -Target $Target -Root $Root -TimeoutSeconds $TimeoutSeconds
        if ($node -and $node.PSObject.Properties['M2WLookupBlocked']) {
            return [pscustomobject]@{
                Status = 'BLOCKED'; Provider = 'JavaAccessBridge'; Element = $null; Node = $null
                Root = $Root; Blocker = $node.Blocker; Detail = $node.Detail
            }
        }
        if ($node) {
            return [pscustomobject]@{ Status = 'READY'; Provider = 'JavaAccessBridge'; Element = $null; Node = $node; Root = $Root; Blocker = $null; Detail = $null }
        }
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

function Get-M2WJavaChildPath {
    param($Node)
    if ($null -eq $Node) {
        return [pscustomobject]@{ Available = $false; Path = [int[]]@() }
    }
    $property = $Node.PSObject.Properties['ChildPath']
    if (-not $property) {
        return [pscustomobject]@{ Available = $false; Path = [int[]]@() }
    }

    $path = [System.Collections.Generic.List[int]]::new()
    foreach ($value in @($property.Value)) {
        try { $childIndex = [int]$value }
        catch { return [pscustomobject]@{ Available = $false; Path = [int[]]@() } }
        if ($childIndex -lt 0) {
            return [pscustomobject]@{ Available = $false; Path = [int[]]@() }
        }
        $path.Add($childIndex)
    }
    return [pscustomobject]@{ Available = $true; Path = [int[]]$path.ToArray() }
}

function Test-M2WJavaPhysicalClickAvailable {
    param(
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [Parameter(Mandatory)]$Node
    )
    if ($WindowHandle -eq [IntPtr]::Zero) { return $false }
    if ([bool](Get-M2WValue -Object $Node -Name 'Offscreen' -Default $true)) { return $false }
    $x = [double](Get-M2WValue -Object $Node -Name 'X' -Default 0)
    $y = [double](Get-M2WValue -Object $Node -Name 'Y' -Default 0)
    $width = [double](Get-M2WValue -Object $Node -Name 'Width' -Default 0)
    $height = [double](Get-M2WValue -Object $Node -Name 'Height' -Default 0)
    if ($width -le 0 -or $height -le 0) { return $false }

    # Java Access Bridge can report a control as showing even when its bounds extend under
    # the Windows taskbar after a DPI or remote-display change. A native click there would
    # activate the shell instead of the application, so use the isolated JAB action instead.
    $workArea = [System.Windows.Forms.Screen]::FromHandle($WindowHandle).WorkingArea
    return $x -ge $workArea.Left `
        -and $y -ge $workArea.Top `
        -and ($x + $width) -le $workArea.Right `
        -and ($y + $height) -le $workArea.Bottom
}

function Invoke-M2WUnifiedClick {
    param([Parameter(Mandatory)]$Match)
    if ((Get-M2WValue -Object $Match -Name 'Status' -Default 'READY') -eq 'BLOCKED') {
        return [pscustomobject]@{
            Status = 'BLOCKED'; Provider = $Match.Provider; Method = $null; Action = $null
            Blocker = $Match.Blocker; Detail = $Match.Detail
        }
    }
    if ($Match.Provider -eq 'UIAutomation') {
        Invoke-M2WElementClick -Element $Match.Element
        return [pscustomobject]@{ Status = 'PASS'; Provider = 'UIAutomation'; Method = 'AutomationPatternOrPhysicalFallback'; Action = $null; Blocker = $null; Detail = $null }
    }
    $windowHandle = Get-M2WRootNativeHandle -Root $Match.Root
    $processId = Get-M2WRootProcessId -Root $Match.Root
    # Swing action listeners commonly open modal dialogs. Invoking those listeners through
    # Java Access Bridge is synchronous and can block until the dialog closes. JAB still
    # supplies the exact target bounds, while a native pointer click returns immediately and
    # leaves the bridge available for evidence capture inside the newly opened dialog.
    if (Test-M2WJavaPhysicalClickAvailable -WindowHandle $windowHandle -Node $Match.Node) {
        if (-not [M2W.WindowActivationV1]::ActivateWindow($windowHandle)) {
            throw 'Unable to activate the Java target window before clicking.'
        }
        Start-Sleep -Milliseconds 120
        $bounds = Get-M2WUnifiedBounds -Match $Match
        Invoke-M2WPointClick -X ($bounds.X + ($bounds.Width / 2)) -Y ($bounds.Y + ($bounds.Height / 2))
        return [pscustomobject]@{
            Status = 'PASS'; Provider = 'JavaAccessBridge'; Method = 'PhysicalFromJavaBounds'
            Action = 'click'; Blocker = $null; Detail = 'Clicked native pointer coordinates resolved from Java accessibility bounds.'
        }
    }
    $childPath = Get-M2WJavaChildPath -Node $Match.Node
    if ($childPath.Available) {
        $accessibleAction = Invoke-M2WJavaAccessibleAction `
            -WindowHandle $windowHandle `
            -ProcessId $processId `
            -ChildPath ([int[]]$childPath.Path) `
            -PreferredAction 'click'
        if ($accessibleAction.Status -eq 'PASS') {
            return [pscustomobject]@{
                Status = 'PASS'
                Provider = 'JavaAccessBridge'
                Method = 'AccessibleAction'
                Action = $accessibleAction.Action
                Blocker = $null
                Detail = $accessibleAction.Detail
            }
        }
        if ($accessibleAction.Status -eq 'BLOCKED') {
            return [pscustomobject]@{
                Status = 'BLOCKED'; Provider = 'JavaAccessBridge'; Method = 'AccessibleAction'; Action = $null
                Blocker = $accessibleAction.Blocker; Detail = $accessibleAction.Detail
            }
        }
        if ($accessibleAction.Status -eq 'FAIL') {
            return [pscustomobject]@{
                Status = 'FAIL'; Provider = 'JavaAccessBridge'; Method = 'AccessibleAction'; Action = $accessibleAction.Action
                Blocker = $accessibleAction.Blocker; Detail = $accessibleAction.Detail
            }
        }
    }
    if ($windowHandle -ne [IntPtr]::Zero) {
        if (-not [M2W.WindowActivationV1]::ActivateWindow($windowHandle)) {
            throw 'Unable to activate the Java target window before clicking.'
        }
        Start-Sleep -Milliseconds 120
    }
    $bounds = Get-M2WUnifiedBounds -Match $Match
    if ($bounds.Width -le 0 -or $bounds.Height -le 0 -or $Match.Node.Offscreen) {
        throw 'Java accessible target does not have visible clickable bounds.'
    }
    Invoke-M2WPointClick -X ($bounds.X + ($bounds.Width / 2)) -Y ($bounds.Y + ($bounds.Height / 2))
    return [pscustomobject]@{ Status = 'PASS'; Provider = 'JavaAccessBridge'; Method = 'PhysicalFallback'; Action = $null; Blocker = $null; Detail = $null }
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

function Get-M2WEffectiveUiControlType {
    param([Parameter(Mandatory)]$Node)
    $reported = [string]$Node.ControlType
    if ($reported -ne 'Pane') { return $reported }
    $className = ([string]$Node.ClassName).ToUpperInvariant()
    if ($className -match '(?:^|\.)BUTTON(?:\.|$)') { return 'Button' }
    if ($className -match '(?:^|\.)EDIT(?:\.|$)') { return 'Edit' }
    if ($className -match '(?:^|\.)COMBOBOX(?:\.|$)') { return 'ComboBox' }
    if ($className -match '(?:^|\.)CHECKBOX(?:\.|$)') { return 'CheckBox' }
    if ($className -match '(?:^|\.)RADIOBUTTON(?:\.|$)') { return 'RadioButton' }
    return $reported
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
    $uiNodes = @($tree | ForEach-Object {
        $effectiveType = Get-M2WEffectiveUiControlType -Node $_
        if ($actionableTypes -contains $effectiveType) {
            $target = [pscustomobject]@{ name = $_.Name; automationId = $_.AutomationId }
            $dangerous = Test-M2WDangerousTarget -Target $target
            [pscustomobject]@{
                Id = "uia:$($_.Index)"
                Provider = 'UIAutomation'
                Index = $_.Index
                Parent = $_.Parent
                Name = $_.Name
                AutomationId = $_.AutomationId
                ControlType = $effectiveType
                ReportedControlType = $_.ControlType
                ClassName = $_.ClassName
                Bounds = $_.Bounds
                Enabled = $_.IsEnabled
                Offscreen = $_.IsOffscreen
                KeyboardFocusable = $_.IsKeyboardFocusable
                Dangerous = $dangerous
                SuggestedAction = $(if ($dangerous) { 'skip' } elseif ($effectiveType -eq 'Edit') { 'inspect' } else { 'invoke' })
            }
        }
    })
    $javaNodes = @($evidence.JavaAccessBridge.Nodes | Where-Object {
        (-not $_.Offscreen) -and $_.Width -gt 0 -and $_.Height -gt 0 -and
        ($_.Actionable -or $actionableTypes -contains $_.ControlType)
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

function Convert-M2WGraphBoundsToRect {
    param([Parameter(Mandatory)]$Bounds)
    return [System.Windows.Rect]::new(
        [double]$Bounds.X,
        [double]$Bounds.Y,
        [double]$Bounds.Width,
        [double]$Bounds.Height
    )
}

function Test-M2WExpectedCompositeOverlap {
    param(
        [Parameter(Mandatory)]$First,
        [Parameter(Mandatory)]$Second,
        [int]$TolerancePixels = 2
    )
    $firstType = [string](Get-M2WValue -Object $First -Name 'ControlType')
    $secondType = [string](Get-M2WValue -Object $Second -Name 'ControlType')
    $firstBounds = Convert-M2WGraphBoundsToRect -Bounds $First.Bounds
    $secondBounds = Convert-M2WGraphBoundsToRect -Bounds $Second.Bounds

    if ($firstType -eq 'Button' -and $secondType -eq 'Button') {
        $smallButtons = $firstBounds.Width -le 32 -and $secondBounds.Width -le 32 -and
            $firstBounds.Height -le 32 -and $secondBounds.Height -le 32
        $sameColumn = [Math]::Abs($firstBounds.X - $secondBounds.X) -le $TolerancePixels -and
            [Math]::Abs($firstBounds.Width - $secondBounds.Width) -le $TolerancePixels
        $verticalJoin = [Math]::Min(
            [Math]::Abs($firstBounds.Bottom - $secondBounds.Top),
            [Math]::Abs($secondBounds.Bottom - $firstBounds.Top)
        ) -le $TolerancePixels
        if ($smallButtons -and $sameColumn -and $verticalJoin) { return $true }
    }

    $button = $null
    $editor = $null
    if ($firstType -eq 'Button' -and $secondType -eq 'Edit') {
        $button = $firstBounds
        $editor = $secondBounds
    }
    elseif ($firstType -eq 'Edit' -and $secondType -eq 'Button') {
        $button = $secondBounds
        $editor = $firstBounds
    }
    if ($button -and $editor) {
        $rightSideWidth = [Math]::Max(32, [Math]::Min(48, $editor.Width * 0.45))
        $narrowButton = $button.Width -le 32 -and $button.Height -le ($editor.Height + $TolerancePixels)
        $atEditorRight = $button.Left -ge ($editor.Right - $rightSideWidth) -and
            $button.Right -le ($editor.Right + $TolerancePixels)
        $verticallyAligned = $button.Bottom -ge ($editor.Top - $TolerancePixels) -and
            $button.Top -le ($editor.Bottom + $TolerancePixels)
        if ($narrowButton -and $atEditorRight -and $verticallyAligned) { return $true }
    }
    return $false
}

function Export-M2WDeterministicAudit {
    param(
        [Parameter(Mandatory)]$Graph,
        [Parameter(Mandatory)][string]$Path,
        [string[]]$FailOn = @(),
        [int]$TolerancePixels = 2
    )
    $findings = [System.Collections.Generic.List[object]]::new()
    $javaPrimary = [bool](
        $Graph.Root.ClassName -match '^(?:SunAwt|javax\.swing|java\.awt)' -and
        [string]$Graph.Providers.JavaAccessBridge.Status -eq 'READY' -and
        [int]$Graph.Providers.JavaAccessBridge.Actionable -gt 0
    )
    $provider = if ($javaPrimary) { 'JavaAccessBridge' } else { 'UIAutomation' }
    $nodes = @($Graph.Nodes | Where-Object { $_.Provider -eq $provider })
    $rootBounds = Convert-M2WGraphBoundsToRect -Bounds $Graph.Root.Bounds

    foreach ($node in $nodes) {
        $bounds = Convert-M2WGraphBoundsToRect -Bounds $node.Bounds
        if ([string]::IsNullOrWhiteSpace([string]$node.Name)) {
            $findings.Add([pscustomobject]@{
                Code = 'MISSING_ACCESSIBLE_NAME'; Severity = 'warning'; NodeId = $node.Id
                OtherNodeId = $null; Detail = 'Visible actionable control has no accessible name.'; Bounds = $node.Bounds
            })
        }
        if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
            $findings.Add([pscustomobject]@{
                Code = 'NONPOSITIVE_BOUNDS'; Severity = 'error'; NodeId = $node.Id
                OtherNodeId = $null; Detail = 'Actionable control has non-positive bounds.'; Bounds = $node.Bounds
            })
            continue
        }
        if ([bool]$node.Offscreen) {
            $findings.Add([pscustomobject]@{
                Code = 'OFFSCREEN_ACTION'; Severity = 'warning'; NodeId = $node.Id
                OtherNodeId = $null; Detail = 'Actionable control is reported off screen.'; Bounds = $node.Bounds
            })
        }
        elseif (-not (Test-M2WRectContained -Child $bounds -Parent $rootBounds -Tolerance $TolerancePixels)) {
            $findings.Add([pscustomobject]@{
                Code = 'OUTSIDE_WINDOW'; Severity = 'error'; NodeId = $node.Id
                OtherNodeId = $null; Detail = 'Actionable control extends outside the owning window.'; Bounds = $node.Bounds
            })
        }
    }

    $visibleNodes = @($nodes | Where-Object {
        -not $_.Offscreen -and $_.Bounds.Width -gt 0 -and $_.Bounds.Height -gt 0
    })
    for ($firstIndex = 0; $firstIndex -lt $visibleNodes.Count; $firstIndex++) {
        $first = $visibleNodes[$firstIndex]
        for ($secondIndex = $firstIndex + 1; $secondIndex -lt $visibleNodes.Count; $secondIndex++) {
            $second = $visibleNodes[$secondIndex]
            if ($first.Parent -ne $second.Parent) { continue }
            $area = Get-M2WRectOverlapArea `
                -First (Convert-M2WGraphBoundsToRect -Bounds $first.Bounds) `
                -Second (Convert-M2WGraphBoundsToRect -Bounds $second.Bounds)
            if ($area -le ($TolerancePixels * $TolerancePixels)) { continue }
            if (Test-M2WExpectedCompositeOverlap -First $first -Second $second -TolerancePixels $TolerancePixels) { continue }
            $findings.Add([pscustomobject]@{
                Code = 'ACTIONABLE_OVERLAP'; Severity = 'error'; NodeId = $first.Id
                OtherNodeId = $second.Id; Detail = "Sibling actionable controls overlap by $area pixel(s)."
                Bounds = [pscustomobject]@{ First = $first.Bounds; Second = $second.Bounds }
            })
        }
    }

    $blocking = @($findings | Where-Object { $FailOn -contains $_.Code })
    $audit = [pscustomobject]@{
        CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
        Status = $(if ($blocking.Count) { 'FAIL' } else { 'PASS' })
        Provider = $provider
        NodeCount = $nodes.Count
        FindingCount = $findings.Count
        BlockingFindingCount = $blocking.Count
        FailOn = @($FailOn)
        Findings = @($findings)
    }
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $audit | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $audit
}

function Get-M2WSafeControlCategory {
    param([Parameter(Mandatory)]$Node)
    if ($Node.Dangerous -or -not $Node.Enabled -or $Node.Offscreen) { return $null }
    $name = ([string]$Node.Name).Trim()
    if (-not $name) { return $null }
    $type = [string]$Node.ControlType
    if ($type -eq 'TabItem') { return 'tab' }
    if ($type -eq 'MenuItem' -and $name -match '(?i)^(file|edit|view|window|tools|settings|help|\u6587\u4ef6|\u7f16\u8f91|\u663e\u793a|\u7a97\u53e3|\u5de5\u5177|\u8bbe\u7f6e|\u5e2e\u52a9)$') {
        return 'menu'
    }
    if ($type -in @('Button', 'Hyperlink') -and $name -match '(?i)settings|preferences|options|appearance|theme|details|about|overview|advanced|\u8bbe\u7f6e|\u9009\u9879|\u5916\u89c2|\u4e3b\u9898|\u8be6\u60c5|\u8be6\u7ec6|\u5173\u4e8e|\u603b\u89c8|\u9ad8\u7ea7') {
        return 'dialog'
    }
    if ($type -in @('ListItem', 'TreeItem', 'Button') -and $name -match '(?i)overview|weight|performance|remote compute|general|display|analysis|\u603b\u89c8|\u6743\u91cd|\u6027\u80fd|\u8fdc\u7a0b\u7b97\u529b|\u5e38\u89c4|\u663e\u793a|\u5206\u6790|\u82f1\u4f1f\u8fbe') {
        return 'navigation'
    }
    return $null
}

function Get-M2WWindowIdentity {
    param([Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Window)
    try {
        $handle = [int64]$Window.Current.NativeWindowHandle
        if ($handle -ne 0) { return "handle:$handle" }
    }
    catch { }
    try {
        $runtimeId = @($Window.GetRuntimeId())
        if ($runtimeId.Count) { return "runtime:$($runtimeId -join '.')" }
    }
    catch { }
    try {
        $bounds = $Window.Current.BoundingRectangle
        return "fallback:$($Window.Current.ProcessId):$($Window.Current.Name):$([int]$bounds.X):$([int]$bounds.Y):$([int]$bounds.Width):$([int]$bounds.Height)"
    }
    catch { return "unavailable:$([Guid]::NewGuid().ToString('N'))" }
}

function Get-M2WVisibleWindowsForProcess {
    param([Parameter(Mandatory)][int]$ProcessId)
    $windows = [System.Collections.Generic.List[System.Windows.Automation.AutomationElement]]::new()
    $identities = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($nativeWindow in @(Get-M2WNativeVisibleWindows -ProcessId $ProcessId)) {
        try {
            $element = [System.Windows.Automation.AutomationElement]::FromHandle(
                [IntPtr]([int64]$nativeWindow.Handle)
            )
            if (-not $element) { continue }
            $identity = Get-M2WWindowIdentity -Window $element
            if ($identities.Add($identity)) { $windows.Add($element) }
        }
        catch { }
    }
    return @($windows)
}

function Close-M2WExplorationWindow {
    param([Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Window)
    $pattern = $null
    if ($Window.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$pattern)) {
        ([System.Windows.Automation.WindowPattern]$pattern).Close()
        return
    }
    try { $Window.SetFocus(); [System.Windows.Forms.SendKeys]::SendWait('%{F4}') } catch { }
}

function Wait-M2WExplorationWindowsClosed {
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string[]]$WindowIdentities,
        [int]$TimeoutMilliseconds = 2500
    )
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    do {
        $visibleIdentities = @(Get-M2WVisibleWindowsForProcess -ProcessId $ProcessId | ForEach-Object {
            Get-M2WWindowIdentity -Window $_
        })
        if (-not @($WindowIdentities | Where-Object { $visibleIdentities -contains $_ }).Count) { return $true }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    return $false
}

function Invoke-M2WSafeExploration {
    param(
        [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Root,
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$ScenarioId,
        [Parameter(Mandatory)][string]$Prefix,
        [int]$MaxControls = 12,
        [string[]]$FailOn = @(),
        [int]$TolerancePixels = 2
    )
    $graphPath = Join-Path $RunDirectory "interaction-graphs\$ScenarioId-$Prefix.json"
    $graph = Export-M2WInteractionGraph -Root $Root -Path $graphPath
    $auditPath = Join-Path $RunDirectory "audits\$ScenarioId-$Prefix.json"
    $audit = Export-M2WDeterministicAudit -Graph $graph -Path $auditPath -FailOn $FailOn -TolerancePixels $TolerancePixels
    if ($graph.Status -ne 'READY') {
        return [pscustomobject]@{
            Status = 'BLOCKED'; Blocker = $graph.Blocker; Graph = $graphPath; Audit = $auditPath
            CandidateCount = 0; InvokedCount = 0; StateChangeCount = 0
            SkippedDangerous = @($graph.DeniedDangerous); Results = @()
        }
    }

    $candidates = @($graph.Nodes | ForEach-Object {
        $category = Get-M2WSafeControlCategory -Node $_
        if ($category) {
            [pscustomobject]@{ Node = $_; Category = $category }
        }
    } | Sort-Object @{ Expression = { switch ($_.Category) { 'tab' { 0 } 'navigation' { 1 } 'dialog' { 2 } default { 3 } } } }, @{ Expression = { $_.Node.Name } } | Select-Object -First $MaxControls)
    $results = [System.Collections.Generic.List[object]]::new()
    $processId = Get-M2WRootProcessId -Root $Root
    $rootHandle = Get-M2WRootNativeHandle -Root $Root

    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{
            Status = 'BLOCKED'; Blocker = 'BLOCKED_SAFE_EXPLORATION_EMPTY'
            Graph = $graphPath; Audit = $auditPath; CandidateCount = 0; InvokedCount = 0
            StateChangeCount = 0; SkippedDangerous = @($graph.DeniedDangerous); Results = @()
        }
    }

    foreach ($candidate in $candidates) {
        $node = $candidate.Node
        $safeName = ([string]$node.Name -replace '[^A-Za-z0-9_-]', '_').Trim('_')
        if (-not $safeName) { $safeName = 'control' }
        if ($safeName.Length -gt 32) { $safeName = $safeName.Substring(0, 32) }
        $sequence = '{0:D2}' -f ($results.Count + 1)
        $evidenceBase = "$ScenarioId-$Prefix-$sequence-$safeName"
        $beforePath = Join-Path $RunDirectory "exploration\$evidenceBase-before.png"
        $afterPath = Join-Path $RunDirectory "exploration\$evidenceBase-after.png"
        $treePath = Join-Path $RunDirectory "exploration\$evidenceBase.json"
        $result = [ordered]@{
            Id = $node.Id; Provider = $node.Provider; Name = $node.Name; ControlType = $node.ControlType
            Category = $candidate.Category; Status = 'PASS'; InvocationMethod = $null
            VisibleStateChanged = $false; NewWindows = @(); CleanupVerified = $true
            Evidence = $null; Error = $null; Blocker = $null
        }
        try {
            $beforeWindows = @(Get-M2WVisibleWindowsForProcess -ProcessId $processId)
            $beforeIdentities = @($beforeWindows | ForEach-Object { Get-M2WWindowIdentity -Window $_ })
            Save-M2WScreenshot -Path $beforePath -Window $Root | Out-Null
            $reportedType = Get-M2WValue -Object $node -Name 'ReportedControlType'
            $selectorType = if ($reportedType) { [string]$reportedType } else { [string]$node.ControlType }
            $target = [ordered]@{ name = [string]$node.Name; controlType = $selectorType }
            if ($node.Provider -eq 'UIAutomation' -and $node.AutomationId) { $target['automationId'] = [string]$node.AutomationId }
            $match = Find-M2WUnifiedElement -Target ([pscustomobject]$target) -Root $Root -TimeoutSeconds 3
            if (-not $match) { throw 'Safe exploration target was no longer available.' }
            $invocation = Invoke-M2WUnifiedClick -Match $match
            if ($invocation.Status -eq 'BLOCKED' -and $invocation.Blocker -eq 'BLOCKED_JAVA_ACCESS_BRIDGE_ACTION_TIMEOUT') {
                $observedWindows = @(Get-M2WVisibleWindowsForProcess -ProcessId $processId | Where-Object {
                    $beforeIdentities -notcontains (Get-M2WWindowIdentity -Window $_)
                })
                if ($observedWindows.Count) {
                    $invocation = [pscustomobject]@{
                        Status = 'PASS'; Provider = 'JavaAccessBridge'; Method = 'AccessibleActionObservedNewWindow'
                        Action = 'click'; Blocker = $null
                        Detail = 'The native action return timed out, but a new same-process window confirmed the requested state change.'
                    }
                }
            }
            if ($invocation.Status -ne 'PASS') {
                $result.Status = $invocation.Status
                $result.Error = $invocation.Detail
                $result.Blocker = $invocation.Blocker
                $results.Add([pscustomobject]$result)
                if ($invocation.Status -eq 'BLOCKED') { break }
                continue
            }
            $result.InvocationMethod = "$($invocation.Provider)/$($invocation.Method)"
            Start-Sleep -Milliseconds 450

            $afterWindows = @(Get-M2WVisibleWindowsForProcess -ProcessId $processId)
            $newWindows = @($afterWindows | Where-Object {
                $identity = Get-M2WWindowIdentity -Window $_
                $handle = try { [int64]$_.Current.NativeWindowHandle } catch { 0 }
                $handle -ne [int64]$rootHandle -and $beforeIdentities -notcontains $identity
            })
            $evidenceWindow = if ($newWindows.Count) { $newWindows[0] } else { $Root }
            Save-M2WScreenshot -Path $afterPath -Window $evidenceWindow | Out-Null
            $trees = Export-M2WAccessibleTrees -Root $evidenceWindow -UiAutomationPath $treePath
            $beforeHash = (Get-FileHash -LiteralPath $beforePath -Algorithm SHA256).Hash
            $afterHash = (Get-FileHash -LiteralPath $afterPath -Algorithm SHA256).Hash
            $result.VisibleStateChanged = [bool]($newWindows.Count -or $beforeHash -ne $afterHash)
            $result.NewWindows = @($newWindows | ForEach-Object { [string]$_.Current.Name })
            $result.Evidence = [pscustomobject]@{
                BeforeScreenshot = $beforePath; AfterScreenshot = $afterPath
                UiTree = $treePath; JavaUiTree = $trees.JavaAccessBridgePath
            }
            $newWindowIdentities = @($newWindows | ForEach-Object { Get-M2WWindowIdentity -Window $_ })
            foreach ($window in $newWindows) { Close-M2WExplorationWindow -Window $window }
            if ($newWindowIdentities.Count) {
                $result.CleanupVerified = Wait-M2WExplorationWindowsClosed `
                    -ProcessId $processId -WindowIdentities $newWindowIdentities
                if (-not $result.CleanupVerified) {
                    throw 'Exploration window remained visible after the automated close action.'
                }
            }
            if ($candidate.Category -eq 'menu' -and -not $newWindows.Count) {
                try { $Root.SetFocus(); [System.Windows.Forms.SendKeys]::SendWait('{ESC}') } catch { }
            }
            Start-Sleep -Milliseconds 180
        }
        catch {
            $result.Status = 'FAIL'
            $result.Error = $_.Exception.Message
        }
        $results.Add([pscustomobject]$result)
    }

    $failed = @($results | Where-Object { $_.Status -eq 'FAIL' })
    $blocked = @($results | Where-Object { $_.Status -eq 'BLOCKED' })
    return [pscustomobject]@{
        Status = $(if ($audit.Status -eq 'FAIL' -or $failed.Count) { 'FAIL' } elseif ($blocked.Count) { 'BLOCKED' } else { 'PASS' })
        Blocker = $(if ($blocked.Count) { $blocked[0].Blocker } else { $null })
        Graph = $graphPath
        Audit = $auditPath
        CandidateCount = $candidates.Count
        InvokedCount = @($results | Where-Object { $_.Status -eq 'PASS' }).Count
        StateChangeCount = @($results | Where-Object VisibleStateChanged).Count
        SkippedDangerous = @($graph.DeniedDangerous)
        Results = @($results)
    }
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
    if ($match -and $match.Status -eq 'BLOCKED') {
        return [pscustomobject]@{ Status = 'BLOCKED'; Passed = $false; Detail = $match.Detail; Blocker = $match.Blocker }
    }
    switch ($condition) {
        'exists' { return [pscustomobject]@{ Status = 'READY'; Passed = [bool]$match; Detail = $(if ($match) { "Element exists through $($match.Provider)." } else { 'Element not found.' }) } }
        'notExists' { return [pscustomobject]@{ Status = 'READY'; Passed = -not $match; Detail = $(if ($match) { 'Unexpected element exists.' } else { 'Element is absent.' }) } }
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
            if ($other -and $other.Status -eq 'BLOCKED') {
                return [pscustomobject]@{ Status = 'BLOCKED'; Passed = $false; Detail = $other.Detail; Blocker = $other.Blocker }
            }
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
        'audit' {
            $graphPath = Join-Path $RunDirectory "interaction-graphs\$ScenarioId-$prefix.json"
            $graph = Export-M2WInteractionGraph -Root $Window -Path $graphPath
            if ($graph.Status -ne 'READY') {
                return [pscustomobject]@{ Status = 'BLOCKED'; Action = $action; Summary = "Audit graph is incomplete: $($graph.Blocker)"; Blocker = $graph.Blocker; InteractionGraph = $graphPath }
            }
            $auditPath = Join-Path $RunDirectory "audits\$ScenarioId-$prefix.json"
            $failOn = @((Get-M2WValue -Object $Step -Name 'failOn' -Default @()) | ForEach-Object { [string]$_ })
            $tolerance = [int](Get-M2WValue -Object $Step -Name 'tolerancePixels' -Default 2)
            $audit = Export-M2WDeterministicAudit -Graph $graph -Path $auditPath -FailOn $failOn -TolerancePixels $tolerance
            return [pscustomobject]@{
                Status = $audit.Status; Action = $action; Audit = $auditPath; InteractionGraph = $graphPath
                FindingCount = $audit.FindingCount; BlockingFindingCount = $audit.BlockingFindingCount
                Summary = "Audited $($audit.NodeCount) actionable control(s); found $($audit.FindingCount) issue(s), $($audit.BlockingFindingCount) blocking."
            }
        }
        'explore' {
            $failOn = @((Get-M2WValue -Object $Step -Name 'failOn' -Default @()) | ForEach-Object { [string]$_ })
            $limit = [int](Get-M2WValue -Object $Step -Name 'maxControls' -Default 12)
            $tolerance = [int](Get-M2WValue -Object $Step -Name 'tolerancePixels' -Default 2)
            $exploration = Invoke-M2WSafeExploration -Root $Window -RunDirectory $RunDirectory -ScenarioId $ScenarioId -Prefix $prefix -MaxControls $limit -FailOn $failOn -TolerancePixels $tolerance
            return [pscustomobject]@{
                Status = $exploration.Status; Action = $action; Blocker = $exploration.Blocker
                InteractionGraph = $exploration.Graph; Audit = $exploration.Audit
                CandidateCount = $exploration.CandidateCount; InvokedCount = $exploration.InvokedCount
                StateChangeCount = $exploration.StateChangeCount; SkippedDangerous = $exploration.SkippedDangerous
                ExplorationResults = $exploration.Results
                Summary = "Safely invoked $($exploration.InvokedCount) of $($exploration.CandidateCount) classified control(s); $($exploration.StateChangeCount) produced visible state changes."
            }
        }
        'assert' {
            $assertion = Test-M2WAssertion -Step $Step -Window $Window
            $assertionStatus = [string](Get-M2WValue -Object $assertion -Name 'Status' -Default 'READY')
            $assertionBlocker = Get-M2WValue -Object $assertion -Name 'Blocker'
            return [pscustomobject]@{
                Status = $(if ($assertionStatus -eq 'BLOCKED') { 'BLOCKED' } elseif ($assertion.Passed) { 'PASS' } else { 'FAIL' })
                Action = $action; Summary = $assertion.Detail; Blocker = $assertionBlocker
            }
        }
        'click' {
            $target = Get-M2WValue -Object $Step -Name 'target'
            if ((Test-M2WDangerousTarget -Target $target) -and -not $AllowDestructiveActions) {
                return [pscustomobject]@{ Status = 'BLOCKED'; Action = $action; Summary = 'Dangerous target denied by profile policy.'; Blocker = 'BLOCKED_DANGEROUS_ACTION' }
            }
            $processId = Get-M2WRootProcessId -Root $Window
            $beforeWindowIdentities = @()
            if ($processId -gt 0) {
                $beforeWindowIdentities = @(Get-M2WVisibleWindowsForProcess -ProcessId $processId | ForEach-Object {
                    Get-M2WWindowIdentity -Window $_
                })
            }
            $match = Find-M2WUnifiedElement -Target $target -Root $Window -TimeoutSeconds 10
            if (-not $match) { return [pscustomobject]@{ Status = 'FAIL'; Action = $action; Summary = 'Click target not found.' } }
            $invocation = Invoke-M2WUnifiedClick -Match $match
            if ($invocation.Status -eq 'BLOCKED' -and $invocation.Blocker -eq 'BLOCKED_JAVA_ACCESS_BRIDGE_ACTION_TIMEOUT' -and $processId -gt 0) {
                $observedWindows = @(Get-M2WVisibleWindowsForProcess -ProcessId $processId | Where-Object {
                    $beforeWindowIdentities -notcontains (Get-M2WWindowIdentity -Window $_)
                })
                if ($observedWindows.Count) {
                    $invocation = [pscustomobject]@{
                        Status = 'PASS'; Provider = 'JavaAccessBridge'; Method = 'AccessibleActionObservedNewWindow'
                        Action = 'click'; Blocker = $null
                        Detail = 'The native action return timed out, but a new same-process window confirmed the requested state change.'
                    }
                }
            }
            if ($invocation.Status -ne 'PASS') {
                return [pscustomobject]@{
                    Status = $invocation.Status; Action = $action; Provider = $invocation.Provider
                    InvocationMethod = $invocation.Method; Blocker = $invocation.Blocker; Summary = $invocation.Detail
                }
            }
            Start-Sleep -Milliseconds 350
            return [pscustomobject]@{
                Status = 'PASS'
                Action = $action
                Provider = $invocation.Provider
                InvocationMethod = $invocation.Method
                Summary = "Invoked target through $($invocation.Provider) using $($invocation.Method)."
            }
        }
        'type' {
            $target = Get-M2WValue -Object $Step -Name 'target'
            $match = Find-M2WUnifiedElement -Target $target -Root $Window -TimeoutSeconds 10
            if (-not $match) { return [pscustomobject]@{ Status = 'FAIL'; Action = $action; Summary = 'Text target not found.' } }
            if ($match.Status -eq 'BLOCKED') {
                return [pscustomobject]@{ Status = 'BLOCKED'; Action = $action; Blocker = $match.Blocker; Summary = $match.Detail }
            }
            $text = [string](Get-M2WValue -Object $Step -Name 'text' -Default '')
            $pattern = $null
            if ($match.Provider -eq 'UIAutomation' -and $match.Element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern) -and -not ([System.Windows.Automation.ValuePattern]$pattern).Current.IsReadOnly) {
                ([System.Windows.Automation.ValuePattern]$pattern).SetValue($text)
            }
            else {
                if ($match.Provider -eq 'UIAutomation') {
                    $match.Element.SetFocus()
                }
                else {
                    $focusResult = Invoke-M2WUnifiedClick -Match $match
                    if ($focusResult.Status -ne 'PASS') {
                        return [pscustomobject]@{ Status = $focusResult.Status; Action = $action; Blocker = $focusResult.Blocker; Summary = $focusResult.Detail }
                    }
                }
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
    'Find-M2WTopLevelWindow',
    'Convert-M2WElement',
    'Export-M2WUiTree',
    'Export-M2WAccessibleTrees',
    'Export-M2WInteractionGraph',
    'Get-M2WEffectiveUiControlType',
    'Export-M2WDeterministicAudit',
    'Get-M2WSafeControlCategory',
    'Invoke-M2WSafeExploration',
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

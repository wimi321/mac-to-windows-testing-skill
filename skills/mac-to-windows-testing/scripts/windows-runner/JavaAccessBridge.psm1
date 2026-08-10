Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:M2WJavaBridgeStarted = $false
$script:M2WJavaBridgeDll = $null
$script:M2WJavaBridgeModulePath = $PSCommandPath

function Initialize-M2WJavaAccessBridgeTypes {
    if ($env:OS -ne 'Windows_NT') {
        throw 'Java Access Bridge is available only on Windows.'
    }
    if ('M2W.JavaAccessBridgeClient' -as [type]) { return }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace M2W {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct AccessibleContextInfoNative {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 1024)] public string Name;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 1024)] public string Description;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Role;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string RoleEnUs;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string States;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string StatesEnUs;
    public int IndexInParent;
    public int ChildrenCount;
    public int X;
    public int Y;
    public int Width;
    public int Height;
    public int AccessibleComponent;
    public int AccessibleAction;
    public int AccessibleSelection;
    public int AccessibleText;
    public int AccessibleInterfaces;
  }

  public sealed class JavaAccessibleNode {
    public int Index { get; set; }
    public int Parent { get; set; }
    public int Depth { get; set; }
    public string Name { get; set; }
    public string Description { get; set; }
    public string Role { get; set; }
    public string LocalizedRole { get; set; }
    public string States { get; set; }
    public string LocalizedStates { get; set; }
    public string ControlType { get; set; }
    public int IndexInParent { get; set; }
    public int ChildrenCount { get; set; }
    public int X { get; set; }
    public int Y { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
    public bool Enabled { get; set; }
    public bool Offscreen { get; set; }
    public bool KeyboardFocusable { get; set; }
    public bool HasKeyboardFocus { get; set; }
    public bool Actionable { get; set; }
    public bool SupportsText { get; set; }
    public int[] ChildPath { get; set; }
  }

  public sealed class JavaAccessibleActionResult {
    public bool Success { get; set; }
    public bool Supported { get; set; }
    public string SelectedAction { get; set; }
    public string[] AvailableActions { get; set; }
    public int FailureIndex { get; set; }
    public string Detail { get; set; }
  }

  public static class JavaAccessBridgeClient {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryW(string fileName);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeLibrary(IntPtr module);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);

    [DllImport("WindowsAccessBridge-64.dll", EntryPoint = "Windows_run", CallingConvention = CallingConvention.Cdecl)]
    private static extern void WindowsRunNative();

    [DllImport("WindowsAccessBridge-64.dll", EntryPoint = "isJavaWindow", CallingConvention = CallingConvention.Cdecl)]
    private static extern int IsJavaWindowNative(IntPtr window);

    [DllImport("WindowsAccessBridge-64.dll", EntryPoint = "getAccessibleContextFromHWND", CallingConvention = CallingConvention.Cdecl)]
    private static extern int GetAccessibleContextFromHwndNative(IntPtr window, out int vmId, out long context);

    [DllImport("WindowsAccessBridge-64.dll", EntryPoint = "getAccessibleContextInfo", CallingConvention = CallingConvention.Cdecl)]
    private static extern int GetAccessibleContextInfoNative(int vmId, long context, out AccessibleContextInfoNative info);

    [DllImport("WindowsAccessBridge-64.dll", EntryPoint = "getAccessibleChildFromContext", CallingConvention = CallingConvention.Cdecl)]
    private static extern long GetAccessibleChildFromContextNative(int vmId, long context, int index);

    [DllImport("WindowsAccessBridge-64.dll", EntryPoint = "releaseJavaObject", CallingConvention = CallingConvention.Cdecl)]
    private static extern void ReleaseJavaObjectNative(int vmId, long context);

    [DllImport("WindowsAccessBridge-64.dll", EntryPoint = "getAccessibleActions", CallingConvention = CallingConvention.Cdecl)]
    private static extern int GetAccessibleActionsNative(int vmId, long context, IntPtr actions);

    [DllImport("WindowsAccessBridge-64.dll", EntryPoint = "doAccessibleActions", CallingConvention = CallingConvention.Cdecl)]
    private static extern int DoAccessibleActionsNative(int vmId, long context, IntPtr actionsToDo, out int failure);

    private static IntPtr module = IntPtr.Zero;
    private static bool started;
    private const int ShortStringChars = 256;
    private const int ActionInfoBytes = ShortStringChars * 2;
    private const int MaxActionInfo = 256;
    private const int MaxActionsToDo = 32;

    public static int ContextInfoSize {
      get { return Marshal.SizeOf(typeof(AccessibleContextInfoNative)); }
    }

    public static int AccessibleActionsSize {
      get { return sizeof(int) + (ActionInfoBytes * MaxActionInfo); }
    }

    public static int AccessibleActionsToDoSize {
      get { return sizeof(int) + (ActionInfoBytes * MaxActionsToDo); }
    }

    public static void Start(string dllPath) {
      if (started) { return; }
      if (IntPtr.Size != 8) {
        throw new PlatformNotSupportedException("Java Access Bridge requires a 64-bit runner process.");
      }
      module = LoadLibraryW(dllPath);
      if (module == IntPtr.Zero) {
        throw new InvalidOperationException("Unable to load Java Access Bridge DLL. Win32 error: " + Marshal.GetLastWin32Error());
      }
      string[] exports = {
        "Windows_run", "isJavaWindow", "getAccessibleContextFromHWND",
        "getAccessibleContextInfo", "getAccessibleChildFromContext", "releaseJavaObject",
        "getAccessibleActions", "doAccessibleActions"
      };
      foreach (string exportName in exports) {
        if (GetProcAddress(module, exportName) == IntPtr.Zero) {
          FreeLibrary(module);
          module = IntPtr.Zero;
          throw new EntryPointNotFoundException("Java Access Bridge export not found: " + exportName);
        }
      }
      WindowsRunNative();
      started = true;
    }

    public static bool IsJavaWindow(IntPtr window) {
      return started && window != IntPtr.Zero && IsJavaWindowNative(window) != 0;
    }

    private sealed class QueueEntry {
      public long Context;
      public int Parent;
      public int Depth;
      public int[] ChildPath;
    }

    public static JavaAccessibleNode[] Walk(IntPtr window, int limit) {
      if (!started) { throw new InvalidOperationException("Java Access Bridge is not initialized."); }
      if (limit < 1) { throw new ArgumentOutOfRangeException("limit"); }

      int vmId;
      long rootContext;
      if (GetAccessibleContextFromHwndNative(window, out vmId, out rootContext) == 0 || rootContext == 0) {
        return new JavaAccessibleNode[0];
      }

      var result = new List<JavaAccessibleNode>();
      var queue = new Queue<QueueEntry>();
      var seen = new HashSet<long>();
      var references = new List<long>();
      queue.Enqueue(new QueueEntry { Context = rootContext, Parent = -1, Depth = 0, ChildPath = new int[0] });
      seen.Add(rootContext);
      references.Add(rootContext);

      try {
        while (queue.Count > 0 && result.Count < limit) {
          QueueEntry entry = queue.Dequeue();
          AccessibleContextInfoNative info;
          if (GetAccessibleContextInfoNative(vmId, entry.Context, out info) == 0) { continue; }
          int nodeIndex = result.Count;
          string states = Clean(info.StatesEnUs);
          string role = Clean(info.RoleEnUs);
          bool showing = HasState(states, "showing") || HasState(states, "visible");
          bool supportsAction = info.AccessibleAction != 0 || (info.AccessibleInterfaces & 2) != 0;
          result.Add(new JavaAccessibleNode {
            Index = nodeIndex,
            Parent = entry.Parent,
            Depth = entry.Depth,
            Name = Clean(info.Name),
            Description = Clean(info.Description),
            Role = role,
            LocalizedRole = Clean(info.Role),
            States = states,
            LocalizedStates = Clean(info.States),
            ControlType = MapControlType(role, states),
            IndexInParent = info.IndexInParent,
            ChildrenCount = Math.Max(0, info.ChildrenCount),
            X = info.X,
            Y = info.Y,
            Width = info.Width,
            Height = info.Height,
            Enabled = HasState(states, "enabled"),
            Offscreen = info.Width <= 0 || info.Height <= 0 || !showing,
            KeyboardFocusable = HasState(states, "focusable"),
            HasKeyboardFocus = HasState(states, "focused"),
            Actionable = supportsAction || IsActionableRole(role),
            SupportsText = info.AccessibleText != 0 || (info.AccessibleInterfaces & 32) != 0,
            ChildPath = entry.ChildPath
          });

          int childCount = Math.Min(Math.Max(0, info.ChildrenCount), limit);
          for (int childIndex = 0; childIndex < childCount; childIndex++) {
            long child = GetAccessibleChildFromContextNative(vmId, entry.Context, childIndex);
            if (child == 0) { continue; }
            if (!seen.Add(child)) {
              ReleaseJavaObjectNative(vmId, child);
              continue;
            }
            references.Add(child);
            int[] childPath = new int[entry.ChildPath.Length + 1];
            Array.Copy(entry.ChildPath, childPath, entry.ChildPath.Length);
            childPath[childPath.Length - 1] = childIndex;
            queue.Enqueue(new QueueEntry { Context = child, Parent = nodeIndex, Depth = entry.Depth + 1, ChildPath = childPath });
          }
        }
      }
      finally {
        // JAB may recycle object handles after release. Keep every context alive for the
        // complete walk so handle-based de-duplication cannot hide legitimate descendants.
        for (int index = references.Count - 1; index >= 0; index--) {
          ReleaseJavaObjectNative(vmId, references[index]);
        }
      }
      return result.ToArray();
    }

    public static JavaAccessibleActionResult InvokeAction(IntPtr window, int[] childPath, string preferredAction) {
      if (!started) { throw new InvalidOperationException("Java Access Bridge is not initialized."); }
      if (window == IntPtr.Zero) { throw new ArgumentException("A Java window handle is required.", "window"); }

      int vmId;
      long rootContext;
      if (GetAccessibleContextFromHwndNative(window, out vmId, out rootContext) == 0 || rootContext == 0) {
        return ActionResult(false, false, null, new string[0], -1, "The Java root context is unavailable.");
      }

      var references = new List<long>();
      references.Add(rootContext);
      long context = rootContext;
      IntPtr actionsBuffer = IntPtr.Zero;
      IntPtr actionsToDoBuffer = IntPtr.Zero;
      try {
        foreach (int childIndex in childPath ?? new int[0]) {
          if (childIndex < 0) {
            return ActionResult(false, false, null, new string[0], -1, "The Java accessibility path is invalid.");
          }
          long child = GetAccessibleChildFromContextNative(vmId, context, childIndex);
          if (child == 0) {
            return ActionResult(false, false, null, new string[0], -1, "The Java control changed before its action could be invoked.");
          }
          references.Add(child);
          context = child;
        }

        actionsBuffer = Marshal.AllocHGlobal(AccessibleActionsSize);
        if (GetAccessibleActionsNative(vmId, context, actionsBuffer) == 0) {
          return ActionResult(false, false, null, new string[0], -1, "The Java control does not expose an accessible action.");
        }

        int count = Marshal.ReadInt32(actionsBuffer);
        if (count < 0 || count > MaxActionInfo) {
          return ActionResult(false, false, null, new string[0], -1, "Java Access Bridge returned an invalid action count.");
        }
        var available = new List<string>();
        for (int index = 0; index < count; index++) {
          IntPtr actionPointer = IntPtr.Add(actionsBuffer, sizeof(int) + (index * ActionInfoBytes));
          string action = (Marshal.PtrToStringUni(actionPointer, ShortStringChars) ?? String.Empty).TrimEnd('\0').Trim();
          if (!String.IsNullOrEmpty(action)) { available.Add(action); }
        }
        if (available.Count == 0) {
          return ActionResult(false, false, null, available.ToArray(), -1, "The Java control exposes no usable accessible action.");
        }

        string selected = null;
        if (!String.IsNullOrWhiteSpace(preferredAction)) {
          selected = available.Find(delegate(string value) {
            return String.Equals(value, preferredAction, StringComparison.OrdinalIgnoreCase);
          });
        }
        if (selected == null) {
          selected = available.Find(delegate(string value) {
            return String.Equals(value, "click", StringComparison.OrdinalIgnoreCase);
          });
        }
        if (selected == null) { selected = available[0]; }

        actionsToDoBuffer = Marshal.AllocHGlobal(AccessibleActionsToDoSize);
        Marshal.WriteInt32(actionsToDoBuffer, 1);
        char[] actionCharacters = new char[ShortStringChars];
        int copyLength = Math.Min(selected.Length, ShortStringChars - 1);
        selected.CopyTo(0, actionCharacters, 0, copyLength);
        Marshal.Copy(actionCharacters, 0, IntPtr.Add(actionsToDoBuffer, sizeof(int)), actionCharacters.Length);
        int failure;
        bool success = DoAccessibleActionsNative(vmId, context, actionsToDoBuffer, out failure) != 0;
        return ActionResult(
          success,
          true,
          selected,
          available.ToArray(),
          failure,
          success ? "The Java accessible action completed." : "Java Access Bridge rejected the requested action."
        );
      }
      finally {
        if (actionsToDoBuffer != IntPtr.Zero) { Marshal.FreeHGlobal(actionsToDoBuffer); }
        if (actionsBuffer != IntPtr.Zero) { Marshal.FreeHGlobal(actionsBuffer); }
        for (int index = references.Count - 1; index >= 0; index--) {
          ReleaseJavaObjectNative(vmId, references[index]);
        }
      }
    }

    private static JavaAccessibleActionResult ActionResult(
      bool success,
      bool supported,
      string selectedAction,
      string[] availableActions,
      int failureIndex,
      string detail
    ) {
      return new JavaAccessibleActionResult {
        Success = success,
        Supported = supported,
        SelectedAction = selectedAction,
        AvailableActions = availableActions ?? new string[0],
        FailureIndex = failureIndex,
        Detail = detail
      };
    }

    private static string Clean(string value) {
      return (value ?? String.Empty).TrimEnd('\0').Trim();
    }

    private static bool HasState(string states, string expected) {
      if (String.IsNullOrEmpty(states)) { return false; }
      string[] parts = states.Split(',');
      foreach (string part in parts) {
        if (String.Equals(part.Trim(), expected, StringComparison.OrdinalIgnoreCase)) { return true; }
      }
      return false;
    }

    private static bool IsActionableRole(string role) {
      switch ((role ?? String.Empty).ToLowerInvariant()) {
        case "push button":
        case "toggle button":
        case "check box":
        case "combo box":
        case "hyperlink":
        case "list item":
        case "menu item":
        case "page tab":
        case "radio button":
        case "tree item":
          return true;
        default:
          return false;
      }
    }

    private static string MapControlType(string role, string states) {
      switch ((role ?? String.Empty).ToLowerInvariant()) {
        case "alert": return "Text";
        case "check box": return "CheckBox";
        case "combo box": return "ComboBox";
        case "dialog": return "Window";
        case "frame": return "Window";
        case "hyperlink": return "Hyperlink";
        case "label": return "Text";
        case "list": return "List";
        case "list item": return "ListItem";
        case "menu": return "Menu";
        case "menu bar": return "MenuBar";
        case "menu item": return "MenuItem";
        case "page tab": return "TabItem";
        case "page tab list": return "Tab";
        case "panel": return "Pane";
        case "password text": return "Edit";
        case "progress bar": return "ProgressBar";
        case "push button": return "Button";
        case "radio button": return "RadioButton";
        case "root pane": return "Pane";
        case "scroll bar": return "ScrollBar";
        case "slider": return "Slider";
        case "table": return "Table";
        case "text": return HasState(states, "editable") ? "Edit" : "Text";
        case "toggle button": return "Button";
        case "tool bar": return "ToolBar";
        case "tree": return "Tree";
        case "tree item": return "TreeItem";
        case "viewport": return "Pane";
        case "window": return "Window";
        default: return "Custom";
      }
    }
  }
}
'@
}

function Get-M2WJavaAccessBridgeCandidates {
    param([int]$ProcessId = 0)
    $paths = [System.Collections.Generic.List[string]]::new()
    if ($ProcessId -gt 0) {
        try {
            $processPath = (Get-Process -Id $ProcessId -ErrorAction Stop).Path
            if ($processPath) {
                $processDirectory = Split-Path -Parent $processPath
                $paths.Add((Join-Path $processDirectory 'WindowsAccessBridge-64.dll'))
                $paths.Add((Join-Path (Split-Path -Parent $processDirectory) 'bin\WindowsAccessBridge-64.dll'))
                $paths.Add((Join-Path (Split-Path -Parent $processDirectory) 'runtime\bin\WindowsAccessBridge-64.dll'))
            }
        }
        catch { }
    }
    if ($env:JAVA_HOME) { $paths.Add((Join-Path $env:JAVA_HOME 'bin\WindowsAccessBridge-64.dll')) }
    try {
        $java = Get-Command java.exe -ErrorAction Stop
        $paths.Add((Join-Path (Split-Path -Parent $java.Source) 'WindowsAccessBridge-64.dll'))
    }
    catch { }
    if ($env:SystemRoot) { $paths.Add((Join-Path $env:SystemRoot 'System32\WindowsAccessBridge-64.dll')) }

    $seen = @{}
    return @($paths | Where-Object {
        $key = $_.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return $false }
        $seen[$key] = $true
        Test-Path -LiteralPath $_ -PathType Leaf
    })
}

function Enable-M2WJavaAccessBridge {
    $switches = [System.Collections.Generic.List[string]]::new()
    if ($env:JAVA_HOME) { $switches.Add((Join-Path $env:JAVA_HOME 'bin\jabswitch.exe')) }
    try { $switches.Add((Get-Command jabswitch.exe -ErrorAction Stop).Source) } catch { }
    try {
        $java = Get-Command java.exe -ErrorAction Stop
        $switches.Add((Join-Path (Split-Path -Parent $java.Source) 'jabswitch.exe'))
    }
    catch { }
    $candidate = $switches | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -Unique -First 1
    if (-not $candidate) {
        return [pscustomobject]@{ Status = 'UNAVAILABLE'; Enabled = $false; Tool = $null; Detail = 'jabswitch.exe was not found.' }
    }
    try {
        $output = & $candidate -enable 2>&1 | Out-String
        return [pscustomobject]@{ Status = 'ENABLED'; Enabled = $true; Tool = $candidate; Detail = $output.Trim() }
    }
    catch {
        return [pscustomobject]@{ Status = 'FAILED'; Enabled = $false; Tool = $candidate; Detail = $_.Exception.Message }
    }
}

function Initialize-M2WJavaAccessBridge {
    param(
        [IntPtr]$WindowHandle = [IntPtr]::Zero,
        [int]$ProcessId = 0,
        [int]$TimeoutSeconds = 4
    )
    Initialize-M2WJavaAccessBridgeTypes
    if (-not $script:M2WJavaBridgeStarted) {
        $errors = [System.Collections.Generic.List[string]]::new()
        foreach ($candidate in @(Get-M2WJavaAccessBridgeCandidates -ProcessId $ProcessId)) {
            try {
                [M2W.JavaAccessBridgeClient]::Start($candidate)
                $script:M2WJavaBridgeStarted = $true
                $script:M2WJavaBridgeDll = $candidate
                break
            }
            catch { $errors.Add("$candidate : $($_.Exception.Message)") }
        }
        if (-not $script:M2WJavaBridgeStarted) {
            $detail = if ($errors.Count) { $errors -join '; ' } else { 'WindowsAccessBridge-64.dll was not found.' }
            return [pscustomobject]@{ Status = 'BLOCKED'; Available = $false; IsJavaWindow = $false; DllPath = $null; Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_UNAVAILABLE'; Detail = $detail }
        }
    }

    $isJavaWindow = $false
    if ($WindowHandle -ne [IntPtr]::Zero) {
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        do {
            [System.Windows.Forms.Application]::DoEvents()
            try { $isJavaWindow = [M2W.JavaAccessBridgeClient]::IsJavaWindow($WindowHandle) } catch { $isJavaWindow = $false }
            if ($isJavaWindow) { break }
            Start-Sleep -Milliseconds 100
        } while ([DateTime]::UtcNow -lt $deadline)
    }
    return [pscustomobject]@{
        Status = $(if ($WindowHandle -eq [IntPtr]::Zero -or $isJavaWindow) { 'READY' } else { 'NOT_JAVA_OR_NOT_ENABLED' })
        Available = $true
        IsJavaWindow = $isJavaWindow
        DllPath = $script:M2WJavaBridgeDll
        Blocker = $(if ($WindowHandle -ne [IntPtr]::Zero -and -not $isJavaWindow) { 'BLOCKED_JAVA_ACCESS_BRIDGE_NOT_ENABLED' } else { $null })
        Detail = $(if ($isJavaWindow) { 'Java window is connected through Java Access Bridge.' } else { 'Bridge loaded, but the target window did not register as accessible Java.' })
    }
}

function Invoke-M2WIsolatedJavaAccessibilitySnapshot {
    param(
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [int]$ProcessId = 0,
        [int]$Limit = 5000,
        [int]$TimeoutSeconds = 8
    )
    $captureScript = Join-Path $PSScriptRoot 'Capture-JavaAccessibility.ps1'
    if (-not (Test-Path -LiteralPath $captureScript -PathType Leaf)) {
        return [pscustomobject]@{
            Status = 'BLOCKED'
            Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_CAPTURE_HELPER_MISSING'
            Detail = "Java accessibility capture helper was not found: $captureScript"
            DllPath = $null
            Nodes = @()
        }
    }

    $outputPath = Join-Path ([IO.Path]::GetTempPath()) ("m2w-java-accessibility-" + [Guid]::NewGuid().ToString('N') + '.json')
    $process = [System.Diagnostics.Process]::new()
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'powershell.exe'
        $startInfo.Arguments = @(
            '-NoProfile'
            '-NonInteractive'
            '-ExecutionPolicy Bypass'
            "-File `"$captureScript`""
            "-ModulePath `"$script:M2WJavaBridgeModulePath`""
            "-WindowHandle $($WindowHandle.ToInt64())"
            "-ProcessId $ProcessId"
            "-Limit $Limit"
            "-OutputPath `"$outputPath`""
        ) -join ' '
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)
        if (-not $completed) {
            try { $process.Kill() } catch { }
            try { [void]$process.WaitForExit(5000) } catch { }
            return [pscustomobject]@{
                Status = 'BLOCKED'
                Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_CAPTURE_TIMEOUT'
                Detail = "Java accessibility capture exceeded the $TimeoutSeconds second evidence deadline."
                DllPath = $null
                Nodes = @()
            }
        }

        $process.WaitForExit()
        $process.Refresh()
        $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
        if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
            try {
                return Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
            }
            catch {
                return [pscustomobject]@{
                    Status = 'BLOCKED'
                    Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_CAPTURE_INVALID'
                    Detail = "Java accessibility capture returned invalid evidence: $($_.Exception.Message)"
                    DllPath = $null
                    Nodes = @()
                }
            }
        }

        $detail = if ($stderr) { $stderr } elseif ($stdout) { $stdout } else { "Capture helper exited with code $($process.ExitCode) without evidence." }
        return [pscustomobject]@{
            Status = 'BLOCKED'
            Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_CAPTURE_FAILED'
            Detail = $detail
            DllPath = $null
            Nodes = @()
        }
    }
    catch {
        return [pscustomobject]@{
            Status = 'BLOCKED'
            Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_CAPTURE_FAILED'
            Detail = $_.Exception.Message
            DllPath = $null
            Nodes = @()
        }
    }
    finally {
        if (Test-Path -LiteralPath $outputPath) {
            Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
        }
        $process.Dispose()
    }
}

function Get-M2WJavaAccessibilitySnapshot {
    param(
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [int]$ProcessId = 0,
        [int]$Limit = 5000,
        [int]$TimeoutSeconds = 8,
        [switch]$InProcess
    )
    if (-not $InProcess) {
        return Invoke-M2WIsolatedJavaAccessibilitySnapshot `
            -WindowHandle $WindowHandle -ProcessId $ProcessId -Limit $Limit -TimeoutSeconds $TimeoutSeconds
    }

    $status = Initialize-M2WJavaAccessBridge -WindowHandle $WindowHandle -ProcessId $ProcessId
    if (-not $status.Available -or -not $status.IsJavaWindow) {
        return [pscustomobject]@{ Status = 'BLOCKED'; Blocker = $status.Blocker; Detail = $status.Detail; DllPath = $status.DllPath; Nodes = @() }
    }
    try {
        $nodes = @([M2W.JavaAccessBridgeClient]::Walk($WindowHandle, $Limit))
        return [pscustomobject]@{ Status = 'READY'; Blocker = $null; Detail = "Captured $($nodes.Count) Java accessible node(s)."; DllPath = $status.DllPath; Nodes = $nodes }
    }
    catch {
        return [pscustomobject]@{ Status = 'BLOCKED'; Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_CAPTURE_FAILED'; Detail = $_.Exception.Message; DllPath = $status.DllPath; Nodes = @() }
    }
}

function Invoke-M2WJavaAccessibleAction {
    param(
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [Parameter(Mandatory)][AllowEmptyCollection()][int[]]$ChildPath,
        [int]$ProcessId = 0,
        [string]$PreferredAction = 'click',
        [int]$TimeoutSeconds = 8,
        [int]$TestDelayMilliseconds = 0,
        [switch]$InProcess
    )
    if (-not $InProcess) {
        return Invoke-M2WIsolatedJavaAccessibleAction `
            -WindowHandle $WindowHandle `
            -ChildPath $ChildPath `
            -ProcessId $ProcessId `
            -PreferredAction $PreferredAction `
            -TimeoutSeconds $TimeoutSeconds `
            -TestDelayMilliseconds $TestDelayMilliseconds
    }

    $status = Initialize-M2WJavaAccessBridge -WindowHandle $WindowHandle -ProcessId $ProcessId
    if (-not $status.Available -or -not $status.IsJavaWindow) {
        return [pscustomobject]@{
            Status = 'BLOCKED'
            Supported = $false
            Action = $null
            AvailableActions = @()
            FailureIndex = -1
            Blocker = $status.Blocker
            Detail = $status.Detail
        }
    }
    try {
        $result = [M2W.JavaAccessBridgeClient]::InvokeAction($WindowHandle, $ChildPath, $PreferredAction)
        return [pscustomobject]@{
            Status = $(if ($result.Success) { 'PASS' } elseif ($result.Supported) { 'FAIL' } else { 'UNAVAILABLE' })
            Supported = $result.Supported
            Action = $result.SelectedAction
            AvailableActions = @($result.AvailableActions)
            FailureIndex = $result.FailureIndex
            Blocker = $(if (-not $result.Success -and $result.Supported) { 'JAVA_ACCESSIBLE_ACTION_FAILED' } else { $null })
            Detail = $result.Detail
        }
    }
    catch {
        return [pscustomobject]@{
            Status = 'FAIL'
            Supported = $true
            Action = $PreferredAction
            AvailableActions = @()
            FailureIndex = -1
            Blocker = 'JAVA_ACCESSIBLE_ACTION_EXCEPTION'
            Detail = $_.Exception.Message
        }
    }
}

function Invoke-M2WIsolatedJavaAccessibleAction {
    param(
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [Parameter(Mandatory)][AllowEmptyCollection()][int[]]$ChildPath,
        [int]$ProcessId = 0,
        [string]$PreferredAction = 'click',
        [int]$TimeoutSeconds = 8,
        [int]$TestDelayMilliseconds = 0
    )
    $actionScript = Join-Path $PSScriptRoot 'Invoke-JavaAccessibilityAction.ps1'
    if (-not (Test-Path -LiteralPath $actionScript -PathType Leaf)) {
        return [pscustomobject]@{
            Status = 'BLOCKED'
            Supported = $false
            Action = $null
            AvailableActions = @()
            FailureIndex = -1
            Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_ACTION_HELPER_MISSING'
            Detail = "Java accessibility action helper was not found: $actionScript"
        }
    }

    $outputPath = Join-Path ([IO.Path]::GetTempPath()) ("m2w-java-action-" + [Guid]::NewGuid().ToString('N') + '.json')
    $childPathCsv = if (@($ChildPath).Count) { @($ChildPath) -join ',' } else { 'root' }
    $process = [System.Diagnostics.Process]::new()
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'powershell.exe'
        $startInfo.Arguments = @(
            '-NoProfile'
            '-NonInteractive'
            '-ExecutionPolicy Bypass'
            "-File `"$actionScript`""
            "-ModulePath `"$script:M2WJavaBridgeModulePath`""
            "-WindowHandle $($WindowHandle.ToInt64())"
            "-ProcessId $ProcessId"
            "-ChildPathCsv `"$childPathCsv`""
            "-PreferredAction `"$PreferredAction`""
            "-OutputPath `"$outputPath`""
            "-TestDelayMilliseconds $TestDelayMilliseconds"
        ) -join ' '
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)
        if (-not $completed) {
            try { $process.Kill() } catch { }
            try { [void]$process.WaitForExit(5000) } catch { }
            return [pscustomobject]@{
                Status = 'BLOCKED'
                Supported = $false
                Action = $null
                AvailableActions = @()
                FailureIndex = -1
                Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_ACTION_TIMEOUT'
                Detail = "Java accessibility action exceeded the $TimeoutSeconds second deadline; its outcome is unknown."
            }
        }

        $process.WaitForExit()
        $process.Refresh()
        $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
        if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
            try {
                return Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
            }
            catch {
                return [pscustomobject]@{
                    Status = 'BLOCKED'
                    Supported = $false
                    Action = $null
                    AvailableActions = @()
                    FailureIndex = -1
                    Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_ACTION_INVALID'
                    Detail = "Java accessibility action returned invalid evidence: $($_.Exception.Message)"
                }
            }
        }

        $detail = if ($stderr) { $stderr } elseif ($stdout) { $stdout } else { "Action helper exited with code $($process.ExitCode) without evidence." }
        return [pscustomobject]@{
            Status = 'BLOCKED'
            Supported = $false
            Action = $null
            AvailableActions = @()
            FailureIndex = -1
            Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_ACTION_FAILED'
            Detail = $detail
        }
    }
    catch {
        return [pscustomobject]@{
            Status = 'BLOCKED'
            Supported = $false
            Action = $null
            AvailableActions = @()
            FailureIndex = -1
            Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_ACTION_FAILED'
            Detail = $_.Exception.Message
        }
    }
    finally {
        if (Test-Path -LiteralPath $outputPath) {
            Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
        }
        $process.Dispose()
    }
}

function Export-M2WJavaAccessibilityTree {
    param(
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [Parameter(Mandatory)][string]$Path,
        [int]$ProcessId = 0,
        [int]$Limit = 5000
    )
    $snapshot = Get-M2WJavaAccessibilitySnapshot -WindowHandle $WindowHandle -ProcessId $ProcessId -Limit $Limit
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $snapshot
}

Export-ModuleMember -Function @(
    'Initialize-M2WJavaAccessBridgeTypes',
    'Get-M2WJavaAccessBridgeCandidates',
    'Enable-M2WJavaAccessBridge',
    'Initialize-M2WJavaAccessBridge',
    'Get-M2WJavaAccessibilitySnapshot',
    'Invoke-M2WJavaAccessibleAction',
    'Export-M2WJavaAccessibilityTree'
)

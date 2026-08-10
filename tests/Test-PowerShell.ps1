Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @(
    Get-ChildItem -LiteralPath (Join-Path $root 'skills\mac-to-windows-testing\scripts\windows-runner') -Include '*.ps1', '*.psm1' -Recurse -File
    Get-Item -LiteralPath (Join-Path $root 'install.ps1')
    Get-Item -LiteralPath (Join-Path $root 'fixtures\windows-ui-fixture\FixtureApp.ps1')
)
$failed = $false
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $failed = $true
        Write-Error "$($file.FullName): $($errors | Out-String)"
    }
}
if ($failed) { exit 1 }

$installRunnerPath = Join-Path $root 'skills\mac-to-windows-testing\scripts\windows-runner\Install-Runner.ps1'
$installRunnerText = Get-Content -LiteralPath $installRunnerPath -Raw -Encoding UTF8
if ($installRunnerText -notmatch '-LogonType\s+Interactive(?:\s|$)') {
    throw 'Interactive runner must use the ScheduledTasks Interactive logon type.'
}
if ($installRunnerText -match '-LogonType\s+InteractiveToken(?:\s|$)') {
    throw 'InteractiveToken is not a valid ScheduledTasks logon type on Windows PowerShell 5.1.'
}

$javaAccessBridgeModule = Join-Path $root 'skills\mac-to-windows-testing\scripts\windows-runner\JavaAccessBridge.psm1'
Import-Module $javaAccessBridgeModule -Force
Initialize-M2WJavaAccessBridgeTypes
if ([M2W.JavaAccessBridgeClient]::ContextInfoSize -ne 6188) {
    throw "Java Access Bridge context layout mismatch: $([M2W.JavaAccessBridgeClient]::ContextInfoSize)"
}
if ([M2W.JavaAccessBridgeClient]::AccessibleActionsSize -ne 131076) {
    throw "Java Access Bridge action-list layout mismatch: $([M2W.JavaAccessBridgeClient]::AccessibleActionsSize)"
}
if ([M2W.JavaAccessBridgeClient]::AccessibleActionsToDoSize -ne 16388) {
    throw "Java Access Bridge action-request layout mismatch: $([M2W.JavaAccessBridgeClient]::AccessibleActionsToDoSize)"
}
if (-not [M2W.JavaAccessBridgeClient].GetMethod('InvokeAction')) {
    throw 'Java Access Bridge accessible actions are unavailable.'
}
$javaSnapshotCommand = Get-Command Get-M2WJavaAccessibilitySnapshot
foreach ($parameterName in @('TimeoutSeconds', 'InProcess')) {
    if (-not $javaSnapshotCommand.Parameters.ContainsKey($parameterName)) {
        throw "Java accessibility snapshot is missing the $parameterName parameter."
    }
}
$captureHelper = Join-Path $root 'skills\mac-to-windows-testing\scripts\windows-runner\Capture-JavaAccessibility.ps1'
if (-not (Test-Path -LiteralPath $captureHelper -PathType Leaf)) {
    throw 'Isolated Java accessibility capture helper is missing.'
}

$javaActionCommand = Get-Command Invoke-M2WJavaAccessibleAction
foreach ($parameterName in @('TimeoutSeconds', 'InProcess')) {
    if (-not $javaActionCommand.Parameters.ContainsKey($parameterName)) {
        throw "Java accessibility action is missing the $parameterName parameter."
    }
}
$actionHelper = Join-Path $root 'skills\mac-to-windows-testing\scripts\windows-runner\Invoke-JavaAccessibilityAction.ps1'
if (-not (Test-Path -LiteralPath $actionHelper -PathType Leaf)) {
    throw 'Isolated Java accessibility action helper is missing.'
}
$actionTimeoutStart = Get-Date
$timeoutAction = Invoke-M2WJavaAccessibleAction `
    -WindowHandle ([IntPtr]::Zero) -ChildPath ([int[]]@()) -TimeoutSeconds 1 `
    -TestDelayMilliseconds 1800
if ($timeoutAction.Blocker -ne 'BLOCKED_JAVA_ACCESS_BRIDGE_ACTION_TIMEOUT') {
    throw "Java accessibility action did not return the timeout blocker: $($timeoutAction.Blocker)"
}
if (((Get-Date) - $actionTimeoutStart).TotalSeconds -gt 5) {
    throw 'Java accessibility action timeout exceeded its bounded shutdown allowance.'
}
$timeoutStart = Get-Date
$timeoutSnapshot = Get-M2WJavaAccessibilitySnapshot `
    -WindowHandle ([IntPtr]::Zero) -TimeoutSeconds 1 -TestDelayMilliseconds 1800
if ($timeoutSnapshot.Blocker -ne 'BLOCKED_JAVA_ACCESS_BRIDGE_CAPTURE_TIMEOUT') {
    throw "Java accessibility capture did not return the timeout blocker: $($timeoutSnapshot.Blocker)"
}
if (((Get-Date) - $timeoutStart).TotalSeconds -gt 5) {
    throw 'Java accessibility capture timeout exceeded its bounded shutdown allowance.'
}

$uiAutomationModule = Import-Module (Join-Path $root 'skills\mac-to-windows-testing\scripts\windows-runner\WindowsUiAutomation.psm1') -Force -PassThru
Initialize-M2WUiAutomation
if (-not [M2W.NativeMethods].GetMethod('SetForegroundWindow')) { throw 'Native foreground activation is unavailable.' }
if (-not [M2W.NativeMethods].GetMethod('ShowWindowAsync')) { throw 'Native window restore is unavailable.' }
if (-not [M2W.NativeMethods].GetMethod('ActivateWindow')) { throw 'Foreground-thread window activation is unavailable.' }
if (-not [M2W.WindowActivationV1].GetMethod('ActivateWindow')) { throw 'Versioned window activation is unavailable.' }
if (-not [M2W.WindowActivationV2].GetMethod('ActivateWindowAtPoint')) { throw 'Point-verified window activation is unavailable.' }
if (-not [M2W.WindowEnumerationV1].GetMethod('GetVisibleWindows')) { throw 'Bounded native window enumeration is unavailable.' }
$nativeWindowFixture = [pscustomobject]@{
    Width = 420
    Height = 240
    Title = 'M2W expected dialog'
}
$expectedNativeTarget = [pscustomobject]@{
    name = 'M2W expected dialog'
    controlType = 'Window'
}
$unrelatedNativeTarget = [pscustomobject]@{
    name = 'M2W unrelated dialog'
    controlType = 'Window'
}
$expectedNativeMatch = & $uiAutomationModule {
    param($Window, $Target)
    Test-M2WNativeWindowCandidate -Window $Window -Target $Target
} $nativeWindowFixture $expectedNativeTarget
$unrelatedNativeMatch = & $uiAutomationModule {
    param($Window, $Target)
    Test-M2WNativeWindowCandidate -Window $Window -Target $Target
} $nativeWindowFixture $unrelatedNativeTarget
if (-not $expectedNativeMatch) { throw 'Native exact-name window matching rejected the expected dialog.' }
if ($unrelatedNativeMatch) { throw 'Native exact-name window matching accepted an unrelated dialog.' }
$topLevelForm = [System.Windows.Forms.Form]::new()
$topLevelForm.Text = 'M2W top-level discovery fixture'
$topLevelForm.Width = 420
$topLevelForm.Height = 240
try {
    $topLevelForm.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $topLevelMatch = Find-M2WTopLevelWindow -Target ([pscustomobject]@{
        name = 'M2W top-level discovery fixture'
        controlType = 'Window'
    }) -TimeoutSeconds 3
    if (-not $topLevelMatch) { throw 'Top-level window discovery did not find the visible fixture form.' }
    $nativeTopLevelMatch = @([M2W.WindowEnumerationV1]::GetVisibleWindows($PID) | Where-Object {
        $_.Handle -eq $topLevelForm.Handle.ToInt64()
    })
    if ($nativeTopLevelMatch.Count -ne 1) { throw 'Native window enumeration did not find the visible fixture form.' }
    $fixturePoint = $topLevelForm.PointToScreen([System.Drawing.Point]::new(40, 40))
    if (-not [M2W.WindowActivationV2]::ActivateWindowAtPoint($topLevelForm.Handle, $fixturePoint.X, $fixturePoint.Y)) {
        throw 'Point-verified window activation did not surface the visible fixture form.'
    }
}
finally {
    $topLevelForm.Close()
    $topLevelForm.Dispose()
}
$first = [System.Windows.Rect]::new(0, 0, 100, 100)
$second = [System.Windows.Rect]::new(50, 50, 100, 100)
if ((Get-M2WRectOverlapArea -First $first -Second $second) -ne 2500) { throw 'Overlap geometry test failed.' }
if (-not (Test-M2WRectContained -Child ([System.Windows.Rect]::new(10, 10, 20, 20)) -Parent $first)) { throw 'Containment test failed.' }
if (-not (Test-M2WDangerousTarget -Target ([pscustomobject]@{ name = 'Delete account' }))) { throw 'Danger classifier test failed.' }
$deleteAccountChinese = -join ([char]0x5220, [char]0x9664, [char]0x8d26, [char]0x6237)
if (-not (Test-M2WDangerousTarget -Target ([pscustomobject]@{ name = $deleteAccountChinese }))) { throw 'Localized danger classifier test failed.' }
if (Test-M2WDangerousTarget -Target ([pscustomobject]@{ name = 'Open settings' })) { throw 'Safe control was misclassified.' }
if (-not (Test-M2WTargetName -ActualName 'LizzieYzy Next - sample.sgf' -Target ([pscustomobject]@{ nameContains = 'lizzieyzy next' }))) { throw 'Case-insensitive nameContains failed.' }
if (-not (Test-M2WTargetName -ActualName 'LizzieYzy Next next-2026.08' -Target ([pscustomobject]@{ nameRegex = '^LizzieYzy Next' }))) { throw 'nameRegex failed.' }
if (Test-M2WTargetName -ActualName 'Unrelated App' -Target ([pscustomobject]@{ nameContains = 'LizzieYzy Next' })) { throw 'nameContains accepted an unrelated window.' }
$javaTarget = [pscustomobject]@{ name = 'One-click setup'; controlType = 'Button' }
$visibleJavaNode = [pscustomobject]@{ Name = 'One-click setup'; ControlType = 'Button'; Offscreen = $false; Width = 120; Height = 30 }
$hiddenJavaNode = [pscustomobject]@{ Name = 'One-click setup'; ControlType = 'Button'; Offscreen = $true; Width = -1; Height = -1 }
$visibleMatched = & $uiAutomationModule { param($node, $target) Test-M2WJavaNodeTarget -Node $node -Target $target } $visibleJavaNode $javaTarget
$hiddenMatched = & $uiAutomationModule { param($node, $target) Test-M2WJavaNodeTarget -Node $node -Target $target } $hiddenJavaNode $javaTarget
$hiddenDiagnosticMatched = & $uiAutomationModule { param($node, $target) Test-M2WJavaNodeTarget -Node $node -Target $target } $hiddenJavaNode ([pscustomobject]@{ name = 'One-click setup'; controlType = 'Button'; includeOffscreen = $true })
if (-not $visibleMatched) { throw 'Visible Java control did not match its selector.' }
if ($hiddenMatched) { throw 'Hidden Java control unexpectedly matched the default selector.' }
if (-not $hiddenDiagnosticMatched) { throw 'Explicit offscreen Java diagnostic selector did not match.' }
$missingChildPath = & $uiAutomationModule { Get-M2WJavaChildPath -Node ([pscustomobject]@{ Name = 'Legacy node' }) }
$validChildPath = & $uiAutomationModule { Get-M2WJavaChildPath -Node ([pscustomobject]@{ ChildPath = @(1, 3, 5) }) }
$emptyChildPath = & $uiAutomationModule { Get-M2WJavaChildPath -Node ([pscustomobject]@{ ChildPath = @() }) }
if ($missingChildPath.Available) { throw 'A legacy Java node without ChildPath was marked action-capable.' }
if (-not $validChildPath.Available -or (@($validChildPath.Path) -join ',') -ne '1,3,5') { throw 'Java child path normalization failed.' }
if (-not $emptyChildPath.Available -or @($emptyChildPath.Path).Count -ne 0) { throw 'An explicit Java root child path was rejected.' }
$workArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$physicalJavaNode = [pscustomobject]@{ Offscreen = $false; X = $workArea.Left + 20; Y = $workArea.Top + 20; Width = 120; Height = 32 }
$offscreenJavaNode = [pscustomobject]@{ Offscreen = $true; X = $workArea.Left + 20; Y = $workArea.Top + 20; Width = 120; Height = 32 }
$taskbarOccludedJavaNode = [pscustomobject]@{ Offscreen = $false; X = $workArea.Left + 20; Y = $workArea.Bottom - 10; Width = 120; Height = 32 }
$physicalJavaClick = & $uiAutomationModule { param($node) Test-M2WJavaPhysicalClickAvailable -WindowHandle ([IntPtr]::new(1)) -Node $node } $physicalJavaNode
$offscreenJavaClick = & $uiAutomationModule { param($node) Test-M2WJavaPhysicalClickAvailable -WindowHandle ([IntPtr]::new(1)) -Node $node } $offscreenJavaNode
$taskbarOccludedJavaClick = & $uiAutomationModule { param($node) Test-M2WJavaPhysicalClickAvailable -WindowHandle ([IntPtr]::new(1)) -Node $node } $taskbarOccludedJavaNode
$missingHandleJavaClick = & $uiAutomationModule { param($node) Test-M2WJavaPhysicalClickAvailable -WindowHandle ([IntPtr]::Zero) -Node $node } $physicalJavaNode
if (-not $physicalJavaClick) { throw 'A visible Java control with a native window was not eligible for physical clicking.' }
if ($offscreenJavaClick) { throw 'An offscreen Java control was eligible for physical clicking.' }
if ($taskbarOccludedJavaClick) { throw 'A Java control extending under the taskbar was eligible for physical clicking.' }
if ($missingHandleJavaClick) { throw 'A Java control without a native window was eligible for physical clicking.' }
$winFormsButton = [pscustomobject]@{ ControlType = 'Pane'; ClassName = 'WindowsForms10.BUTTON.app.0.test' }
$winFormsLabel = [pscustomobject]@{ ControlType = 'Pane'; ClassName = 'WindowsForms10.STATIC.app.0.test' }
if ((Get-M2WEffectiveUiControlType -Node $winFormsButton) -ne 'Button') { throw 'WinForms button type normalization failed.' }
if ((Get-M2WEffectiveUiControlType -Node $winFormsLabel) -ne 'Pane') { throw 'WinForms static text was incorrectly classified as actionable.' }

$settingsNode = [pscustomobject]@{ Name = 'Open settings'; ControlType = 'Button'; Dangerous = $false; Enabled = $true; Offscreen = $false }
$paymentNode = [pscustomobject]@{ Name = 'Pay now'; ControlType = 'Button'; Dangerous = $true; Enabled = $true; Offscreen = $false }
$unknownNode = [pscustomobject]@{ Name = 'Launch mystery'; ControlType = 'Button'; Dangerous = $false; Enabled = $true; Offscreen = $false }
if ((Get-M2WSafeControlCategory -Node $settingsNode) -ne 'dialog') { throw 'Safe settings control was not classified.' }
if (Get-M2WSafeControlCategory -Node $paymentNode) { throw 'Dangerous control was classified as safe.' }
if (Get-M2WSafeControlCategory -Node $unknownNode) { throw 'Unknown control was classified as safe.' }

$auditRoot = Join-Path ([IO.Path]::GetTempPath()) ("m2w-audit-" + [Guid]::NewGuid().ToString('N'))
try {
    $graph = [pscustomobject]@{
        Root = [pscustomobject]@{ ClassName = 'FixtureWindow'; Bounds = [pscustomobject]@{ X = 0; Y = 0; Width = 300; Height = 200 } }
        Providers = [pscustomobject]@{ JavaAccessBridge = [pscustomobject]@{ Status = 'UNAVAILABLE'; Actionable = 0 } }
        Nodes = @(
            [pscustomobject]@{ Id = 'missing'; Provider = 'UIAutomation'; Parent = 'root'; Name = ''; ControlType = 'Button'; Offscreen = $false; Bounds = [pscustomobject]@{ X = 10; Y = 10; Width = 80; Height = 30 } },
            [pscustomobject]@{ Id = 'overlap-a'; Provider = 'UIAutomation'; Parent = 'root'; Name = 'A'; ControlType = 'Button'; Offscreen = $false; Bounds = [pscustomobject]@{ X = 100; Y = 20; Width = 80; Height = 40 } },
            [pscustomobject]@{ Id = 'overlap-b'; Provider = 'UIAutomation'; Parent = 'root'; Name = 'B'; ControlType = 'Button'; Offscreen = $false; Bounds = [pscustomobject]@{ X = 140; Y = 30; Width = 80; Height = 40 } },
            [pscustomobject]@{ Id = 'outside'; Provider = 'UIAutomation'; Parent = 'root'; Name = 'Outside'; ControlType = 'Button'; Offscreen = $false; Bounds = [pscustomobject]@{ X = 280; Y = 160; Width = 60; Height = 50 } },
            [pscustomobject]@{ Id = 'spinner-edit'; Provider = 'UIAutomation'; Parent = 'spinner'; Name = 'Komi'; ControlType = 'Edit'; Offscreen = $false; Bounds = [pscustomobject]@{ X = 210; Y = 80; Width = 72; Height = 28 } },
            [pscustomobject]@{ Id = 'spinner-up'; Provider = 'UIAutomation'; Parent = 'spinner'; Name = 'Increase'; ControlType = 'Button'; Offscreen = $false; Bounds = [pscustomobject]@{ X = 262; Y = 78; Width = 22; Height = 16 } },
            [pscustomobject]@{ Id = 'spinner-down'; Provider = 'UIAutomation'; Parent = 'spinner'; Name = 'Decrease'; ControlType = 'Button'; Offscreen = $false; Bounds = [pscustomobject]@{ X = 262; Y = 93; Width = 22; Height = 16 } }
        )
    }
    $auditPath = Join-Path $auditRoot 'audit.json'
    $audit = Export-M2WDeterministicAudit -Graph $graph -Path $auditPath -FailOn @('OUTSIDE_WINDOW', 'ACTIONABLE_OVERLAP')
    $codes = @($audit.Findings | Select-Object -ExpandProperty Code)
    foreach ($expected in @('MISSING_ACCESSIBLE_NAME', 'OUTSIDE_WINDOW', 'ACTIONABLE_OVERLAP')) {
        if ($codes -notcontains $expected) { throw "Deterministic audit missed $expected." }
    }
    $spinnerFindings = @($audit.Findings | Where-Object {
        $_.NodeId -like 'spinner-*' -or $_.OtherNodeId -like 'spinner-*'
    })
    if ($spinnerFindings.Count) { throw 'Spinner buttons were reported as ordinary actionable overlap.' }
    if ($audit.Status -ne 'FAIL') { throw 'Configured deterministic audit findings did not fail.' }
}
finally {
    Remove-Item -LiteralPath $auditRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$probeInfo = [System.Diagnostics.ProcessStartInfo]::new()
$probeInfo.FileName = 'cmd.exe'
$probeInfo.Arguments = '/d /c "echo probe-output & exit 7"'
$probeInfo.UseShellExecute = $false
$probeInfo.CreateNoWindow = $true
$probeInfo.RedirectStandardOutput = $true
$probeInfo.RedirectStandardError = $true
$exitProbe = [System.Diagnostics.Process]::new()
$exitProbe.StartInfo = $probeInfo
[void]$exitProbe.Start()
$probeOutput = $exitProbe.StandardOutput.ReadToEndAsync()
$probeError = $exitProbe.StandardError.ReadToEndAsync()
if (-not $exitProbe.WaitForExit(10000)) { throw 'Redirected process exit-code probe timed out.' }
$exitProbe.WaitForExit()
$exitProbe.Refresh()
if ($exitProbe.ExitCode -ne 7) { throw 'Redirected process exit code was not synchronized.' }
if ($probeOutput.GetAwaiter().GetResult().Trim() -ne 'probe-output') { throw 'Redirected stdout was not captured.' }
if ($probeError.GetAwaiter().GetResult()) { throw 'Redirected stderr was unexpectedly populated.' }

$trustRoot = Join-Path ([IO.Path]::GetTempPath()) ("m2w-trust-" + [Guid]::NewGuid().ToString('N'))
try {
    $trustScript = Join-Path $root 'skills\mac-to-windows-testing\scripts\windows-runner\Trust-Profile.ps1'
    $firstSha = 'a' * 64
    $secondSha = 'b' * 64
    & $trustScript -RunnerRoot $trustRoot -ProfileSha256 $firstSha -Repository 'https://example.test/one' | Out-Null
    & $trustScript -RunnerRoot $trustRoot -ProfileSha256 $secondSha -Repository 'https://example.test/two' | Out-Null
    $trustedProfiles = Get-Content -LiteralPath (Join-Path $trustRoot 'trusted-profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($trustedProfiles).Count -ne 2) { throw 'Trusted profile registry did not retain two flat entries.' }
    if (@($trustedProfiles | Where-Object { -not $_.PSObject.Properties['profileSha256'] }).Count) { throw 'Trusted profile registry contains a wrapped or invalid entry.' }
}
finally {
    Remove-Item -LiteralPath $trustRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "Validated $($files.Count) PowerShell files."

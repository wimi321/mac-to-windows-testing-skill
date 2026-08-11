param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$RunnerRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WindowsUiAutomation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'RunnerCommand.psm1') -Force

function Write-JsonFile {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$LogPath,
        [int]$TimeoutSeconds = 1800
    )
    $start = Get-Date
    $stdout = "$LogPath.stdout.log"
    $stderr = "$LogPath.stderr.log"
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'cmd.exe'
    $startInfo.Arguments = ConvertTo-M2WCmdArguments -Command $Command
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) {
        Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID', [string]$process.Id, '/T', '/F') -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
        try { $process.WaitForExit() } catch { }
    }

    $stdoutText = $stdoutTask.GetAwaiter().GetResult()
    $stderrText = $stderrTask.GetAwaiter().GetResult()
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($stdout, $stdoutText, $utf8)
    [IO.File]::WriteAllText($stderr, $stderrText, $utf8)

    if (-not $completed) {
        return [pscustomobject]@{ Name = $Name; Status = 'FAIL'; ExitCode = $null; TimedOut = $true; DurationMs = [int]((Get-Date) - $start).TotalMilliseconds; Stdout = $stdout; Stderr = $stderr }
    }
    $process.Refresh()
    $exitCode = $process.ExitCode
    return [pscustomobject]@{ Name = $Name; Status = $(if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }); ExitCode = $exitCode; TimedOut = $false; DurationMs = [int]((Get-Date) - $start).TotalMilliseconds; Stdout = $stdout; Stderr = $stderr }
}

function Test-TrustedManifest {
    param($Manifest, [string]$Root)
    $trustPath = Join-Path $Root 'trusted-profiles.json'
    if (-not (Test-Path -LiteralPath $trustPath)) { return $false }
    try { $parsed = Get-Content -LiteralPath $trustPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $false }
    $trusted = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in @($parsed)) {
        if ($candidate.PSObject.Properties['profileSha256']) {
            $trusted.Add($candidate)
        }
        elseif ($candidate.PSObject.Properties['value']) {
            foreach ($nested in @($candidate.value)) {
                if ($nested.PSObject.Properties['profileSha256']) { $trusted.Add($nested) }
            }
        }
    }
    return [bool]($trusted | Where-Object { [string]$_.profileSha256 -eq [string]$Manifest.profileSha256 })
}

function Save-StepEvidence {
    param(
        [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Window,
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$ScenarioId,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)]$StepResult
    )
    # A successful close invalidates the AutomationElement by design. Earlier checkpoints
    # already contain the visual evidence, so probing the disposed element only creates a
    # misleading EvidenceError.
    if ([string]$StepResult.Action -eq 'close') { return }
    $prefix = '{0:D2}' -f $Index
    $shot = Join-Path $RunDirectory "screenshots\$ScenarioId-$prefix.png"
    $tree = Join-Path $RunDirectory "ui-trees\$ScenarioId-$prefix.json"
    try {
        Save-M2WScreenshot -Path $shot -Window $Window | Out-Null
        $trees = Export-M2WAccessibleTrees -Root $Window -UiAutomationPath $tree
        $focusedName = ''
        try {
            $focusedElement = [System.Windows.Automation.AutomationElement]::FocusedElement
            if ($focusedElement) { $focusedName = [string]$focusedElement.Current.Name }
        }
        catch { }
        $StepResult | Add-Member -NotePropertyName Evidence -NotePropertyValue ([pscustomobject]@{
            Screenshot = $shot
            UiTree = $tree
            JavaUiTree = $trees.JavaAccessBridgePath
            AccessibilityProviders = [pscustomobject]@{
                UIAutomationNodes = @($trees.UiAutomationNodes).Count
                JavaAccessBridgeStatus = $trees.JavaAccessBridge.Status
                JavaAccessBridgeNodes = @($trees.JavaAccessBridge.Nodes).Count
                JavaAccessBridgeBlocker = $trees.JavaAccessBridge.Blocker
            }
            Focused = $focusedName
            CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
        }) -Force
    }
    catch {
        $StepResult | Add-Member -NotePropertyName EvidenceError -NotePropertyValue $_.Exception.Message -Force
    }
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runId = [string]$manifest.runId
$runDirectory = Join-Path $RunnerRoot "runs\$runId"
$resultPath = Join-Path $runDirectory 'result.json'
[IO.Directory]::CreateDirectory($runDirectory) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $runDirectory 'logs')) | Out-Null

$result = [ordered]@{
    schemaVersion = 1
    runId = $runId
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    status = 'BLOCKED'
    blocker = $null
    visualConfidenceThreshold = [double]$manifest.automation.visualConfidenceThreshold
    profileSha256 = [string]$manifest.profileSha256
    repair = $manifest.repair
    completionEligible = $false
    source = $manifest.source
    redaction = $manifest.redaction
    environment = $null
    commands = @()
    scenarios = @()
}
$launchProcess = $null
$applicationProcessIds = [System.Collections.Generic.HashSet[int]]::new()

try {
    Copy-Item -LiteralPath $ManifestPath -Destination (Join-Path $runDirectory 'manifest.json') -Force
    if (-not (Test-TrustedManifest -Manifest $manifest -Root $RunnerRoot)) {
        $result.blocker = 'BLOCKED_UNTRUSTED_PROFILE'
        return
    }

    $result.environment = Get-M2WEnvironment
    Write-JsonFile -Value $result.environment -Path (Join-Path $runDirectory 'environment.json')
    if ($result.environment.Session.Status -ne 'READY') {
        $result.blocker = $result.environment.Session.Blocker
        return
    }

    $workspace = [Environment]::ExpandEnvironmentVariables([string]$manifest.project.windowsWorkspace)
    if (-not (Test-Path -LiteralPath $workspace)) {
        $result.blocker = 'BLOCKED_WINDOWS_WORKSPACE_MISSING'
        return
    }

    foreach ($name in @('build', 'test')) {
        $logBase = Join-Path $runDirectory "logs\$name"
        $commandResult = Invoke-LoggedCommand -Name $name -Command ([string]$manifest.commands.$name) -WorkingDirectory $workspace -LogPath $logBase
        $result.commands += $commandResult
        if ($commandResult.Status -ne 'PASS') {
            $result.status = 'FAIL'
            return
        }
    }

    $artifact = [Environment]::ExpandEnvironmentVariables([string]$manifest.project.artifact)
    if (-not [IO.Path]::IsPathRooted($artifact)) { $artifact = Join-Path $workspace $artifact }
    if (-not (Test-Path -LiteralPath $artifact)) {
        $result.status = 'FAIL'
        $result.commands += [pscustomobject]@{ Name = 'artifact'; Status = 'FAIL'; Path = $artifact; Summary = 'Declared packaged artifact was not found.' }
        return
    }
    $result.commands += [pscustomobject]@{ Name = 'artifact'; Status = 'PASS'; Path = $artifact }

    $launchLog = Join-Path $runDirectory 'logs\launch'
    $launchProcess = Start-Process -FilePath 'cmd.exe' -ArgumentList (ConvertTo-M2WCmdArguments -Command ([string]$manifest.commands.launch)) `
        -WorkingDirectory $workspace -RedirectStandardOutput "$launchLog.stdout.log" -RedirectStandardError "$launchLog.stderr.log" -PassThru
    Start-Sleep -Milliseconds 750
    if ($launchProcess.HasExited -and $launchProcess.ExitCode -ne 0) {
        $result.status = 'FAIL'
        $result.commands += [pscustomobject]@{ Name = 'launch'; Status = 'FAIL'; ExitCode = $launchProcess.ExitCode; Stdout = "$launchLog.stdout.log"; Stderr = "$launchLog.stderr.log" }
        return
    }
    $result.commands += [pscustomobject]@{ Name = 'launch'; Status = 'PASS'; ExitCode = $null; Stdout = "$launchLog.stdout.log"; Stderr = "$launchLog.stderr.log" }

    $hasFailure = $false
    $hasBlocker = $false
    foreach ($scenario in @($manifest.scenarios)) {
        $scenarioResult = [ordered]@{ id = [string]$scenario.id; title = [string]$scenario.title; status = 'PASS'; summary = ''; steps = @() }
        $windowTarget = $scenario.window
        if (-not $windowTarget.PSObject.Properties['controlType']) {
            $windowTarget | Add-Member -NotePropertyName controlType -NotePropertyValue 'Window'
        }
        $window = Find-M2WTopLevelWindow -Target $windowTarget -TimeoutSeconds 20
        if (-not $window) {
            $scenarioResult.status = 'FAIL'
            $scenarioResult.summary = 'Expected application window was not found.'
            $hasFailure = $true
            $result.scenarios += [pscustomobject]$scenarioResult
            continue
        }
        try { [void]$applicationProcessIds.Add([int]$window.Current.ProcessId) } catch { }

        try {
            Save-M2WScreenshot -Path (Join-Path $runDirectory "screenshots\$($scenario.id)-00-fullscreen.png") -FullScreen | Out-Null
        }
        catch { }

        $index = 0
        foreach ($step in @($scenario.steps)) {
            $index++
            $stepResult = Invoke-M2WStep -Step $step -Window $window -RunDirectory $runDirectory -ScenarioId $scenario.id -Index $index -AllowDestructiveActions:([bool]$manifest.automation.allowDestructiveActions)
            Save-StepEvidence -Window $window -RunDirectory $runDirectory -ScenarioId $scenario.id -Index $index -StepResult $stepResult
            $scenarioResult.steps += $stepResult
            if ($stepResult.Status -eq 'FAIL') { $scenarioResult.status = 'FAIL'; $hasFailure = $true; break }
            if ($stepResult.Status -eq 'BLOCKED') { $scenarioResult.status = 'BLOCKED'; $scenarioResult.summary = $stepResult.Blocker; $hasBlocker = $true; break }
        }
        if (-not $scenarioResult.summary) {
            $scenarioResult.summary = if ($scenarioResult.status -eq 'PASS') { 'Deterministic UI steps completed; visual review required.' } else { 'Scenario did not complete.' }
        }
        $result.scenarios += [pscustomobject]$scenarioResult
    }

    $result['processes'] = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object {
        [pscustomobject]@{
            Name = $_.ProcessName
            Id = $_.Id
            SessionId = $_.SessionId
            MainWindowTitle = $_.MainWindowTitle
            Responding = $_.Responding
            WorkingSet64 = $_.WorkingSet64
        }
    })

    if ($hasFailure) { $result.status = 'FAIL' }
    elseif ($hasBlocker) { $result.status = 'BLOCKED'; $result.blocker = 'BLOCKED_SCENARIO' }
    else { $result.status = 'PENDING_AI_REVIEW' }
}
catch {
    $result.status = 'FAIL'
    $result.blocker = $null
    $result['error'] = $_.Exception.Message
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $runDirectory 'logs\runner-error.log') -Encoding UTF8
}
finally {
    $keepRunning = [bool](Get-M2WValue -Object $manifest.automation -Name 'keepApplicationRunning' -Default $false)
    if (-not $keepRunning) {
        foreach ($processId in $applicationProcessIds) {
            if ($processId -gt 0) {
                Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID', [string]$processId, '/T', '/F') -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
            }
        }
        if ($launchProcess -and -not $launchProcess.HasExited) {
            Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID', [string]$launchProcess.Id, '/T', '/F') -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
        }
    }
    $result['finishedAt'] = (Get-Date).ToUniversalTime().ToString('o')
    Write-JsonFile -Value $result -Path $resultPath
}

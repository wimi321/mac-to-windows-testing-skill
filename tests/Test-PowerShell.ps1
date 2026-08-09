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

Import-Module (Join-Path $root 'skills\mac-to-windows-testing\scripts\windows-runner\WindowsUiAutomation.psm1') -Force
Initialize-M2WUiAutomation
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
    [IO.Directory]::CreateDirectory($trustRoot) | Out-Null
    '[]' | Set-Content -LiteralPath (Join-Path $trustRoot 'trusted-profiles.json') -Encoding UTF8
    $trustScript = Join-Path $root 'skills\mac-to-windows-testing\scripts\windows-runner\Trust-Profile.ps1'
    $firstSha = 'a' * 64
    $secondSha = 'b' * 64
    & $trustScript -RunnerRoot $trustRoot -ProfileSha256 $firstSha -Repository 'https://example.test/one' | Out-Null
    & $trustScript -RunnerRoot $trustRoot -ProfileSha256 $secondSha -Repository 'https://example.test/two' | Out-Null
    $trustedProfiles = Get-Content -LiteralPath (Join-Path $trustRoot 'trusted-profiles.json') -Raw | ConvertFrom-Json
    if (@($trustedProfiles).Count -ne 2) { throw 'Trusted profile registry did not retain two flat entries.' }
    if (@($trustedProfiles | Where-Object { -not $_.PSObject.Properties['profileSha256'] }).Count) { throw 'Trusted profile registry contains a wrapped or invalid entry.' }
}
finally {
    Remove-Item -LiteralPath $trustRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "Validated $($files.Count) PowerShell files."

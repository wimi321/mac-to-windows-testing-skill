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
if (Test-M2WDangerousTarget -Target ([pscustomobject]@{ name = 'Open settings' })) { throw 'Safe control was misclassified.' }

Write-Output "Validated $($files.Count) PowerShell files."

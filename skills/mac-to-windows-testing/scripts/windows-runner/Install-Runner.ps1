param([Parameter(Mandatory = $true)][string]$RunnerRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'Mac-to-Windows Testing Skill Runner'
[IO.Directory]::CreateDirectory($RunnerRoot) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $RunnerRoot 'queue')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $RunnerRoot 'incoming')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $RunnerRoot 'runs')) | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $RunnerRoot 'trusted-profiles.json'))) {
    '[]' | Set-Content -LiteralPath (Join-Path $RunnerRoot 'trusted-profiles.json') -Encoding UTF8
}
$worker = Join-Path $RunnerRoot 'runner\Worker.ps1'
if (-not (Test-Path -LiteralPath $worker)) { throw "Runner worker not found: $worker" }
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$worker`" -RunnerRoot `"$RunnerRoot`""
$principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType InteractiveToken -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 4) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
[pscustomobject]@{ status = 'INSTALLED'; task = $taskName; root = $RunnerRoot; user = $principal.UserId } | ConvertTo-Json -Compress

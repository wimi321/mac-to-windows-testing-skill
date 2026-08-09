param([Parameter(Mandatory = $true)][string]$RunnerRoot)

$taskName = 'Mac-to-Windows Testing Skill Runner'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
$session = $null
try {
    Import-Module (Join-Path $PSScriptRoot 'WindowsUiAutomation.psm1') -Force
    $session = Get-M2WSessionState
}
catch { $session = [pscustomobject]@{ Status = 'UNKNOWN'; Blocker = $_.Exception.Message } }
[pscustomobject]@{
    status = $(if ($task) { 'INSTALLED' } else { 'NOT_INSTALLED' })
    taskState = $(if ($task) { [string]$task.State } else { $null })
    root = $RunnerRoot
    session = $session
} | ConvertTo-Json -Depth 6 -Compress
if (-not $task) { exit 2 }

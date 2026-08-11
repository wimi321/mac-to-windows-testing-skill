param(
    [Parameter(Mandatory = $true)][string]$RunnerRoot,
    [Parameter(Mandatory = $true)][string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'Mac-to-Windows Testing Skill Runner'
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) { throw 'Interactive runner is not installed.' }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$destination = Join-Path $RunnerRoot "queue\$($manifest.runId).json"
Copy-Item -LiteralPath $ManifestPath -Destination $destination -Force
Start-ScheduledTask -TaskName $taskName
[pscustomobject]@{ status = 'SUBMITTED'; runId = $manifest.runId; manifest = $destination } | ConvertTo-Json -Compress

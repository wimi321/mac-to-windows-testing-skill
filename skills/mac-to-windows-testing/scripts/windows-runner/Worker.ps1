param([Parameter(Mandatory = $true)][string]$RunnerRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$queue = Join-Path $RunnerRoot 'queue'
[IO.Directory]::CreateDirectory($queue) | Out-Null
$lockPath = Join-Path $RunnerRoot 'runner.lock'
$lock = $null
try {
    $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    foreach ($item in Get-ChildItem -LiteralPath $queue -Filter '*.json' -File | Sort-Object CreationTimeUtc) {
        $processing = "$($item.FullName).processing"
        Move-Item -LiteralPath $item.FullName -Destination $processing -Force
        try {
            & (Join-Path $PSScriptRoot 'Invoke-MacToWindowsTest.ps1') -ManifestPath $processing -RunnerRoot $RunnerRoot
        }
        finally {
            Remove-Item -LiteralPath $processing -Force -ErrorAction SilentlyContinue
        }
    }
}
finally {
    if ($lock) { $lock.Dispose() }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}

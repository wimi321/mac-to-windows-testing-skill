param([Parameter(Mandatory = $true)][string]$RunnerRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'Mac-to-Windows Testing Skill Runner'
$localAppData = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
$resolvedRoot = [IO.Path]::GetFullPath($RunnerRoot).TrimEnd('\')
if (-not $resolvedRoot.StartsWith($localAppData + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to remove a runner directory outside LOCALAPPDATA.'
}
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
[pscustomobject]@{ status = 'UNINSTALLED'; task = $taskName; root = $RunnerRoot } | ConvertTo-Json -Compress
$escaped = $resolvedRoot.Replace('"', '""')
Start-Process -FilePath 'cmd.exe' -WindowStyle Hidden -ArgumentList @(
    '/d', '/s', '/c', "timeout /t 2 /nobreak >nul & rmdir /s /q `"$escaped`""
) | Out-Null

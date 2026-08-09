param(
    [ValidateSet('all', 'codex', 'claude', 'opencode', 'copilot', 'agents')]
    [string]$Target = 'all'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $root 'skills\mac-to-windows-testing'
if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md'))) {
    throw "Skill source is incomplete: $source"
}

$map = [ordered]@{
    codex = Join-Path $HOME '.codex\skills\mac-to-windows-testing'
    claude = Join-Path $HOME '.claude\skills\mac-to-windows-testing'
    opencode = Join-Path $HOME '.config\opencode\skills\mac-to-windows-testing'
    copilot = Join-Path $HOME '.copilot\skills\mac-to-windows-testing'
    agents = Join-Path $HOME '.agents\skills\mac-to-windows-testing'
}
$targets = if ($Target -eq 'all') { @($map.Values) } else { @($map[$Target]) }

foreach ($destination in $targets) {
    $parent = Split-Path -Parent $destination
    $temp = Join-Path $parent ".mac-to-windows-testing.tmp.$PID"
    $backup = Join-Path $parent ".mac-to-windows-testing.backup.$PID"
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    Copy-Item -LiteralPath $source -Destination $temp -Recurse -Force
    if (Test-Path -LiteralPath $destination) { Move-Item -LiteralPath $destination -Destination $backup -Force }
    try {
        Move-Item -LiteralPath $temp -Destination $destination -Force
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "Installed: $destination"
    }
    catch {
        if (-not (Test-Path -LiteralPath $destination) -and (Test-Path -LiteralPath $backup)) {
            Move-Item -LiteralPath $backup -Destination $destination -Force
        }
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

param(
    [Parameter(Mandatory = $true)][string]$RunnerRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ProfileSha256,
    [string]$Repository = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$path = Join-Path $RunnerRoot 'trusted-profiles.json'
$entries = @()
if (Test-Path -LiteralPath $path) { $entries = @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) }
$entries = @($entries | Where-Object { $_.profileSha256 -ne $ProfileSha256 })
$entries += [pscustomobject]@{
    profileSha256 = $ProfileSha256.ToLowerInvariant()
    repository = $Repository
    trustedAt = (Get-Date).ToUniversalTime().ToString('o')
    trustedBy = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}
$entries | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
[pscustomobject]@{ status = 'TRUSTED'; profileSha256 = $ProfileSha256.ToLowerInvariant(); repository = $Repository } | ConvertTo-Json -Compress

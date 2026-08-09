param(
    [Parameter(Mandatory = $true)][string]$RunnerRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ProfileSha256,
    [string]$Repository = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$path = Join-Path $RunnerRoot 'trusted-profiles.json'
$entries = [System.Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $path) {
    $parsed = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($candidate in @($parsed)) {
        if ($candidate.PSObject.Properties['profileSha256']) {
            $entries.Add($candidate)
        }
        elseif ($candidate.PSObject.Properties['value']) {
            # Repair registries written by Windows PowerShell 5.1 as wrapped arrays.
            foreach ($nested in @($candidate.value)) {
                if ($nested.PSObject.Properties['profileSha256']) { $entries.Add($nested) }
            }
        }
    }
}
$normalizedSha = $ProfileSha256.ToLowerInvariant()
$filtered = @($entries | Where-Object { [string]$_.profileSha256 -ne $normalizedSha })
$filtered += [pscustomobject]@{
    profileSha256 = $normalizedSha
    repository = $Repository
    trustedAt = (Get-Date).ToUniversalTime().ToString('o')
    trustedBy = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}
ConvertTo-Json -InputObject @($filtered) -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
[pscustomobject]@{ status = 'TRUSTED'; profileSha256 = $normalizedSha; repository = $Repository } | ConvertTo-Json -Compress

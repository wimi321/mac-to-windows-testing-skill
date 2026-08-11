param(
    [Parameter(Mandatory)][string]$ModulePath,
    [Parameter(Mandatory)][long]$WindowHandle,
    [Parameter(Mandatory)][int]$ProcessId,
    [Parameter(Mandatory)][string]$ChildPathCsv,
    [Parameter(Mandatory)][string]$PreferredAction,
    [Parameter(Mandatory)][string]$OutputPath,
    [int]$TestDelayMilliseconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-ActionResult {
    param([Parameter(Mandatory)]$Value)
    $directory = Split-Path -Parent $OutputPath
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $json = $Value | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($OutputPath, $json, [System.Text.UTF8Encoding]::new($false))
}

try {
    $testDelay = [Math]::Max(0, $TestDelayMilliseconds)
    if ($testDelay -gt 0) { Start-Sleep -Milliseconds $testDelay }

    $childPath = [System.Collections.Generic.List[int]]::new()
    if ($ChildPathCsv -ne 'root') {
        foreach ($value in $ChildPathCsv.Split(',')) {
            $parsed = 0
            if (-not [int]::TryParse($value, [ref]$parsed) -or $parsed -lt 0) {
                throw "Invalid Java accessibility child path: $ChildPathCsv"
            }
            $childPath.Add($parsed)
        }
    }

    Import-Module $ModulePath -Force
    $result = Invoke-M2WJavaAccessibleAction `
        -WindowHandle ([IntPtr]$WindowHandle) `
        -ProcessId $ProcessId `
        -ChildPath ([int[]]$childPath.ToArray()) `
        -PreferredAction $PreferredAction `
        -InProcess
    Write-ActionResult -Value $result
}
catch {
    Write-ActionResult -Value ([pscustomobject]@{
        Status = 'BLOCKED'
        Supported = $false
        Action = $null
        AvailableActions = @()
        FailureIndex = -1
        Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_ACTION_FAILED'
        Detail = $_.Exception.Message
    })
}

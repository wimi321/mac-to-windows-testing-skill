param(
    [Parameter(Mandatory)][string]$ModulePath,
    [Parameter(Mandatory)][long]$WindowHandle,
    [Parameter(Mandatory)][int]$ProcessId,
    [Parameter(Mandatory)][int]$Limit,
    [Parameter(Mandatory)][string]$OutputPath,
    [int]$TestDelayMilliseconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-CaptureResult {
    param([Parameter(Mandatory)]$Value)
    $directory = Split-Path -Parent $OutputPath
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $json = $Value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($OutputPath, $json, [System.Text.UTF8Encoding]::new($false))
}

try {
    $testDelay = [Math]::Max(0, $TestDelayMilliseconds)
    if ($testDelay -gt 0) { Start-Sleep -Milliseconds $testDelay }

    Import-Module $ModulePath -Force
    $snapshot = Get-M2WJavaAccessibilitySnapshot `
        -WindowHandle ([IntPtr]$WindowHandle) -ProcessId $ProcessId -Limit $Limit -InProcess
    Write-CaptureResult -Value $snapshot
}
catch {
    Write-CaptureResult -Value ([pscustomobject]@{
        Status = 'BLOCKED'
        Blocker = 'BLOCKED_JAVA_ACCESS_BRIDGE_CAPTURE_FAILED'
        Detail = $_.Exception.Message
        DllPath = $null
        Nodes = @()
    })
}

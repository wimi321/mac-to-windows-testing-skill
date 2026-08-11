Set-StrictMode -Version Latest

function ConvertTo-M2WCmdArguments {
    param([Parameter(Mandatory = $true)][string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) {
        throw 'Runner command cannot be empty.'
    }
    return "/d /s /c `"$Command`""
}

Export-ModuleMember -Function ConvertTo-M2WCmdArguments

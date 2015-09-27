function Get-NBDSession{
    [CmdletBinding()]
    Param
    (
        [Parameter()]
            [string]$Name
    )

    if($PSBoundParameters.ContainsKey('Name'))
    {
        $Global:NBDSessions[$Name]
    }
    else
    {
        foreach($obj in $Global:NBDSessions.Values.GetEnumerator())
        {
            Write-Output $obj
        }
    }
}
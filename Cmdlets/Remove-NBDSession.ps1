function Remove-NBDSession{
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param
    (
        [Parameter(ParameterSetName = 'Name')]
            [string]$Name,

        [Parameter(ParameterSetName = 'Session', ValueFromPipeline = $True)]
            [NBD.NbdSession[]]$Session
    )

    BEGIN
    {
        # Build Request Packet
        [byte[]]$killstring = @(0x4B, 0x49, 0x4C, 0x4C)
        Write-Verbose $killstring
    }

    PROCESS
    {
        if($PSCmdlet.ParameterSetName -eq 'Name')
        {
            $obj = Get-NBDSession -Name $Name
            $client = New-Object System.Net.Sockets.TcpClient($obj.ComputerName, $obj.Port)
            $stream = $client.GetStream()
            $stream.Write($Request, 0, $Request.Length)
            $obj.Disconnect()
        }
        elseif($PSCmdlet.ParameterSetName -eq 'Session')
        {
            $client = New-Object System.Net.Sockets.TcpClient($Session.ComputerName, $Session.Port)
            $stream = $client.GetStream()
            $stream.Write($Request, 0, $Request.Length)
            $Session.Disconnect()
        }
        else
        {
            foreach($obj in Get-NBDSession)
            {
                $client = New-Object System.Net.Sockets.TcpClient($obj.ComputerName, $obj.Port)
                $stream = $client.GetStream()
                $stream.Write($Request, 0, $Request.Length)
                $obj.Disconnect()
            }
        }
    }

    END
    {
        $stream.Close()
        $client.Close()
    }
}
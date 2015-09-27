function New-NBDSession{
    [CmdletBinding()]
    Param
    (
        [Parameter()]
            [string]$ComputerName = 'localhost',

        [Parameter(Mandatory = $true, Position = 0)]
            [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
            [String]$ClientIP,

        [Parameter()]
            [String]$FileToServe = "\\.\PHYSICALDRIVE0",

        [Parameter()]
            [String]$ListenPort = "60000"
    )

    BEGIN
    {
        if(!($PSBoundParameters.ContainsKey('Name')))
        {
            
        }

        $scriptblock = {
            Param
            (
                [String]$ClientIP,
                [String]$FileToServe,
                [String]$ListenPort
            )
            
            #region Constants
        
            $GENERIC_READWRITE = 0x80000000
            $FILE_SHARE_READWRITE = 0x02 -bor 0x01
            $OPEN_EXISTING = 0x03
        
            #endregion

            #region Reflection
            $DynAssembly = New-Object System.Reflection.AssemblyName('Win32')
            $AssemblyBuilder = [AppDomain]::CurrentDomain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
            $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('Win32', $False)

            $TypeBuilder = $ModuleBuilder.DefineType('Win32.Kernel32', 'Public, Class')
            $DllImportConstructor = [Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String]))
            $SetLastError = [Runtime.InteropServices.DllImportAttribute].GetField('SetLastError')
            $SetLastErrorCustomAttribute = New-Object Reflection.Emit.CustomAttributeBuilder($DllImportConstructor,
                @('kernel32.dll'),
                [Reflection.FieldInfo[]]@($SetLastError),
                @($True))

            # Define [Win32.Kernel32]::CreateFile
            $PInvokeMethod = $TypeBuilder.DefinePInvokeMethod('CreateFile',
                'kernel32.dll',
                ([Reflection.MethodAttributes]::Public -bor [Reflection.MethodAttributes]::Static),
                [Reflection.CallingConventions]::Standard,
                [IntPtr],
                [Type[]]@([String], [Int32], [UInt32], [IntPtr], [UInt32], [UInt32], [IntPtr]),
                [Runtime.InteropServices.CallingConvention]::Winapi,
                [Runtime.InteropServices.CharSet]::Ansi)
            $PInvokeMethod.SetCustomAttribute($SetLastErrorCustomAttribute)

            # Define [Win32.Kernel32]::CloseHandle
            $PInvokeMethod = $TypeBuilder.DefinePInvokeMethod('CloseHandle',
                'kernel32.dll',
                ([Reflection.MethodAttributes]::Public -bor [Reflection.MethodAttributes]::Static),
                [Reflection.CallingConventions]::Standard,
                [Bool],
                [Type[]]@([IntPtr]),
                [Runtime.InteropServices.CallingConvention]::Winapi,
                [Runtime.InteropServices.CharSet]::Auto)
            $PInvokeMethod.SetCustomAttribute($SetLastErrorCustomAttribute)

            $Kernel32 = $TypeBuilder.CreateType()

            #endregion

            ########################
            # Ultimately we will want to change this to send $buffer back to the client
            # Create a TCPListener object
            $server = New-Object -TypeName System.Net.Sockets.TcpListener($ListenPort)
        
            # Start listening on $ListenPort
            $server.Start()
        
            # Probably want to ultimately use the BeginAcceptSocket method
        
            # Initialize Connection Counter
            $i = 0

            # Loop for connections
            while($i -lt $ConnectionLimit)
            {
                $socket = $server.AcceptSocket()
                ########################
                # Listen for the request from the client
                # Request should look like
                # Header: TF12
                # Offset: XXX
                # Length: XXX
                ########################
                $request = New-Object Byte[](0x20)
            
                $receivereturn = $socket.Receive($request)
            
                if($socket.RemoteEndPoint.ToString().Split(':') -ne $ClientIP)
                {
                    $errorbytes = New-Object -TypeName Byte[](1)
                    $socket.Send($errorbytes)
                }

                if(([System.BitConverter]::ToString($request[0x00..0x03])) -eq '54-46-31-32')
                {
                    $Offset = [System.BitConverter]::ToInt32($request, 0x04)
                    $Length = [System.BitConverter]::ToInt32($request, 0x08)
                }
                elseif(([System.BitConverter]::ToString($request[0x00..0x03])) -eq '4B-49-4C-4C')
                {
                    break;
                }
            
                # Check for invalid $Length and $Offset values
                if($Length -lt 1)
                { 
                    Write-Error "Size parameter cannot be null or 0 or less than 0!" -ErrorAction Stop
                }
                if(($Length % 512) -ne 0) 
                {
                    Write-Error "Size parameter must be divisible by 512" -ErrorAction Stop
                }
                if(($Offset % 512) -ne 0)
                { 
                    Write-Error "Offset parameter must be divisible by 512" -ErrorAction Stop
                }

                try
                {
                    # Get handle to $FileToServe
                    $DriveHandle = $Kernel32::CreateFile($FileToServe, $GENERIC_READWRITE, $FILE_SHARE_READWRITE, 0, $OPEN_EXISTING, 0, 0)

                    # Check that handle is valid
                    if ($DriveHandle -eq ([IntPtr] 0xFFFFFFFF))
                    {
                        # Probably need to think of some better way to return error
                        $errorbytes = New-Object -TypeName Byte[](1)
                        $socket.Send($errorbytes)
                    }

                    # Create a FileStream to read from the handle
                    $streamToRead = New-Object -TypeName System.IO.FileStream($DriveHandle, [System.IO.FileAccess]::Read)
            
                    # Set our position in the stream to $Offset
                    $streamToRead.Position = $Offset
        
                    # Create a buffer $Length bytes long
                    $buffer = New-Object -TypeName Byte[]($Length)

                    # Read $Length bytes
                    $return = $streamToRead.Read($buffer, 0, $Length)
                
                    # Clean up FileStream
                    $streamToRead.Dispose()
                
                    # Output requested bytes
                    $socket.Send($buffer)
                
                    # Increment Connection counter
                    $i++
                }
                catch
                {
                    # Probably need to think of some better way to return error
                    $errorbytes = New-Object -TypeName Byte[](1)
                    $socket.Send($errorbytes)
                }
            }
            $socket.Dispose()
            $server.Stop()
            $null = $Kernel32::CloseHandle($DriveHandle)
        }
    }

    PROCESS
    {
        try
        {
            $job = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptblock -ArgumentList @($ClientIP, $FileToServe, $ListenPort) -AsJob
        }
        catch
        {
            Write-Error "Failed to set up NBD Server on $($ComputerName)" -ErrorAction Stop
        }
    }

    END
    {
        $obj = New-Object -TypeName NBD.NbdSession($job.Id, $ComputerName, $ClientIP, $FileToServe, $ListenPort)
        $Global:NBDSessions.Add($Name, $obj)
        Write-Output $obj 
    }
}
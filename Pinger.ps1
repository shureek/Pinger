function Ping-Computer {
    [CmdletBinding()]
    param(
        [string[]]$ComputerName,
        [int]$Count = 4,
        [int]$Delay = 1
    )
    
    #If Count <= 0 we'll make endless loop
    if ($Count -le 0) {
        $CountInt = 100
    }
    else {
        $CountInt = $Count
    }

    0 | %{
        do {
            Test-Connection -ComputerName $ComputerName -Count $CountInt -Delay $Delay -ErrorAction SilentlyContinue -ErrorVariable PingError
        } while($Count -le 0)
    } | %{
        $_
        if ($PingError.Count -gt 0) {
            Write-Output $PingError
            $PingError.Clear()
        }
    } -End {
        if ($PingError.Count -gt 0) {
            Write-Output $PingError
            $PingError.Clear()
        }
    } | %{
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $obj = [PSCustomObject]@{Computer=$_.TargetObject; Address=$null; Status=$false; Time=$null}
        }
        else {
            $obj = [PSCustomObject]@{Computer=$_.Address; Address=$_.ProtocolAddress; Status=$true; Time=$_.ResponseTime}
        }
        $obj.PSObject.TypeNames.Insert(0, 'PingStatus')
        $obj
    }
}

function Send-NetMessage {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [string]$Address,
        [Parameter(ValueFromPipeline=$true)]
        [string]$Message,
        $ObjectNumber
    )
    
    begin {
        if ($Address -match '^(?<Address>[^:]+)(?::(?<Port>\d+))?$') {
        }
        else {
            Write-Error 'Address is incorrect'
            return
        }
        $AddressStr = $Matches.Address
        $Port = [Int32]::Parse($Matches.Port)
    }
    process {
        if ($PSCmdlet.ShouldProcess("$Message => $Address")) {
            $client = New-Object System.Net.Sockets.Socket -ArgumentList 'InterNetwork','Stream','Tcp'
            $client.Connect($AddressStr, $Port)
            $client.NoDelay = $true
            $client.ReceiveTimeout = 4000
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("$Message`r")
            Write-Verbose "Отправка '$Message' => $($client.RemoteEndpoint)"
            $client.Send($bytes) | Out-Null
            $bytesReceived = $client.Receive($bytes)
            if ($bytesReceived) {
                $sb = New-Object System.Text.StringBuilder
                $sb.Append("В ответ получено $bytesReceived байт") | Out-Null
                $sb.Append(':') | Out-Null
                for ($i = 0; $i -lt $bytesReceived; $i++) {
                    $sb.AppendFormat(' {0:X2}', $bytes[$i]) | Out-Null
                }
                Write-Verbose $sb
            }
            else {
                Write-Verbose 'Ответ не получен'
            }
            $client.Close()
        }
    }
    end {
    }
}

$Computers = @{
    '10.34.0.72' = 1;
    '10.34.0.73' = 2;
    '10.34.0.75' = 3;
    '10.34.0.77' = 4
}
$SendTo = '10.34.0.25:10030'
$ObjectNumber = 9999
$VerbosePreference = 'Continue'

Ping-Computer $Computers.Keys -Count 0 -Delay 10 -PipelineVariable Ping | %{
    $CompStats = $Stats[$Ping.Computer]
    if ($CompStats -eq $null) {
        $CompStats = [PSCustomObject]@{Computer=$Ping.Computer; Status=$null; Begin=$null}
        $Stats[$Ping.Computer] = $CompStats
    }
    if ($Ping.Status -eq $CompStats.Status) {
        if ($CompStats.Begin -eq $null) {
            $begin = 'момента запуска'
            $span = (Get-Date) - $StartTime
        }
        else {
            $begin = '{0}' -f $CompStats.Begin
            $span = (Get-Date) - $CompStats.Begin
        }
        $span = New-Object TimeSpan -ArgumentList $span.Days,$span.Hours,$span.Minutes,$span.Seconds
        $add = ' с {0} ({1:c})' -f $begin,$span
    }
    else {
        if ($CompStats.Status -ne $null) {
            $CompStats.Begin = Get-Date
        }
        $CompStats.Status = $Ping.Status
        $add = ''
    }
    if ($Ping.Status) {
        Write-Verbose "$($Ping.Computer) доступен$add, пинг $($Ping.Time) мс"
    }
    else {
        Write-Warning "$($Ping.Computer) не отвечает$add"
    }

    if (-not $Ping.Status) {
        $Zone = $Computers[$Ping.Computer]
        $Message = '5011 18{0:D4}E13001{1:D3}' -f $ObjectNumber,$Zone
        Send-NetMessage -Message $Message -Address $SendTo
    }
} -Begin {
    $StartTime = Get-Date
    $Stats = @{}
}
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
    [CmdletBinding()]
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
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($AddressStr, $Port)
        #Write-Verbose "Sending '$Message' to $($client.Client.RemoteEndPoint)"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($Message)
        $client.Client.Send($bytes)
        $client.Close()
    }
    end {
    }
}

#$Computers = 'MAIN','ATS','Server1C','www.yandex.ru','hp1mux'
$Computers = '10.34.0.72','10.34.0.73','10.34.0.75'
$SendTo = '188.247.38.178:3056'
$VerbosePreference = 'Continue'

Ping-Computer $Computers -Count 0 -Delay 10 -PipelineVariable Ping | %{
    $CompStats = $Stats[$Ping.Computer]
    if ($CompStats -eq $null) {
        $CompStats = [PSCustomObject]@{Computer=$Ping.Computer; Status=$null; Begin=(Get-Date)}
        $Stats[$Ping.Computer] = $CompStats
    }
    if ($Ping.Status -ne $CompStats.Status) {
        if ($Ping.Status) {
            Write-Verbose "$($Ping.Computer) доступен"
        }
        else {
            Write-Warning "$($Ping.Computer) не доступен"
        }
    }
    if (-not $Ping.Status) {
        $Zone = 1
        $Message = '501118{0:D4}E1300100{1:D1}' -f $ObjectNumber,$Zone
        Write-Verbose "$(Get-Date): $ComputerName is unavailable (Message: $Message)"
        Send-NetMessage -Message $Message -Address $SendTo
    }
} -Begin {
    $Stats = @{}
}
[CmdletBinding()]
param(
    # Компьютеры и соответствующие им номера зон
    [Parameter(Mandatory=$true)]
    [Hashtable]$Computers,

    # Адрес получателя в формате <адрес>[:<порт>]
    [Parameter(Position=0, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidatePattern('[^:]+(:\d+)?')]
    [string]$SendTo,

    # Номер объекта в сработке
    [Parameter(Mandatory=$true)]
    [ValidateRange(0, 9999)]
    [int]$ObjectNumber,

    # Номер раздела (шлейфа) в сработке
    [ValidateRange(0, 99)]
    [int]$Part = 1,

    # Код события в сработке
    [Parameter(Mandatory=$true)]
    [ValidatePattern('[E|R]\d{3}')]
    [string]$EventCode
)

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

function Send-ShurgardMessage {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        # Адрес получателя в формате <адрес>[:<порт>]
        [Parameter(Position=0, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('[^:]+(:\d+)?')]
        [string]$Address,

        # Номер приемника
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 9)]
        [int]$Receiver = 1,
        # Номер линии
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 99)]
        [int]$Line = 1,
        # Номер объекта
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 9999)]
        [int]$Object,
        # Код события
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('[E|R]\d{3}')]
        [string]$Event,
        # Номер раздела (шлейфа)
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 99)]
        [int]$Part,
        # Номер зоны
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 999)]
        [int]$Zone,

        # Тест
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [switch]$Test
    )
    
    begin {
        if ($Address -match '(?<Address>[^:]+)(?::(?<Port>\d+))?') {
        }
        else {
            Write-Error 'Address is incorrect' -Category InvalidArgument -TargetObject $Address
            return
        }
        $AddressStr = $Matches.Address
        $Port = [Int32]::Parse($Matches.Port)
        $Socket = New-Object System.Net.Sockets.Socket -ArgumentList 'InterNetwork','Stream','Tcp'
        $Socket.Connect($AddressStr, $Port)
        if (-not $Socket.Connected) {
            Write-Error 'Не удалось подключиться к получателю' -Category ConnectionError -TargetObject $Address
        }
        Write-Verbose "Connected to $($Socket.RemoteEndpoint)"
        $Socket.NoDelay = $true
        $Socket.ReceiveTimeout = 5000
        [byte]$EOL = 0x14
        [byte]$AnswerOK = 0x06
        [byte]$AnswerFail = 0x15
        [byte[]]$Buffer = New-Object byte[] 128
        #Не реже, чем раз в 30 сек. нужно что-нибудь отправлять (сообщение или тест)
    }
    process {
        if ($Test) {
            $Message = '1011           @    '
        }
        else {
            $Message = '5{0:D2}{1} 18{2:D4}{3}{4:D2}{5:D3}' -f $Receiver,$Line,$Object,$Event,$Part,$Zone
        }
        if ($PSCmdlet.ShouldProcess($Message)) {
            $BytesCount = [System.Text.Encoding]::ASCII.GetBytes($Message, 0, $Message.Length, $Buffer, 0)
            $Buffer[$BytesCount] = $EOL
            $BytesCount++
            $SentCount = $Socket.Send($Buffer, 0, $BytesCount, 'None')
            if ($SentCount -ne $BytesCount) {
                Write-Error "Отправлено $SentCount байт вместо $BytesCount" -Category InvalidResult
            }
            [System.Net.Sockets.SocketError]$SocketError = 0
            $ReceivedCount = $Socket.Receive($Buffer, 0, $Buffer.Length, 'None', [Ref]$SocketError)
            if ($SocketError -ne 'Success' -and $SocketError -ne 'TimedOut') {
                Write-Error "Ошибка получения ответа от получателя: $SocketError" -Category ConnectionError
            }
            elseif ($ReceivedCount -eq 1 -and $Buffer[0] -eq $AnswerOK) {
                # Все ОК
            }
            elseif ($ReceivedCount -eq 1 -and $Buffer[0] -eq $AnswerFail) {
                Write-Warning 'Получатель вернул ошибку'
            }
            elseif ($ReceivedCount) {
                $sb = New-Object System.Text.StringBuilder
                $sb.Append("В ответ получено $ReceivedCount байт") | Out-Null
                $sb.Append(':') | Out-Null
                for ($i = 0; $i -lt $ReceivedCount; $i++) {
                    $sb.AppendFormat(' {0:X2}', $Buffer[$i]) | Out-Null
                }
                $sb.AppendFormat(' ({0})', [System.Text.Encoding]::ASCII.GetString($Buffer, 0, $ReceivedCount)) | Out-Null
                Write-Verbose $sb
            }
            elseif (-not $Test) {
                Write-Warning 'Ответ не получен'
            }
        }
    }
    end {
        $Socket.Close()
    }
}

function ConvertTo-ObjectEvent {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
        $PingStatus
    )
}

Ping-Computer $Computers.Keys -Count 0 -Delay 10 -PipelineVariable Ping | %{
    $CompStats = $Stats[$Ping.Computer]
    if ($CompStats -eq $null) {
        $CompStats = [PSCustomObject]@{Computer=$Ping.Computer; Status=$null; Begin=$null}
        $Stats[$Ping.Computer] = $CompStats
    }
    if ($Ping.Status -eq $CompStats.Status) {
        if ($CompStats.Begin -eq $null) {
            $Begin = 'момента запуска'
            $Span = (Get-Date) - $StartTime
        }
        else {
            $Begin = '{0}' -f $CompStats.Begin
            $Span = (Get-Date) - $CompStats.Begin
        }
        $Span = New-Object TimeSpan -ArgumentList $Span.Days,$Span.Hours,$Span.Minutes,$Span.Seconds
        $add = ' с {0} ({1:c})' -f $Begin,$Span
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
        $data = [PSCustomObject]@{ Zone = $Computers[$Ping.Computer] }
    }
    else {
        $data = [PSCustomObject]@{ Test = $true }
    }
    Write-Output $data
} -Begin {
    $StartTime = Get-Date
    $Stats = @{}
} | Send-ShurgardMessage -Address $SendTo -Object $ObjectNumber -Part $Part -Event $EventCode
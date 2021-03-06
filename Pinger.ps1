﻿<#
.Synopsis
    Пингует указанные компьютеры и отправляет тревожные сообщения на приемник по TCP
.Notes
    Создал Александр Кузин
    Версия 1.2 от 14.07.2014
    Файл подписан цифровой подписью. При малейшем изменении он перестанет запускаться.
#>
[CmdletBinding(DefaultParameterSetName='FileName', SupportsShouldProcess=$true)]
param(
    # Адрес приемника в формате <адрес>[:<порт>]
    [Parameter(Position=0)]
    [ValidatePattern('[^:]+(:\d+)?')]
    [string]$SendTo = '10.34.0.25:10030',
    
    # Соответствие компьютеров и номеров зон
    [Parameter(Mandatory=$true, ParameterSetName='Computers')]
    [Hashtable]$Computers,

    # Имя файла со списком компьютеров и номерами зон
    # Текстовый файл со строками вида:
    #  Server1 = 1
    #  10.34.0.1 = 2
    #  www.yandex.ru = 3
    [Parameter(ParameterSetName='FileName')]
    [string]$FileName = 'Ping computers.txt',

    # Номер приемника
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateRange(0, 9)]
    [int]$ReceiverNo = 1,

    # Номер линии
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateRange(0, 99)]
    [int]$LineNo = 1,

    # Номер объекта
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateRange(0, 9999)]
    [int]$ObjectNumber = 9999,

    # Код события
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidatePattern('[E|R]\d{3}')]
    [string]$EventCode = 'E130',

    # Номер раздела (шлейфа)
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateRange(0, 99)]
    [int]$Part = 1
)

<#
.Synopsis
   Пингует указанные компьютеры
.Description
   Пингует указанные компьютеры и выдает результат в виде объекта PingStatus
.Example
   Ping-Computer SERVER
.Example
   Ping-Computer SERVER1,SERVER2 -Count 0 -Delay 10
.Outputs
   PingStatus
.Notes
   В отличие от Test-Connection, при отсутствии пинга этот командлет не генерирует ошибку, а возвращает объект PingStatus со статусом $false
#>
function Ping-Computer {
    [CmdletBinding()]
    param(
        # Имя или адрес компьютера
        [Parameter(Mandatory=$true, Position=0)]
        [string[]]$ComputerName,
        # Количество пингов (0 — бесконечно)
        [int]$Count = 4,
        # Задержка между пингами
        [int]$Delay = 1
    )
    
    # Начальные данные для формирования статистики
    $StartTime = Get-Date
    $Stats = @{}
    
    if ($Count -le 0) {
        $CountInt = 100
    }
    else {
        $CountInt = $Count
    }

    0 | %{
        do {
            Test-Connection -ComputerName $ComputerName -Count $CountInt -Delay $Delay -ErrorAction SilentlyContinue -ErrorVariable PingError
        } while($Count -le 0) # при $Count ≤ 0 будет бесконечный цикл
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
        # Формируем объект PingStatus
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $PingStatus = [PSCustomObject]@{Computer=$_.TargetObject; Address=$null; Status=$false; Time=$null}
        }
        else {
            $PingStatus = [PSCustomObject]@{Computer=$_.Address; Address=$_.ProtocolAddress; Status=$true; Time=$_.ResponseTime}
        }
        $PingStatus.PSObject.TypeNames.Insert(0, 'PingStatus')
        
        # Формируем статистику
        $CompStats = $Stats[$PingStatus.Computer]
        if ($CompStats -eq $null) {
            $CompStats = [PSCustomObject]@{Computer=$PingStatus.Computer; Status=$null; Begin=$null}
            $Stats[$PingStatus.Computer] = $CompStats
        }

        if ($PingStatus.Status -eq $CompStats.Status) {
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
            $CompStats.Status = $PingStatus.Status
            $add = ''
        }
        if ($PingStatus.Status) {
            Write-Verbose "$($PingStatus.Computer) доступен$add, пинг $($PingStatus.Time) мс"
        }
        else {
            Write-Warning "$($PingStatus.Computer) не отвечает$add"
        }

        $PingStatus
    }
}

<#
.Synopsis
   Отправляет сообщение в формате Surgard
.Description
   Формирует и отправляет по tcp на указанный адрес и порт сообщение в формате Surgard
.Example
   Send-SurgardMessage -Address SERVER:10000 -Object 100 -Event R130 -Part 2 -Zone 4
.Example
   [PSCustomObject]@{ Object=1; Event='E130'; Part = 1; Zone = 1 } | Send-SurgardMessage SERVER:10000 -Receiver 1 -Line 1
.Inputs
   ObjectEvent
#>
function Send-SurgardMessage {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        # Адрес приемника в формате <адрес>[:<порт>]
        [Parameter(Position=0, Mandatory=$true)]
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
        [int]$Part = 1,
        # Номер зоны
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 999)]
        [int]$Zone = 1,

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
        if ($PSCmdlet.ShouldProcess($Message, 'Отправка сообщения')) {
            $BytesCount = [System.Text.Encoding]::ASCII.GetBytes($Message, 0, $Message.Length, $Buffer, 0)
            $Buffer[$BytesCount] = $EOL
            $BytesCount++

            if ($Socket -eq $null -or -not $Socket.Connected) {
                if ($Socket -ne $null) {
                    $Socket.Close()
                }
                $Socket = New-Object System.Net.Sockets.Socket -ArgumentList 'InterNetwork','Stream','Tcp'
                $Socket.Connect($AddressStr, $Port)
                if (-not $Socket.Connected) {
                    Write-Error 'Не удалось подключиться к получателю' -Category ConnectionError -TargetObject $Address
                    return
                }
                Write-Verbose "Подключились к $($Socket.RemoteEndpoint)"
                $Socket.NoDelay = $true
                $Socket.ReceiveTimeout = 5000
            }

            [System.Net.Sockets.SocketError]$SocketError = 0
            $SentCount = $Socket.Send($Buffer, 0, $BytesCount, 'None', [Ref]$SocketError)
            if ($SocketError -ne 'Success') {
                $ErrorCategory = [System.Management.Automation.ErrorCategory]::ConnectionError
                if ($SocketError -eq 'TimedOut') {
                    $ErrorCategory = [System.Management.Automation.ErrorCategory]::OperationTimeout
                }
                Write-Error "Ошибка отправки сообщения: $SocketError" -Category $ErrorCategory
                return
            }
            elseif ($SentCount -ne $BytesCount) {
                Write-Error "Отправлено $SentCount байт вместо $BytesCount" -Category InvalidResult
            }
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
                $sb.AppendFormat("В ответ получено {0} байт:", $ReceivedCount) | Out-Null
                for ($i = 0; $i -lt $ReceivedCount; $i++) {
                    $sb.AppendFormat(' {0:X2}', $Buffer[$i]) | Out-Null
                }
                $sb.AppendFormat(' ({0})', [System.Text.Encoding]::ASCII.GetString($Buffer, 0, $ReceivedCount)) | Out-Null
                Write-Verbose $sb
            }
            elseif (-not $Test) {
                Write-Warning 'От приемника не получено подтверждение о доставке сообщения'
            }
        }
    }
    end {
        $Socket.Close()
    }
}

# Начало основной программы
if ($PSCmdlet.ParameterSetName -eq 'FileName') {
    $FullFileName = $FileName
    if (-not (Test-Path $FullFileName)) {
        # Если не нашли файл, то попробуем поискать в папке со скриптом
        if (-not [System.IO.Path]::IsPathRooted($FileName)) {
            $ScriptPath = Split-Path $PSCommandPath -Parent
            $FullFileName = Join-Path $ScriptPath $FileName
        }
    }
    $Computers = Get-Content $FullFileName | ?{ $_ -match '(?<Name>[^\s=]+)\s*=\s*(?<Value>\d+)' } | %{ $Hashtable[$Matches.Name] = [int]$Matches.Value } -Begin { $Hashtable = @{} } -End { $Hashtable }
}
Ping-Computer $Computers.Keys -Count 0 -Delay 10 -Verbose | %{
    if ($_.Status) {
        [PSCustomObject]@{
            Test = $True
        }
    }
    else {
        [PSCustomObject]@{
            Object = $ObjectNumber;
            Event = $EventCode;
            Part = $Part;
            Zone = $Computers[$_.Computer];
        }
    }
} | Send-SurgardMessage -Address $SendTo -Receiver $ReceiverNo -Line $LineNo
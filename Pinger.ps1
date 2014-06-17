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

$Computers = 'MAIN','ATS','Server1C','www.yandex.ru','hp1mux'

Ping-Computer $Computers -Count 0 -Delay 10 | ?{ $_.Status -ne $true } | select -ExpandProperty Computer
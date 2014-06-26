. .\Pinger.ps1
$Computers = @{
    '10.34.0.72' = 2;
    '10.34.0.73' = 3;
    '10.34.0.74' = 4;
    '10.34.0.75' = 5;
    '10.34.0.76' = 6;
    '10.34.0.77' = 7;
}
Ping-Computer $Computers.Keys -Count 0 -Delay 10 -Verbose | %{
    if ($_.Status) {
        [PSCustomObject]@{
            Test = $True
        }
    }
    else {
        [PSCustomObject]@{
            Object = 9999;
            Event = 'E130';
            Part = 1;
            Zone = $Computers[$_.Computer];
        }
    }
} | Send-ShurgardMessage -Address 10.34.0.25:10030
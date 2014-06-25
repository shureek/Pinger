$Computers = @{
    '10.34.0.72' = 2;
    '10.34.0.73' = 3;
    '10.34.0.74' = 4;
    '10.34.0.75' = 5;
    '10.34.0.76' = 6;
    '10.34.0.77' = 7;
}
.\Pinger.ps1 -Computers $Computers -SendTo 10.34.0.25:10030 -ObjectNumber 9999 -EventCode E130 -Verbose
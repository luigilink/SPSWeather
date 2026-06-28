class SQLInstancesStatus {
    [System.String]$Server
    [System.String]$InstanceName
    [System.String]$Version
    [System.String]$ProductLevel
    [System.String]$UpdateLevel
}

function Get-SQLInstancesStatus {
    [CmdletBinding()]
    param()

    $tbSQLInstancesStatus = New-Object -TypeName System.Collections.ArrayList
    $sqlInstances = $env:COMPUTERNAME | Foreach-Object {Get-ChildItem -Path "SQLSERVER:\SQL\$_"}
    foreach ($sqlInstance in $sqlInstances){
        [void]$tbSQLInstancesStatus.Add([SQLInstancesStatus]@{
            Server=$env:COMPUTERNAME;
            InstanceName=$sqlInstance.InstanceName;
            Version=$sqlInstance.Version.ToString();
            ProductLevel=$sqlInstance.ProductLevel;
            UpdateLevel=$sqlInstance.ProductUpdateLevel;
        })
    }
    $jsonObject | Add-Member -MemberType NoteProperty `
                             -Name SQLInstancesStatus `
                             -Value $tbSQLInstancesStatus
}

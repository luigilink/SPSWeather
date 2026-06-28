class SQLDatabasesStatus {
    [System.String]$Server
    [System.String]$Instance
    [System.String]$Name
    [System.String]$Status
    [System.String]$Size
    [System.String]$SpaceAvailable
}

function Get-SQLDatabasesStatus {
    [CmdletBinding()]

    $tbSQLDatabasesStatus = New-Object -TypeName System.Collections.ArrayList
    $sqlInstances = $env:COMPUTERNAME | Foreach-Object {Get-ChildItem -Path "SQLSERVER:\SQL\$_"}
    foreach ($sqlInstance in $sqlInstances){
        Set-Location "SQLSERVER:\SQL\$($env:COMPUTERNAME)\$($sqlInstance.InstanceName)\databases"
        $sqlDatabases = Get-ChildItem | Sort-Object -Descending -Property Size
        foreach ($sqlDatabase in $sqlDatabases){
            [void]$tbSQLDatabasesStatus.Add([SQLDatabasesStatus]@{
                Server=$env:COMPUTERNAME;
                Instance= $sqlInstance.InstanceName;
                Name=$sqlDatabase.Name;
                Status=$sqlDatabase.Status;
                Size="$([math]::Round($sqlDatabase.Size/1024,2))";
                SpaceAvailable="$([math]::Round($sqlDatabase.SpaceAvailable/1024,2))";
            })
        }
    }
    $jsonObject | Add-Member -MemberType NoteProperty `
                             -Name SQLDatabasesStatus `
                             -Value $tbSQLDatabasesStatus
}

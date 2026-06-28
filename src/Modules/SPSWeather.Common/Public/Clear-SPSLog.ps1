function Clear-SPSLog {
    param (
        [Parameter(Mandatory = $true)]
        [System.String]
        $path,

        [Parameter()]
        [System.UInt32]
        $Retention = 180
    )

    if (Test-Path $path) {
        # Get the current date
        $Now = Get-Date
        # Define LastWriteTime parameter based on $days
        $LastWrite = $Now.AddDays(-$Retention)
        # Get files based on lastwrite filter and specified folder
        $files = Get-Childitem -Path $path -Filter "$($logFileName)*" | Where-Object -FilterScript {
            $_.LastWriteTime -le "$LastWrite"
        }
        if ($files) {
            Write-Output '--------------------------------------------------------------'
            Write-Output "Cleaning log files in $path ..."
            foreach ($file in $files) {
                if ($null -ne $file) {
                    Write-Output "Deleting file $file ..."
                    Remove-Item $file.FullName | out-null
                }
                else {
                    Write-Output 'No more log files to delete'
                    Write-Output '--------------------------------------------------------------'
                }
            }
        }
        else {
            Write-Output '--------------------------------------------------------------'
            Write-Output "$path - No needs to delete log files"
            Write-Output '--------------------------------------------------------------'
        }
    }
    else {
        Write-Output '--------------------------------------------------------------'
        Write-Output "$path does not exist"
        Write-Output '--------------------------------------------------------------'
    }
}

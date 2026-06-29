function Clear-SPSLog {
    param (
        [Parameter(Mandatory = $true)]
        [System.String]
        $path,

        [Parameter()]
        [System.UInt32]
        $Retention = 180,

        [Parameter()]
        [System.String]
        $Filter = '*.log'
    )

    if ($Retention -eq 0) {
        Write-Verbose -Message "Clear-SPSLog: retention is 0, pruning disabled."
        return
    }

    if (Test-Path $path) {
        $Now = Get-Date
        $LastWrite = $Now.AddDays(-$Retention)
        $files = Get-Childitem -Path $path -Filter $Filter -File -ErrorAction SilentlyContinue |
            Where-Object -FilterScript { $_.LastWriteTime -le $LastWrite }
        if ($files) {
            Write-Output '--------------------------------------------------------------'
            Write-Output "Cleaning files matching '$Filter' in $path (older than $Retention days) ..."
            foreach ($file in $files) {
                Write-Output "Deleting file $($file.FullName) ..."
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-Output '--------------------------------------------------------------'
            Write-Output "$path - No needs to delete files matching '$Filter'"
            Write-Output '--------------------------------------------------------------'
        }
    }
    else {
        Write-Output '--------------------------------------------------------------'
        Write-Output "$path does not exist"
        Write-Output '--------------------------------------------------------------'
    }
}

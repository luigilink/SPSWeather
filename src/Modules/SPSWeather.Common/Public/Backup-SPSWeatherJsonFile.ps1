function Backup-SPSWeatherJsonFile {
    <#
        .SYNOPSIS
        Archives an existing JSON snapshot into a history folder before it is overwritten.

        .DESCRIPTION
        Backup-SPSWeatherJsonFile copies the file at -Path into -HistoryFolder, appending
        a timestamp to the file name (e.g. zebes-PROD-2026-06-29-20260629-1130.json). The
        original file is left untouched so the caller can overwrite it with a fresh
        snapshot afterwards.

        The function does not perform retention itself: pass -RetentionDays to also prune
        history files older than that many days. Returns the full path of the backup
        that was created, or $null when -Path does not exist (first run).

        .PARAMETER Path
        The JSON file about to be overwritten.

        .PARAMETER HistoryFolder
        Destination folder for the timestamped copy. Created if missing.

        .PARAMETER TimeStamp
        Timestamp string injected into the backup file name. Defaults to yyyyMMdd-HHmm.

        .PARAMETER RetentionDays
        When > 0, delete *.json files in the history folder older than this many days
        after archiving the current file. 0 (default) disables pruning.

        .EXAMPLE
        $previous = Backup-SPSWeatherJsonFile -Path $pathJsonFile `
            -HistoryFolder (Join-Path $pathResultsFolder 'history') `
            -RetentionDays 30
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.String]
        $HistoryFolder,

        [Parameter()]
        [System.String]
        $TimeStamp = (Get-Date -Format yyyyMMdd-HHmm),

        [Parameter()]
        [System.UInt32]
        $RetentionDays = 0
    )

    if (-not (Test-Path -Path $Path)) {
        Write-Verbose -Message "Backup-SPSWeatherJsonFile: no existing file to archive at '$Path'."
        return $null
    }

    if (-not (Test-Path -Path $HistoryFolder)) {
        $null = New-Item -Path $HistoryFolder -ItemType Directory -Force
    }

    $leaf       = Split-Path -Path $Path -Leaf
    $name       = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    $extension  = [System.IO.Path]::GetExtension($leaf)
    $backupName = "$name-$TimeStamp$extension"
    $backupPath = Join-Path -Path $HistoryFolder -ChildPath $backupName

    Copy-Item -Path $Path -Destination $backupPath -Force
    Write-Verbose -Message "Backup-SPSWeatherJsonFile: archived '$Path' to '$backupPath'."

    if ($RetentionDays -gt 0) {
        $cutoff = (Get-Date).AddDays(-[double]$RetentionDays)
        Get-ChildItem -Path $HistoryFolder -Filter '*.json' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    return $backupPath
}

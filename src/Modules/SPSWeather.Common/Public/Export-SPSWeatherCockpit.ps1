function Export-SPSWeatherCockpit {
    <#
        .SYNOPSIS
        Writes the multi-farm page of an environment as one self-contained HTML file.

        .DESCRIPTION
        Builds the dataset from the files that the runs leave in the Results folder (snapshots, run journal, settings) and
        writes the page to the given file: styles, script, data and display strings are all inside the file, so it opens from a
        file share, a SharePoint library or a double-click. The page is read-only: nothing is
        collected from the farms. The file is replaced in one step, so a reader never sees a half-written page.
        See the wiki pages Cockpit-Page and Cockpit-Data.

        .PARAMETER OutputFile
        The HTML file to write. Its folder is created when it does not exist.

        .PARAMETER ResultsFolder
        The Results folder of the installation.

        .PARAMETER Application
        ApplicationName of the environment configuration.

        .PARAMETER Environment
        ConfigurationName of the environment configuration.

        .PARAMETER FarmName
        The configured farms, in the order to show them.

        .PARAMETER RetentionDays
        JsonHistoryRetentionDays: limits the periods offered, 0 offers all of them.

        .PARAMETER Language
        The language the page opens in. The page also holds the other shipped languages. Default: en-US.

        .PARAMETER Version
        The SPSWeather version shown in the footer. Default: the module version.

        .EXAMPLE
        Export-SPSWeatherCockpit -OutputFile 'D:\Dashboards\contoso-PROD-cockpit.html' -ResultsFolder $pathResultsFolder -Application 'contoso' -Environment 'PROD' -FarmName 'CONTENT', 'SEARCH' -RetentionDays 30 -Language 'fr-FR'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputFile,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ResultsFolder,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Application,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Environment,

        [Parameter()]
        [System.String[]]
        $FarmName,

        [Parameter()]
        [System.UInt32]
        $RetentionDays = 0,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Language,

        [Parameter()]
        [System.String]
        $Version
    )

    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
    $folder = [System.IO.Path]::GetDirectoryName($fullPath)
    $temp = $null
    try {
        $data = Get-SPSWeatherCockpitData -DashboardFolder $folder -ResultsFolder $ResultsFolder -Application $Application -Environment $Environment -FarmName $FarmName -RetentionDays $RetentionDays
        $html = ConvertTo-SPSWeatherCockpitHtml -Data $data -Language $Language -Version $Version

        if (-not [System.IO.Directory]::Exists($folder)) { [void][System.IO.Directory]::CreateDirectory($folder) }

        $temp = '{0}.{1}.tmp' -f $fullPath, [guid]::NewGuid().ToString('N')
        [System.IO.File]::WriteAllText($temp, $html, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
        # Replace is a single step and throws on failure
        if ([System.IO.File]::Exists($fullPath)) { [System.IO.File]::Replace($temp, $fullPath, [NullString]::Value) }
        else { [System.IO.File]::Move($temp, $fullPath) }
        $temp = $null
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    finally {
        if ($null -ne $temp -and [System.IO.File]::Exists($temp)) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
    return $fullPath
}

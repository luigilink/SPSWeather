function Resolve-SPSCockpitSetting {
    <#
        .SYNOPSIS
        Resolves the cockpit page settings of an environment from its configuration.

        .DESCRIPTION
        Single place that reads the optional Dashboard.Cockpit key, so that the run, the readiness check and the tests agree.
        The key is a boolean, $false by default: nothing changes unless it is set. A value that is not a boolean (or its text form)
        is never cast (the text 'false' would become $true): it is reported and the page is not produced. Returns Enabled, the
        file name of the page, its folder (Dashboard.OutputPath, or Results when it is empty), its path, and the public URL of
        the page when Dashboard.Url is set (empty otherwise, which hides the button of the email). Messages holds what to report.

        .PARAMETER Config
        The environment configuration (hashtable loaded from the .psd1).

        .PARAMETER Application
        ApplicationName of the configuration.

        .PARAMETER Environment
        ConfigurationName of the configuration.

        .PARAMETER ResultsFolder
        The Results folder of the installation, used when Dashboard.OutputPath is empty.

        .EXAMPLE
        $cockpit = Resolve-SPSCockpitSetting -Config $envCfg -Application $Application -Environment $Environment -ResultsFolder $pathResultsFolder
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Config,

        [Parameter()]
        [System.String]
        $Application = '',

        [Parameter()]
        [System.String]
        $Environment = '',

        [Parameter()]
        [System.String]
        $ResultsFolder = ''
    )

    $messages = New-Object -TypeName System.Collections.ArrayList
    $dashboard = $null
    if (($null -ne $Config) -and $Config.Contains('Dashboard')) { $dashboard = $Config['Dashboard'] }
    $hasDashboard = ($null -ne $dashboard) -and ($dashboard -is [System.Collections.IDictionary])

    function Get-DashboardValue {
        param($Name)
        if (-not $hasDashboard -or -not $dashboard.Contains($Name)) { return $null }
        return $dashboard[$Name]
    }

    $enabled = $false
    if ($hasDashboard -and $dashboard.Contains('Cockpit')) {
        $raw = $dashboard['Cockpit']
        $parsed = $false
        if ($raw -is [bool]) { $enabled = $raw }
        elseif ($raw -is [string] -and [bool]::TryParse($raw.Trim(), [ref]$parsed)) { $enabled = $parsed }
        else {
            $shown = if ($raw -is [string]) { "'$raw'" } elseif ($null -eq $raw) { '$null' } else { "a value of type $($raw.GetType().Name)" }
            [void]$messages.Add("Dashboard.Cockpit must be `$true or `$false (got $shown); the cockpit page is not produced.")
        }
    }

    $fileName = "$Application-$Environment-cockpit.html"
    $outputPath = Get-DashboardValue -Name 'OutputPath'
    $folder = if (($outputPath -is [string]) -and -not [string]::IsNullOrWhiteSpace($outputPath)) { $outputPath } else { $ResultsFolder }
    $baseUrl = Get-DashboardValue -Name 'Url'
    $baseUrl = if (($baseUrl -is [string]) -and -not [string]::IsNullOrWhiteSpace($baseUrl)) { $baseUrl.Trim().TrimEnd('/') } else { '' }

    return [PSCustomObject]@{
        Enabled  = [bool]$enabled
        FileName = $fileName
        Folder   = $folder
        Path     = if ([string]::IsNullOrWhiteSpace($folder)) { $fileName } else { '{0}{1}{2}' -f $folder.TrimEnd('\', '/'), [System.IO.Path]::DirectorySeparatorChar, $fileName }
        Url      = if ($baseUrl) { "$baseUrl/$fileName" } else { '' }
        Messages = @($messages)
    }
}

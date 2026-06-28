function Add-SPSWeatherEvent {
    <#
        .SYNOPSIS
        Writes an entry to the dedicated SPSWeather Windows Event Log.

        .DESCRIPTION
        Add-SPSWeatherEvent writes an entry to the custom 'SPSWeather' Windows
        Event Log under the specified Source. The Source typically identifies the
        stage that raised the event (e.g. 'SPSWeather', 'Get-SPSContentDBStatus'),
        which makes filtering and SCOM monitoring straightforward.

        When the Source does not exist yet, it is created under the SPSWeather
        log; when the log itself does not exist, it is created on first use.
        Creating an event source requires administrative privileges, so this
        function is expected to run from the SPSWeather script, which already
        validates that it runs as Administrator.

        Each message is prefixed with a header containing the module version, the
        current user and the computer name to ease cross-server correlation.

        .PARAMETER Message
        The event message body. The header is prepended automatically.

        .PARAMETER Source
        Identifier of the event source. Defaults to 'SPSWeather'.

        .PARAMETER EntryType
        Severity of the event. Defaults to Information.

        .PARAMETER EventID
        Numeric event identifier. Defaults to 1.

        .EXAMPLE
        Add-SPSWeatherEvent -Message 'SPSWeather run started' -EventID 1000

        .EXAMPLE
        Add-SPSWeatherEvent -Message $_.Exception.Message -Source 'SPSWeather' -EntryType 'Error' -EventID 3000
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Message,

        [Parameter()]
        [System.String]
        $Source = 'SPSWeather',

        [Parameter()]
        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
        [System.String]
        $EntryType = 'Information',

        [Parameter()]
        [System.UInt32]
        $EventID = 1
    )

    $LogName = 'SPSWeather'

    if ([System.Diagnostics.EventLog]::SourceExists($Source)) {
        $sourceLogName = [System.Diagnostics.EventLog]::LogNameFromSourceName($Source, '.')
        if ($LogName -ne $sourceLogName) {
            Write-Verbose -Message "[ERROR] Specified source {$Source} already exists on log {$sourceLogName}"
            return
        }
    }
    else {
        if ([System.Diagnostics.EventLog]::Exists($LogName) -eq $false) {
            $null = New-EventLog -LogName $LogName -Source $Source
        }
        else {
            [System.Diagnostics.EventLog]::CreateEventSource($Source, $LogName)
        }
    }

    $autoVersion = $MyInvocation.MyCommand.Module.Version
    if ($null -eq $autoVersion) {
        $autoVersion = (Get-Module -Name 'SPSWeather.Common' -ErrorAction SilentlyContinue).Version
    }
    $scriptVersion = if ($null -ne $autoVersion) { $autoVersion.ToString() } else { 'unknown' }
    $userName = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name

    try {
        $headerMessage = @"
SPSWeather Version: $scriptVersion
User: $userName
ComputerName: $($env:COMPUTERNAME)
--------------------------------------------------------------
"@
        Write-EventLog -LogName $LogName -Source $Source -EventId $EventID -Message ($headerMessage + "`r`n" + $Message) -EntryType $EntryType
    }
    catch {
        Write-Error -Message @"
SPSWeather Version: $scriptVersion
An error occurred while writing to Event Log in Source: $Source
User: $userName
ComputerName: $($env:COMPUTERNAME)
Exception: $_
"@
    }
}

function Resolve-SPSSmtpSetting {
    <#
        .SYNOPSIS
        Resolves the effective email settings from the environment config and the legacy switch.

        .DESCRIPTION
        Single place that turns the SMTPEnabled / SMTPPreview config keys and the deprecated
        -EnableSmtp switch of SPSWeather.ps1 into what the run should do:
          - SMTPEnabled present in the config: its value decides, the switch is ignored (with a
            deprecation warning when it is also passed);
          - SMTPEnabled absent: the legacy switch decides (with a deprecation warning), so
            existing scheduled tasks keep sending mail;
          - SMTPPreview: write the email body to a file (independent from sending).
        A non-boolean value is never cast (the string 'false' would become $true): it is
        reported and treated as disabled. When sending is on but SMTPToAddress, SMTPFromAddress
        or SMTPServer is missing, sending is turned off with an explicit message.

        Returns Send, Preview, ConfigDefinesEnabled (so -Action Install knows whether the
        scheduled task can drop the deprecated switch) and Messages (warnings to display).

        .PARAMETER Config
        The environment configuration (hashtable loaded from the .psd1).

        .PARAMETER EnableSmtp
        The deprecated -EnableSmtp switch of the entry script.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Config,

        [Parameter()]
        [switch]
        $EnableSmtp
    )

    $messages = New-Object -TypeName System.Collections.ArrayList

    # Returns @{ Defined; Valid; Value } without casting arbitrary values to [bool].
    function Get-BooleanSetting {
        param($Config, [string]$Name)
        # A key that is written in the file counts as defined even when its value is $null: it is
        # then invalid (reported, treated as disabled) rather than silently ignored.
        $present = ($null -ne $Config) -and ($Config.Contains($Name))
        if (-not $present) { return @{ Defined = $false; Valid = $true; Value = $false } }
        $raw = $Config[$Name]
        if ($raw -is [bool]) { return @{ Defined = $true; Valid = $true; Value = $raw } }
        $parsed = $false
        if ($raw -is [string] -and [bool]::TryParse($raw.Trim(), [ref]$parsed)) {
            return @{ Defined = $true; Valid = $true; Value = $parsed }
        }
        return @{ Defined = $true; Valid = $false; Value = $false }
    }

    $enabled = Get-BooleanSetting -Config $Config -Name 'SMTPEnabled'
    $preview = Get-BooleanSetting -Config $Config -Name 'SMTPPreview'

    foreach ($setting in @(@{ Name = 'SMTPEnabled'; Result = $enabled }, @{ Name = 'SMTPPreview'; Result = $preview })) {
        if ($setting.Result.Defined -and -not $setting.Result.Valid) {
            [void]$messages.Add("$($setting.Name) must be `$true or `$false (got '$($Config[$setting.Name])'); treated as `$false.")
        }
    }

    if ($enabled.Defined) {
        $send = $enabled.Value
        if ($EnableSmtp) {
            [void]$messages.Add("-EnableSmtp is deprecated and ignored: SMTPEnabled = $($enabled.Value) in the configuration file takes precedence.")
        }
    }
    else {
        $send = [bool]$EnableSmtp
        if ($EnableSmtp) {
            [void]$messages.Add('-EnableSmtp is deprecated and will be removed in 4.0.0: set SMTPEnabled = $true in the configuration file instead (the switch still works while SMTPEnabled is not defined).')
        }
    }

    if ($send) {
        $missing = @('SMTPToAddress', 'SMTPFromAddress', 'SMTPServer' | Where-Object {
                -not (($null -ne $Config) -and $Config.Contains($_) -and -not [string]::IsNullOrWhiteSpace((@($Config[$_]) -join '')))
            })
        if ($missing.Count -gt 0) {
            $send = $false
            [void]$messages.Add("Email sending is enabled but $($missing -join ', ') is missing or empty in the configuration file: no email will be sent.")
        }
    }

    return [PSCustomObject]@{
        Send                 = [bool]$send
        Preview              = [bool]$preview.Value
        ConfigDefinesEnabled = [bool]$enabled.Defined
        Messages             = @($messages)
    }
}

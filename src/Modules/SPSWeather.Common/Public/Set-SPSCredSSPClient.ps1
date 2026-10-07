function Set-SPSCredSSPClient {
    <#
        .SYNOPSIS
        Enables the CredSSP client role and fresh-credentials delegation for SPSWeather.

        .DESCRIPTION
        SPSWeather reaches each farm over a CredSSP PSSession. The server side of CredSSP
        is owned by DSC on the SharePoint servers; this function configures only the CLIENT
        side on the machine that runs SPSWeather (e.g. an orchestration/PULL server that is
        not a SharePoint server). It is idempotent and honors -WhatIf.

        It enables CredSSP client authentication (WSMan) and writes the fresh-credentials
        delegation policy limited to the precise farm FQDNs (WSMAN/<fqdn> SPNs). When those
        settings are controlled by Group Policy it warns instead of fighting the GPO.

        Requires Windows and local administrator. See the SPSWeather wiki (Prerequisites).

        .PARAMETER DelegateComputer
        Farm server FQDNs to allow delegation to (e.g. 'app1.contoso.com'). Each is turned
        into a 'WSMAN/<fqdn>' SPN. Values are de-duplicated.

        .EXAMPLE
        Set-SPSCredSSPClient -DelegateComputer 'app1.contoso.com','app2.contoso.com'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        $DelegateComputer
    )

    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
        Write-Warning 'Set-SPSCredSSPClient is Windows-only; skipping CredSSP client setup.'
        return $false
    }

    $spns = $DelegateComputer |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { 'WSMAN/' + ($_.Trim()) } |
        Select-Object -Unique
    if (-not $spns) {
        Write-Warning 'Set-SPSCredSSPClient: no valid server FQDN supplied; nothing to do.'
        return $false
    }

    # 1. CredSSP client authentication (WSMan). Respect a GPO-controlled value.
    $authPath = 'WSMan:\localhost\Client\Auth\CredSSP'
    $authItem = Get-Item -Path $authPath -ErrorAction SilentlyContinue
    if ($null -ne $authItem -and "$($authItem.SourceOfValue)" -match 'GPO') {
        Write-Warning 'CredSSP client authentication is controlled by Group Policy; leaving it to the GPO.'
    }
    elseif ($null -eq $authItem -or "$($authItem.Value)" -ne 'true') {
        if ($PSCmdlet.ShouldProcess($authPath, 'Enable CredSSP client authentication')) {
            Set-Item -Path $authPath -Value $true -Force
        }
    }

    # 2. Fresh-credentials delegation policy, scoped to the farm SPNs.
    $polRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
    $polLeaf = "$polRoot\AllowFreshCredentials"
    if ($PSCmdlet.ShouldProcess($polRoot, 'Enable fresh-credentials delegation')) {
        if (-not (Test-Path -Path $polRoot)) { $null = New-Item -Path $polRoot -Force }
        $null = New-ItemProperty -Path $polRoot -Name 'AllowFreshCredentials' -Value 1 -PropertyType DWord -Force
        $null = New-ItemProperty -Path $polRoot -Name 'ConcatenateDefaults_AllowFresh' -Value 1 -PropertyType DWord -Force
        if (-not (Test-Path -Path $polLeaf)) { $null = New-Item -Path $polLeaf -Force }
    }

    # Existing SPN entries: add only the missing ones; warn on entries we did not set
    # (another policy - possibly a GPO - may manage this key).
    $existing = @{}
    $leafProps = Get-ItemProperty -Path $polLeaf -ErrorAction SilentlyContinue
    if ($null -ne $leafProps) {
        foreach ($p in $leafProps.PSObject.Properties) {
            if ($p.Name -match '^\d+$') { $existing[[string]$p.Value] = [int]$p.Name }
        }
    }
    $unexpected = @($existing.Keys | Where-Object { $spns -notcontains $_ })
    if ($unexpected.Count -gt 0) {
        Write-Warning "CredSSP delegation entries not managed by SPSWeather (possibly a Group Policy) are left untouched: $($unexpected -join ', ')."
    }
    $nextIndex = 1
    if ($existing.Count -gt 0) { $nextIndex = [int](($existing.Values | Measure-Object -Maximum).Maximum) + 1 }
    foreach ($spn in $spns) {
        if ($existing.ContainsKey($spn)) { continue }
        if ($PSCmdlet.ShouldProcess("$polLeaf => $spn", 'Add CredSSP delegation SPN')) {
            $null = New-ItemProperty -Path $polLeaf -Name ([string]$nextIndex) -Value $spn -PropertyType String -Force
            $nextIndex++
        }
    }

    return $true
}

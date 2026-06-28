function Resolve-SPSSqlAlias {
    <#
        .SYNOPSIS
        Resolves SQL Server client aliases (cliconfg) into their real targets.

        .DESCRIPTION
        SharePoint best practice is to reach SQL through a client alias created
        with cliconfg.exe (the SQL Server Client Network Utility). The alias name
        is what Get-SPDatabase returns, so the real server stays hidden. This
        function reads the alias definitions from the registry and returns, for
        each alias, the real server, instance, network protocol, port and the
        bitness where it is defined.

        Aliases live under:
          - 64-bit: HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo
          - 32-bit: HKLM:\SOFTWARE\Wow6432Node\Microsoft\MSSQLServer\Client\ConnectTo

        Each value's data has the form "<provider>,<server[\instance][,port]>"
        (or a named-pipe path), e.g. "DBMSSOCN,SQLPROD01\SP,1433". A SharePoint
        process is 64-bit, so a 64-bit alias is what matters at run time; this
        function also reports 32-bit definitions so a 32/64-bit mismatch can be
        surfaced.

        When -Name is omitted, every defined alias is returned. The registry is
        only present on Windows; on other platforms the function returns nothing.

        .PARAMETER Name
        One or more alias names to resolve. When omitted, all aliases are returned.

        .EXAMPLE
        Resolve-SPSSqlAlias

        .EXAMPLE
        Resolve-SPSSqlAlias -Name 'SPSQLCONTENT'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [System.String[]]
        $Name
    )

    $roots = @(
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo'; Bitness = '64-bit' }
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\MSSQLServer\Client\ConnectTo'; Bitness = '32-bit' }
    )

    $aliases = @{}

    foreach ($root in $roots) {
        if (-not (Test-Path -Path $root.Path)) { continue }
        $key = Get-Item -Path $root.Path -ErrorAction SilentlyContinue
        if ($null -eq $key) { continue }
        foreach ($valueName in $key.GetValueNames()) {
            if ([string]::IsNullOrEmpty($valueName)) { continue }
            if ($Name -and ($Name -notcontains $valueName)) { continue }
            $parsed = ConvertFrom-SPSSqlAliasValue -AliasName $valueName -RawValue ([string]$key.GetValue($valueName))
            $parsed | Add-Member -MemberType NoteProperty -Name Bitness -Value $root.Bitness -Force

            if ($aliases.ContainsKey($valueName)) {
                $existing = $aliases[$valueName]
                if ($existing.Bitness -ne $parsed.Bitness) { $existing.Bitness = 'both' }
            }
            else {
                $aliases[$valueName] = $parsed
            }
        }
    }

    return $aliases.Values
}

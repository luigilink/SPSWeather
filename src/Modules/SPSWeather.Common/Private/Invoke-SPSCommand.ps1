function Invoke-SPSCommand {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter()]
        [Object[]]
        $Arguments,

        [Parameter(Mandatory = $true)]
        [ScriptBlock]
        $ScriptBlock,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [Switch]
        $AllowFallback
    )

    $VerbosePreference = 'Continue'
    $baseScript = @"
        if (-not (Get-Module -Name SharePointServer))
        {
            Import-Module -Name SharePointServer -Verbose:`$false -WarningAction SilentlyContinue -DisableNameChecking
        }

"@

    $invokeArgs = @{
        ScriptBlock = [ScriptBlock]::Create($baseScript + $ScriptBlock.ToString())
    }
    if ($null -ne $Arguments) {
        $invokeArgs.Add("ArgumentList", $Arguments)
    }
    if ($null -eq $Credential) {
        throw 'You need to specify a Credential'
    }

    Write-Verbose -Message ("Executing on '$Server' as user $($Credential.UserName) " + `
            "(CredSSP preferred$(if ($AllowFallback) { ', Negotiate fallback enabled' }))")

    # Running garbage collection to resolve issues related to Azure DSC extension use
    [GC]::Collect()

    # Build the rich remoting session option; fall back to a default when a host's
    # New-PSSessionOption does not expose the timeout parameters (e.g. non-Windows).
    try {
        $sessionOption = New-PSSessionOption -OperationTimeout 0 -IdleTimeout 60000 -OpenTimeout 30000 -ErrorAction Stop
    }
    catch {
        $sessionOption = New-PSSessionOption
    }

    # CredSSP first (it delegates the credential for the remote cmdlets' second hop to
    # SQL / a file share); Negotiate only when explicitly allowed, and it cannot delegate.
    $authChain = @('CredSSP')
    if ($AllowFallback) { $authChain += 'Negotiate' }

    $session = $null
    $lastError = $null
    $authErrors = [System.Collections.Generic.List[string]]::new()
    foreach ($auth in $authChain) {
        try {
            $session = New-PSSession -ComputerName $Server `
                -Credential $Credential `
                -Authentication $auth `
                -Name "Microsoft.SharePoint.PSSession" `
                -SessionOption $sessionOption `
                -ErrorAction Stop
            if ($auth -ne 'CredSSP') {
                Write-Warning -Message ("CredSSP unavailable to '$Server'; using '$auth'. Second-hop steps " + `
                        "(SQL / file share) may fail without Kerberos delegation for $($Credential.UserName).")
            }
            break
        }
        catch {
            $lastError = $_
            $authErrors.Add("${auth}: $($_.Exception.Message)")
            Write-Warning -Message "Failed to open a '$auth' PSSession to '$Server': $($_.Exception.Message)"
        }
    }

    if ($null -eq $session) {
        if ($authChain.Count -eq 1) {
            # Keep the original CredSSP-only message for strict environments.
            throw "Failed to open a CredSSP PSSession to '$Server': $($lastError.Exception.Message)"
        }
        # Keep every method's error so a broken CredSSP setup and the fallback failure are both visible.
        throw ("Failed to open a remote PSSession to '$Server' using any of: $($authChain -join ', '). " + `
                "Errors - $($authErrors -join ' | ')")
    }

    $invokeArgs.Add("Session", $session)

    try {
        return Invoke-Command @invokeArgs -Verbose
    }
    catch {
        throw "Remote command on '$Server' failed: $($_.Exception.Message)"
    }
    finally {
        Remove-PSSession -Session $session
    }
}

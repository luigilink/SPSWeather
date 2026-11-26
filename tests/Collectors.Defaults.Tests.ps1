# A parameter a collector declares with a default must reach its remote script block even when the
# caller leaves it out: $PSBoundParameters only holds what the caller wrote, so passing it as the
# arguments of the block gave the block $null for every omitted parameter (a look-back of zero hours,
# a threshold of $null, an empty Farm label). The entry script calls the collectors with only
# -Server, -InstallAccount and -Farm, so it ran with the lost defaults.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force

    function global:Get-SPFarm {
        [PSCustomObject]@{ TimerService = [PSCustomObject]@{ JobHistoryEntries = $global:SPSWeatherDefaultsTest.Entries } }
    }
}

AfterAll {
    Remove-Item -Path Function:\global:Get-SPFarm -ErrorAction SilentlyContinue
    Remove-Variable -Name SPSWeatherDefaultsTest -Scope Global -ErrorAction SilentlyContinue
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Collector defaults reach the remote script block' {
    Context 'Get-SPSFailedTimerJob called as the entry script calls it' {
        BeforeAll {
            # 10 runs started two hours ago, 6 of them failed: inside the default window, above the default threshold
            $entries = 1..10 | ForEach-Object {
                [PSCustomObject]@{
                    StartTime          = (Get-Date).AddHours(-2)
                    JobDefinitionTitle = 'Health Analysis'
                    ServerName         = 'APP1'
                    Status             = $(if ($_ -le 6) { 'Failed' } else { 'Succeeded' })
                }
            }
            $global:SPSWeatherDefaultsTest = @{ Entries = $entries }
            $script:rows = InModuleScope SPSWeather.Common {
                Mock Invoke-SPSCommand { & $ScriptBlock @($Arguments) }
                $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))
                @(Get-SPSFailedTimerJob -Server 'APP1.contoso.com' -InstallAccount $cred -Farm 'CONTENT')
            }
        }

        It 'reports the failing job (the 24 hour look-back is applied)' {
            $script:rows.Count | Should -Be 1
            $script:rows[0].JobDefinitionTitle | Should -Be 'Health Analysis'
            $script:rows[0].FailedExecutions | Should -Be 6
            $script:rows[0].TotalExecutions | Should -Be 10
        }

        It 'applies the default threshold of 5 percent' {
            $script:rows[0].ThresholdPercentage | Should -Be 5
            $script:rows[0].IsInfo | Should -BeFalse
            $script:rows[0].Status | Should -Be 'Failure rate above 5% threshold'
        }

        It 'writes the farm label it was given' {
            $script:rows[0].Farm | Should -Be 'CONTENT'
        }

        It 'keeps the look-back: a run older than 24 hours is not counted' {
            $old = 1..4 | ForEach-Object {
                [PSCustomObject]@{ StartTime = (Get-Date).AddHours(-30); JobDefinitionTitle = 'Old Job'; ServerName = 'APP1'; Status = 'Failed' }
            }
            $global:SPSWeatherDefaultsTest = @{ Entries = $old }
            $rows = InModuleScope SPSWeather.Common {
                Mock Invoke-SPSCommand { & $ScriptBlock @($Arguments) }
                $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))
                @(Get-SPSFailedTimerJob -Server 'APP1.contoso.com' -InstallAccount $cred -Farm 'CONTENT')
            }
            $rows.Count | Should -Be 0
        }

        It 'still honours a value the caller writes' {
            $global:SPSWeatherDefaultsTest = @{ Entries = 1..10 | ForEach-Object {
                    [PSCustomObject]@{ StartTime = (Get-Date).AddHours(-2); JobDefinitionTitle = 'Health Analysis'; ServerName = 'APP1'; Status = $(if ($_ -le 6) { 'Failed' } else { 'Succeeded' }) }
                } }
            $rows = InModuleScope SPSWeather.Common {
                Mock Invoke-SPSCommand { & $ScriptBlock @($Arguments) }
                $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))
                @(Get-SPSFailedTimerJob -Server 'APP1.contoso.com' -InstallAccount $cred -Farm 'CONTENT' -FailureThresholdPercent 80)
            }
            $rows[0].ThresholdPercentage | Should -Be 80
            $rows[0].IsInfo | Should -BeTrue
        }
    }

    Context 'every collector that reads a parameter in its remote block' {
        BeforeDiscovery {
            $publicDir = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common/Public'
            $collectors = foreach ($file in Get-ChildItem -Path $publicDir -Filter '*.ps1' | Sort-Object -Property Name) {
                $tokens = $null; $errs = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errs)
                $function = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
                $reads = $ast.FindAll({
                        param($n)
                        $n -is [System.Management.Automation.Language.MemberExpressionAst] -and
                        $n.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                        $n.Expression.VariablePath.UserPath -eq 'params'
                    }, $true)
                if ($null -eq $function -or @($reads).Count -eq 0) { continue }
                $declared = @{}
                foreach ($p in $function.Body.ParamBlock.Parameters) {
                    if ($null -ne $p.DefaultValue) { $declared[$p.Name.VariablePath.UserPath] = $p.DefaultValue.Extent.Text }
                }
                $guarded = @($reads | Where-Object { $_ -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $_.Member.Value -eq 'ContainsKey' } |
                        ForEach-Object { $_.Arguments[0].Extent.Text.Trim("'`"") })
                $readNames = @($reads | Where-Object { $_ -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst] } |
                        ForEach-Object { $_.Member.Extent.Text.Trim("'`"") } | Select-Object -Unique)
                @{ Name = $file.BaseName; Read = $readNames; Declared = $declared; Guarded = $guarded }
            }
        }

        It '<Name> hands every defaulted parameter it reads to the block, with its default value' -ForEach $collectors {
            $name = $Name
            $captured = InModuleScope SPSWeather.Common -Parameters @{ Name = $name } {
                param($Name)
                $script:capturedArguments = $null
                Mock Invoke-SPSCommand { $script:capturedArguments = $Arguments; $null }
                $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))
                $null = & $Name -Server 'APP1.contoso.com' -InstallAccount $cred
                $script:capturedArguments
            }
            foreach ($key in $Read) {
                if ($Guarded -contains $key) { continue }
                $declaredKey = @($Declared.Keys | Where-Object { $_ -eq $key })
                if ($declaredKey.Count -eq 0) { continue }
                $captured.ContainsKey($key) | Should -BeTrue -Because "the remote block of $Name reads `$params.$key, whose default is $($Declared[$declaredKey[0]])"
                $expected = Invoke-Expression -Command $Declared[$declaredKey[0]]
                $captured[$key] | Should -Be $expected -Because "$key must reach the block with its declared default"
            }
        }
    }
}

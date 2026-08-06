Set-StrictMode -Version Latest

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\SubscriptionPortability.Foundation.psm1'
Import-Module $modulePath -Force

Describe 'SubscriptionPortability.Foundation' {
    It 'masks identifiers to the final four characters' {
        Get-MaskedIdentifier -Identifier '12345678-1234-1234-1234-1234567890ab' | Should Be '...90ab'
    }

    It 'produces a stable deterministic suffix for the same inputs' {
        $first = Get-DeterministicSuffix -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -SubscriptionId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -Environment 'dev' -WorkloadRegionCode 'deu'
        $second = Get-DeterministicSuffix -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -SubscriptionId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -Environment 'dev' -WorkloadRegionCode 'deu'

        $first | Should Be $second
    }

    It 'produces different suffixes for different subscriptions' {
        $first = Get-DeterministicSuffix -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -SubscriptionId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -Environment 'dev' -WorkloadRegionCode 'deu'
        $second = Get-DeterministicSuffix -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -SubscriptionId 'cccccccc-cccc-cccc-cccc-cccccccccccc' -Environment 'dev' -WorkloadRegionCode 'deu'

        $first | Should Not Be $second
    }

    It 'normalizes storage account names to Azure rules' {
        $name = New-AzureStorageAccountName -Prefix 'ST-App_DEV-deu' -Suffix '0f3a5c7d9e'
        $name | Should Match '^[a-z][a-z0-9]{2,23}$'
        ($name.Length -le 24) | Should Be $true
    }

    It 'normalizes key vault names to Azure rules' {
        $name = New-AzureKeyVaultName -Prefix 'KV-App_DEV-deu' -Suffix '0f3a5c7d9e'
        $name | Should Match '^[a-z][a-z0-9-]{1,22}[a-z0-9]$'
        ($name.Length -le 24) | Should Be $true
    }

    It 'normalizes web app names to Azure rules' {
        $name = New-AzureWebAppName -Prefix 'APP_DEV-DEU' -Suffix '0f3a5c7d9e'
        $name | Should Match '^[a-z0-9-]+$'
        ($name.Length -le 60) | Should Be $true
    }

    It 'creates a deterministic portable naming set' {
        $names = New-PortableNameSet -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -SubscriptionId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -Environment 'dev' -WorkloadRegionCode 'deu'
        $names.backendResourceGroup | Should Match '^rg-dev-tfstate-deu-'
        $names.backendStorageAccount | Should Match '^st[a-z0-9]{2,23}$'
    }

    It 'aggregates passed and warning results to GO' {
        $results = @(
            New-AssessmentResult -Name 'One' -Status 'Passed' -Message 'ok'
            New-AssessmentResult -Name 'Two' -Status 'Warning' -Message 'warn'
        )

        $outcome = Get-AssessmentOutcome -Results $results
        $outcome.overallStatus | Should Be 'GO'
        $outcome.warnings.Count | Should Be 1
    }

    It 'aggregates blocked results to NO-GO' {
        $results = @(
            New-AssessmentResult -Name 'One' -Status 'Blocked' -Message 'stop'
        )

        $outcome = Get-AssessmentOutcome -Results $results
        $outcome.overallStatus | Should Be 'NO-GO'
        $outcome.blockers.Count | Should Be 1
    }

    It 'treats NotVerifiable as NO-GO' {
        $results = @(
            New-AssessmentResult -Name 'One' -Status 'NotVerifiable' -Message 'unknown'
        )

        $outcome = Get-AssessmentOutcome -Results $results
        $outcome.overallStatus | Should Be 'NO-GO'
    }

    It 'serializes a profile without secret-like fields' {
        $context = New-OfflineAzureContext -ExpectedTenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -ExpectedSubscriptionId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        $names = New-PortableNameSet -TenantId $context.tenantId -SubscriptionId $context.id -Environment 'dev' -WorkloadRegionCode 'deu'
        $profileParams = @{
            Environment          = 'dev'
            Context              = $context
            WorkloadLocation     = 'denmarkeast'
            WorkloadRegionCode   = 'deu'
            MonitoringLocation   = 'swedencentral'
            MonitoringRegionCode = 'swe'
            AddressSpace         = '10.0.0.0/16'
            VmSize               = 'Standard_B1s'
            AppServiceSku        = 'B1'
            ProposedNames        = $names
            ProviderResults      = @()
            RegionResults        = @()
            SkuResults           = @()
            QuotaResults         = @()
            OverallStatus        = 'NO-GO'
            Blockers             = @('offline')
            Warnings             = @()
        }

        $profile = New-SubscriptionPortabilityProfile @profileParams

        $json = $profile | ConvertTo-Json -Depth 10

        $json | Should Not Match 'client_secret|token|private_key|ssh-rsa'
    }

    It 'marks expected tenant mismatch as NO-GO with TenantMismatch code' {
        $context = [pscustomobject]@{
            tenantId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            id       = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        }

        $results = @(Test-ExpectedContextMatch -Context $context -ExpectedTenantId 'cccccccc-cccc-cccc-cccc-cccccccccccc')
        $outcome = Get-AssessmentOutcome -Results $results

        $results[0].status | Should Be 'Blocked'
        $results[0].code | Should Be 'TenantMismatch'
        $outcome.overallStatus | Should Be 'NO-GO'
        $outcome.blockers[0] | Should Match '\[TenantMismatch\]'
    }

    It 'marks expected subscription mismatch as NO-GO with SubscriptionMismatch code' {
        $context = [pscustomobject]@{
            tenantId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            id       = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        }

        $results = @(Test-ExpectedContextMatch -Context $context -ExpectedSubscriptionId 'cccccccc-cccc-cccc-cccc-cccccccccccc')
        $outcome = Get-AssessmentOutcome -Results $results

        $results[0].status | Should Be 'Blocked'
        $results[0].code | Should Be 'SubscriptionMismatch'
        $outcome.overallStatus | Should Be 'NO-GO'
        $outcome.blockers[0] | Should Match '\[SubscriptionMismatch\]'
    }

    It 'marks disabled subscription state as NO-GO with SubscriptionDisabled code' {
        $context = [pscustomobject]@{ state = 'Disabled' }
        $stateResult = Get-SubscriptionStateAssessment -Context $context
        $outcome = Get-AssessmentOutcome -Results @($stateResult)

        $stateResult.status | Should Be 'Blocked'
        $stateResult.code | Should Be 'SubscriptionDisabled'
        $outcome.overallStatus | Should Be 'NO-GO'
    }

    It 'parses valid stdout JSON even when stderr contains a warning' {
        $processInvoker = {
            param($Arguments)
            [pscustomobject]@{
                ExitCode = 0
                StdOut   = '{"tenantId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}'
                StdErr   = 'WARNING: using cached profile'
                Success  = $true
            }
        }

        $result = Invoke-AzureCliJson -Arguments @('account', 'show', '-o', 'json') -ProcessInvoker $processInvoker -AllowFailure
        $result.Success | Should Be $true
        $result.ParsedJson.id | Should Be 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    }

    It 'returns structured failure for non-zero Azure CLI exit code' {
        $processInvoker = {
            param($Arguments)
            [pscustomobject]@{
                ExitCode = 2
                StdOut   = ''
                StdErr   = 'ERROR: command failed'
                Success  = $false
            }
        }

        $result = Invoke-AzureCliJson -Arguments @('account', 'show', '-o', 'json') -ProcessInvoker $processInvoker -AllowFailure
        $result.Success | Should Be $false
        $result.FailureKind | Should Be 'NonZeroExit'
        $result.SafeMessage | Should Match 'non-zero exit code'
    }

    It 'returns structured failure for empty stdout on zero exit code' {
        $processInvoker = {
            param($Arguments)
            [pscustomobject]@{
                ExitCode = 0
                StdOut   = ''
                StdErr   = ''
                Success  = $true
            }
        }

        $result = Invoke-AzureCliJson -Arguments @('account', 'show', '-o', 'json') -ProcessInvoker $processInvoker -AllowFailure
        $result.Success | Should Be $false
        $result.FailureKind | Should Be 'EmptyStdOut'
    }

    It 'returns structured failure for invalid JSON stdout' {
        $processInvoker = {
            param($Arguments)
            [pscustomobject]@{
                ExitCode = 0
                StdOut   = 'not-json'
                StdErr   = ''
                Success  = $true
            }
        }

        $result = Invoke-AzureCliJson -Arguments @('account', 'show', '-o', 'json') -ProcessInvoker $processInvoker -AllowFailure
        $result.Success | Should Be $false
        $result.FailureKind | Should Be 'InvalidJson'
    }

    It 'serializes a failure profile with unavailable IDs as valid JSON' {
        $context = New-UnavailableAzureContext
        $names = New-PortableNameSetForFailure -Environment 'dev' -WorkloadRegionCode 'deu'
        $profileParams = @{
            Environment          = 'dev'
            Context              = $context
            WorkloadLocation     = 'denmarkeast'
            WorkloadRegionCode   = 'deu'
            MonitoringLocation   = 'swedencentral'
            MonitoringRegionCode = 'swe'
            AddressSpace         = '10.0.0.0/16'
            VmSize               = 'Standard_B1s'
            AppServiceSku        = 'B1'
            ProposedNames        = $names
            ProviderResults      = @()
            RegionResults        = @()
            SkuResults           = @()
            QuotaResults         = @()
            OverallStatus        = 'NO-GO'
            Blockers             = @('[AzureContextUnavailable] AzureContext: context unavailable')
            Warnings             = @()
        }

        $profile = New-SubscriptionPortabilityProfile @profileParams
        $profile.tenantId | Should Be $null
        $profile.subscriptionId | Should Be $null
        $profile.maskedTenantId | Should Be '<unavailable>'
        $profile.maskedSubscriptionId | Should Be '<unavailable>'
        $profile.assessmentOutcomeType | Should Be 'Failure'

        { $profile | ConvertTo-Json -Depth 10 } | Should Not Throw
    }

    It 'classifies unavailable context as NO-GO without throwing' {
        Mock -ModuleName SubscriptionPortability.Foundation Get-Command { $null }

        $assessment = Get-ActiveAzureContextAssessment
        $assessment.Result.status | Should Be 'Blocked'
        $assessment.Result.code | Should Be 'AzureCliUnavailable'

        $outcome = Get-AssessmentOutcome -Results @($assessment.Result)
        $outcome.overallStatus | Should Be 'NO-GO'
    }

    It 'failed context results can never aggregate to GO' {
        $results = @(
            New-AssessmentResult -Name 'AzureContext' -Status 'Blocked' -Code 'AzureContextUnavailable' -Message 'No context'
            New-AssessmentResult -Name 'ComputeQuota' -Status 'Warning' -Message 'Advisory only'
        )

        $outcome = Get-AssessmentOutcome -Results $results
        $outcome.overallStatus | Should Be 'NO-GO'
    }
}
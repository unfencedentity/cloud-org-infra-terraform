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
}
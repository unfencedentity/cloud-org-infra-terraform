<#
.SYNOPSIS
Performs a read-only subscription portability assessment for Terraform onboarding.

.DESCRIPTION
Validates the current Azure CLI tenant and subscription context, checks provider and regional
readiness, evaluates VM and App Service portability constraints, and generates a deterministic,
non-secret onboarding profile for later backend bootstrap and CI/CD capabilities.

.PARAMETER Environment
Deployment environment name. Defaults to dev.

.PARAMETER WorkloadLocation
Azure location for workload resources. Defaults to denmarkeast.

.PARAMETER WorkloadRegionCode
Short region code used in naming. Defaults to deu.

.PARAMETER MonitoringLocation
Azure location for monitoring resources. Defaults to swedencentral.

.PARAMETER MonitoringRegionCode
Short region code used in naming for monitoring. Defaults to swe.

.PARAMETER AddressSpace
Proposed workload VNet address space. Defaults to 10.0.0.0/16.

.PARAMETER VmSize
VM SKU to validate. Defaults to Standard_B1s based on the proven cloud-org-infra deployment.

.PARAMETER AppServiceSku
Linux App Service plan SKU to validate. Defaults to B1.

.PARAMETER ExpectedTenantId
Optional tenant guardrail. If supplied and the active Azure CLI tenant does not match, the result is NO-GO.

.PARAMETER ExpectedSubscriptionId
Optional subscription guardrail. If supplied and the active Azure CLI subscription does not match, the result is NO-GO.

.PARAMETER OutputPath
Path for the generated onboarding profile JSON. Defaults to .generated/onboarding/<environment>-profile.json.

.PARAMETER PassThru
Returns the generated profile object.

.PARAMETER Offline
Skips live Azure CLI validation and generates a dry-run NO-GO profile with NotVerifiable Azure checks.

.EXAMPLE
./automation/onboarding/Invoke-SubscriptionPortabilityAssessment.ps1 `
    -ExpectedTenantId '<EXPECTED_TENANT_ID>' `
    -ExpectedSubscriptionId '<EXPECTED_SUBSCRIPTION_ID>' `
    -PassThru

.EXAMPLE
./automation/onboarding/Invoke-SubscriptionPortabilityAssessment.ps1 `
    -Offline `
    -PassThru
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidatePattern('^(dev|test|prod)$')]
    [string]$Environment = 'dev',

    [ValidateNotNullOrEmpty()]
    [string]$WorkloadLocation = 'denmarkeast',

    [ValidatePattern('^[a-z0-9]{2,8}$')]
    [string]$WorkloadRegionCode = 'deu',

    [ValidateNotNullOrEmpty()]
    [string]$MonitoringLocation = 'swedencentral',

    [ValidatePattern('^[a-z0-9]{2,8}$')]
    [string]$MonitoringRegionCode = 'swe',

    [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$')]
    [string]$AddressSpace = '10.0.0.0/16',

    [ValidateNotNullOrEmpty()]
    [string]$VmSize = 'Standard_B1s',

    [ValidateNotNullOrEmpty()]
    [string]$AppServiceSku = 'B1',

    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$ExpectedTenantId,

    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$ExpectedSubscriptionId,

    [string]$OutputPath,

    [switch]$PassThru,

    [switch]$Offline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'SubscriptionPortability.Foundation.psm1'
Import-Module $modulePath -Force

try {
    $resolvedOutputPath = Resolve-AssessmentOutputPath -Environment $Environment -OutputPath $OutputPath
    $providerDefinitions = Get-RequiredProviderDefinitions

    if ($Offline) {
        $context = New-OfflineAzureContext -ExpectedTenantId $ExpectedTenantId -ExpectedSubscriptionId $ExpectedSubscriptionId
        $expectedContextResults = @(
            Test-ExpectedContextMatch -Context $context -ExpectedTenantId $ExpectedTenantId -ExpectedSubscriptionId $ExpectedSubscriptionId
        )
        $providerResults = @($providerDefinitions | ForEach-Object {
            New-AssessmentResult -Name $_.Namespace -Status 'NotVerifiable' -Message 'Offline mode does not query Azure provider registration.'
        })
        $regionResults = @(
            New-AssessmentResult -Name 'WorkloadLocation' -Status 'NotVerifiable' -Message 'Offline mode does not query Azure location availability.'
            New-AssessmentResult -Name 'MonitoringLocation' -Status 'NotVerifiable' -Message 'Offline mode does not query Azure location availability.'
        )
        $resourceTypeResults = @($providerDefinitions | ForEach-Object {
            foreach ($resourceType in $_.ResourceTypes) {
                New-AssessmentResult -Name ("{0}/{1}" -f $_.Namespace, $resourceType) -Status 'NotVerifiable' -Message 'Offline mode does not query provider resource type metadata.'
            }
        })
        $vmSkuResult = New-AssessmentResult -Name 'VmSku' -Status 'NotVerifiable' -Message 'Offline mode does not query Azure VM SKU availability.'
        $appServiceSkuResult = New-AssessmentResult -Name 'AppServiceSku' -Status 'NotVerifiable' -Message 'Offline mode does not query Azure App Service SKU availability.'
        $quotaResult = New-AssessmentResult -Name 'ComputeQuota' -Status 'NotVerifiable' -Message 'Offline mode does not query Azure compute quota usage.'
        $subscriptionStateResult = New-AssessmentResult -Name 'SubscriptionState' -Status 'NotVerifiable' -Message 'Offline mode does not query Azure subscription state.'
        $contextAvailabilityResult = New-AssessmentResult -Name 'AzureContext' -Status 'NotVerifiable' -Code 'AzureContextOffline' -Message 'Offline mode does not query Azure account context.'
    }
    else {
        $contextAssessment = Get-ActiveAzureContextAssessment
        $context = $contextAssessment.Context
        $contextAvailabilityResult = $contextAssessment.Result

        if ($contextAvailabilityResult.status -eq 'Passed') {
            $expectedContextResults = @(
                Test-ExpectedContextMatch -Context $context -ExpectedTenantId $ExpectedTenantId -ExpectedSubscriptionId $ExpectedSubscriptionId
            )
            $subscriptionStateResult = Get-SubscriptionStateAssessment -Context $context

            $locationCatalogAssessment = Get-AccountLocationAssessment
            if ($locationCatalogAssessment.Result.status -eq 'Passed') {
                $locations = @($locationCatalogAssessment.Locations)
                $regionResults = @(
                    Test-LocationPair -RegionCode $WorkloadRegionCode -Location $WorkloadLocation -AvailableLocations $locations -Label 'Workload'
                    Test-LocationPair -RegionCode $MonitoringRegionCode -Location $MonitoringLocation -AvailableLocations $locations -Label 'Monitoring'
                )
            }
            else {
                $regionResults = @(
                    $locationCatalogAssessment.Result
                    New-AssessmentResult -Name 'WorkloadLocation' -Status 'Blocked' -Code 'LocationCatalogUnavailable' -Message 'Workload location cannot be validated because the Azure location catalog is unavailable.'
                    New-AssessmentResult -Name 'MonitoringLocation' -Status 'Blocked' -Code 'LocationCatalogUnavailable' -Message 'Monitoring location cannot be validated because the Azure location catalog is unavailable.'
                )
            }

            $providerResults = Get-ProviderRegistrationResults -ProviderDefinitions $providerDefinitions
            $resourceTypeResults = Get-ProviderResourceTypeLocationResults -ProviderDefinitions $providerDefinitions -WorkloadLocation $WorkloadLocation -MonitoringLocation $MonitoringLocation
            $vmSkuResult = Get-VmSkuAssessment -Location $WorkloadLocation -VmSize $VmSize
            $appServiceSkuResult = Get-AppServiceSkuAssessment -Location $WorkloadLocation -AppServiceSku $AppServiceSku
            $quotaResult = Get-ComputeQuotaAssessment -Location $WorkloadLocation -VmSkuMetadata $vmSkuResult.data
        }
        else {
            $expectedContextResults = @()
            $subscriptionStateResult = New-AssessmentResult -Name 'SubscriptionState' -Status 'NotVerifiable' -Code 'SubscriptionStateUnknown' -Message 'Subscription state cannot be verified because the Azure account context is unavailable.'
            $providerResults = @($providerDefinitions | ForEach-Object {
                New-AssessmentResult -Name $_.Namespace -Status 'NotVerifiable' -Code 'ProviderStateUnavailable' -Message 'Provider registration cannot be verified because the Azure account context is unavailable.'
            })
            $regionResults = @(
                New-AssessmentResult -Name 'WorkloadLocation' -Status 'NotVerifiable' -Code 'LocationCatalogUnavailable' -Message 'Workload location cannot be verified because the Azure account context is unavailable.'
                New-AssessmentResult -Name 'MonitoringLocation' -Status 'NotVerifiable' -Code 'LocationCatalogUnavailable' -Message 'Monitoring location cannot be verified because the Azure account context is unavailable.'
            )
            $resourceTypeResults = @($providerDefinitions | ForEach-Object {
                foreach ($resourceType in $_.ResourceTypes) {
                    New-AssessmentResult -Name ("{0}/{1}" -f $_.Namespace, $resourceType) -Status 'NotVerifiable' -Code 'ProviderResourceTypeUnavailable' -Message 'Resource type metadata cannot be verified because the Azure account context is unavailable.'
                }
            })
            $vmSkuResult = New-AssessmentResult -Name 'VmSku' -Status 'NotVerifiable' -Code 'VmSkuUnavailable' -Message 'VM SKU availability cannot be verified because the Azure account context is unavailable.'
            $appServiceSkuResult = New-AssessmentResult -Name 'AppServiceSku' -Status 'NotVerifiable' -Code 'AppServiceSkuUnavailable' -Message 'App Service SKU availability cannot be verified because the Azure account context is unavailable.'
            $quotaResult = New-AssessmentResult -Name 'ComputeQuota' -Status 'NotVerifiable' -Code 'ComputeQuotaUnavailable' -Message 'Compute quota cannot be verified because the Azure account context is unavailable.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($context.tenantId) -or [string]::IsNullOrWhiteSpace($context.id)) {
        $proposedNames = New-PortableNameSetForFailure -Environment $Environment -WorkloadRegionCode $WorkloadRegionCode
    }
    else {
        $proposedNames = New-PortableNameSet -TenantId $context.tenantId -SubscriptionId $context.id -Environment $Environment -WorkloadRegionCode $WorkloadRegionCode
    }

    $allResults = @(
        $contextAvailabilityResult
        $expectedContextResults
        $subscriptionStateResult
        $providerResults
        $regionResults
        $resourceTypeResults
        $vmSkuResult
        $appServiceSkuResult
        $quotaResult
    )

    $outcome = Get-AssessmentOutcome -Results $allResults

    $profileParams = @{
        Environment          = $Environment
        Context              = $context
        WorkloadLocation     = $WorkloadLocation
        WorkloadRegionCode   = $WorkloadRegionCode
        MonitoringLocation   = $MonitoringLocation
        MonitoringRegionCode = $MonitoringRegionCode
        AddressSpace         = $AddressSpace
        VmSize               = $VmSize
        AppServiceSku        = $AppServiceSku
        ProposedNames        = $proposedNames
        ProviderResults      = $providerResults
        RegionResults        = @($regionResults + $resourceTypeResults)
        SkuResults           = @($vmSkuResult, $appServiceSkuResult)
        QuotaResults         = @($quotaResult)
        OverallStatus        = $outcome.overallStatus
        Blockers             = $outcome.blockers
        Warnings             = $outcome.warnings
    }

    $profile = New-SubscriptionPortabilityProfile @profileParams

    $outputDirectory = Split-Path -Path $resolvedOutputPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path $outputDirectory)) {
        if ($PSCmdlet.ShouldProcess($outputDirectory, 'Create local onboarding output directory')) {
            $null = New-Item -Path $outputDirectory -ItemType Directory -Force
        }
    }

    if ($PSCmdlet.ShouldProcess($resolvedOutputPath, 'Write onboarding profile JSON')) {
        $profile | ConvertTo-Json -Depth 12 | Set-Content -Path $resolvedOutputPath -Encoding utf8
    }

    Write-AssessmentSummary -Profile $profile -Context $context -OutputPath $resolvedOutputPath

    if ($PassThru) {
        return $profile
    }
}
catch {
    $message = $_.Exception.Message
    Write-Error ("Unexpected script defect encountered: {0}" -f $message)
    throw
}
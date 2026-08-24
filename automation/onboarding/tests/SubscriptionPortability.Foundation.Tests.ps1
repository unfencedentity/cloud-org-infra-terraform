Set-StrictMode -Version Latest

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\SubscriptionPortability.Foundation.psm1'
$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Invoke-SubscriptionPortabilityAssessment.ps1'
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

        $assessmentProfile = New-SubscriptionPortabilityProfile @profileParams

        $json = $assessmentProfile | ConvertTo-Json -Depth 10

        $json | Should Not Match 'client_secret|token|private_key|ssh-rsa'
    }

    It 'accepts a canonical tenant id in offline script execution' {
        $outputPath = Join-Path $env:TEMP ('subscription-portability-tenant-' + [guid]::NewGuid().ToString() + '.json')

        try {
            { & $scriptPath -Offline -ExpectedTenantId '12345678-1234-1234-1234-123456789abc' -OutputPath $outputPath | Out-Null } | Should Not Throw
        }
        finally {
            if (Test-Path $outputPath) {
                Remove-Item -Path $outputPath -Force
            }
        }
    }

    It 'accepts a canonical subscription id in offline script execution' {
        $outputPath = Join-Path $env:TEMP ('subscription-portability-subscription-' + [guid]::NewGuid().ToString() + '.json')

        try {
            { & $scriptPath -Offline -ExpectedSubscriptionId '87654321-4321-4321-4321-cba987654321' -OutputPath $outputPath | Out-Null } | Should Not Throw
        }
        finally {
            if (Test-Path $outputPath) {
                Remove-Item -Path $outputPath -Force
            }
        }
    }

    It 'rejects a hyphen-only tenant id' {
        $threw = $false
        try {
            & $scriptPath -Offline -ExpectedTenantId '------------------------------------' -ErrorAction Stop | Out-Null
        }
        catch {
            $threw = $true
        }

        $threw | Should Be $true
    }

    It 'rejects an invalid subscription id' {
        $threw = $false
        try {
            & $scriptPath -Offline -ExpectedSubscriptionId 'not-a-guid' -ErrorAction Stop | Out-Null
        }
        catch {
            $threw = $true
        }

        $threw | Should Be $true
    }

    It 'accepts the default IPv4 CIDR in offline script execution' {
        $outputPath = Join-Path $env:TEMP ('subscription-portability-cidr-' + [guid]::NewGuid().ToString() + '.json')

        try {
            { & $scriptPath -Offline -OutputPath $outputPath | Out-Null } | Should Not Throw
        }
        finally {
            if (Test-Path $outputPath) {
                Remove-Item -Path $outputPath -Force
            }
        }
    }

    It 'rejects an impossible IPv4 CIDR' {
        $threw = $false
        try {
            & $scriptPath -Offline -AddressSpace '999.999.999.999/99' -ErrorAction Stop | Out-Null
        }
        catch {
            $threw = $true
        }

        $threw | Should Be $true
    }

    It 'rejects an oversized IPv4 prefix' {
        $threw = $false
        try {
            & $scriptPath -Offline -AddressSpace '10.0.0.0/33' -ErrorAction Stop | Out-Null
        }
        catch {
            $threw = $true
        }

        $threw | Should Be $true
    }

    It 'rejects an IPv6 CIDR' {
        $threw = $false
        try {
            & $scriptPath -Offline -AddressSpace '2001:db8::/32' -ErrorAction Stop | Out-Null
        }
        catch {
            $threw = $true
        }

        $threw | Should Be $true
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

    It 'classifies list-locations non-zero exit as blocked LocationCatalogUnavailable without throwing' {
        $processInvoker = {
            param($Arguments)
            [pscustomobject]@{
                ExitCode = 3
                StdOut   = ''
                StdErr   = 'ERROR: unable to list locations'
                Success  = $false
            }
        }

        $assessment = $null
        $threw = $false
        try {
            $assessment = Get-AccountLocationAssessment -ProcessInvoker $processInvoker
        }
        catch {
            $threw = $true
        }

        $threw | Should Be $false

        $assessment.Result.status | Should Be 'Blocked'
        $assessment.Result.code | Should Be 'LocationCatalogUnavailable'

        $outcome = Get-AssessmentOutcome -Results @($assessment.Result)
        $outcome.overallStatus | Should Be 'NO-GO'
    }

    It 'classifies list-locations empty stdout as blocked LocationCatalogUnavailable without throwing' {
        $processInvoker = {
            param($Arguments)
            [pscustomobject]@{
                ExitCode = 0
                StdOut   = ''
                StdErr   = ''
                Success  = $true
            }
        }

        $assessment = $null
        $threw = $false
        try {
            $assessment = Get-AccountLocationAssessment -ProcessInvoker $processInvoker
        }
        catch {
            $threw = $true
        }

        $threw | Should Be $false

        $assessment.Result.status | Should Be 'Blocked'
        $assessment.Result.code | Should Be 'LocationCatalogUnavailable'
    }

    It 'classifies list-locations invalid JSON as blocked LocationCatalogUnavailable without throwing' {
        $processInvoker = {
            param($Arguments)
            [pscustomobject]@{
                ExitCode = 0
                StdOut   = 'not-json'
                StdErr   = ''
                Success  = $true
            }
        }

        $assessment = $null
        $threw = $false
        try {
            $assessment = Get-AccountLocationAssessment -ProcessInvoker $processInvoker
        }
        catch {
            $threw = $true
        }

        $threw | Should Be $false

        $assessment.Result.status | Should Be 'Blocked'
        $assessment.Result.code | Should Be 'LocationCatalogUnavailable'
    }

    It 'maps account-show non-zero exit to AzureContextUnavailable' {
        Mock -ModuleName SubscriptionPortability.Foundation Get-Command { [pscustomobject]@{ Name = 'az' } }
        Mock -ModuleName SubscriptionPortability.Foundation Invoke-AzureCliJson {
            [pscustomobject]@{
                ExitCode    = 2
                StdOut      = ''
                StdErr      = 'simulated failure'
                ParsedJson  = $null
                Success     = $false
                FailureKind = 'NonZeroExit'
                SafeMessage = 'simulated failure'
                Succeeded   = $false
                Data        = $null
                RawOutput   = 'simulated failure'
            }
        }

        $assessment = Get-ActiveAzureContextAssessment
        $assessment.Result.status | Should Be 'Blocked'
        $assessment.Result.code | Should Be 'AzureContextUnavailable'
    }

    It 'maps account-show invalid JSON to AzureContextInvalid' {
        Mock -ModuleName SubscriptionPortability.Foundation Get-Command { [pscustomobject]@{ Name = 'az' } }
        Mock -ModuleName SubscriptionPortability.Foundation Invoke-AzureCliJson {
            [pscustomobject]@{
                ExitCode    = 0
                StdOut      = 'not-json'
                StdErr      = ''
                ParsedJson  = $null
                Success     = $false
                FailureKind = 'InvalidJson'
                SafeMessage = 'stdout not json'
                Succeeded   = $false
                Data        = $null
                RawOutput   = ''
            }
        }

        $assessment = Get-ActiveAzureContextAssessment
        $assessment.Result.status | Should Be 'Blocked'
        $assessment.Result.code | Should Be 'AzureContextInvalid'
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

        $assessmentProfile = New-SubscriptionPortabilityProfile @profileParams
        $assessmentProfile.tenantId | Should Be $null
        $assessmentProfile.subscriptionId | Should Be $null
        $assessmentProfile.maskedTenantId | Should Be '<unavailable>'
        $assessmentProfile.maskedSubscriptionId | Should Be '<unavailable>'
        $assessmentProfile.assessmentOutcomeType | Should Be 'Failure'

        { $assessmentProfile | ConvertTo-Json -Depth 10 } | Should Not Throw
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

    It 'returns a structured AzureCliUnavailable failure when Azure CLI cannot be resolved' {
        Mock -ModuleName SubscriptionPortability.Foundation Get-Command { $null }

        $result = Invoke-AzureCliProcess -Arguments @('version', '--output', 'json')
        $result.Success | Should Be $false
        $result.ExitCode | Should Be 127
        $result.StdErr | Should Match 'not found'
    }

    InModuleScope SubscriptionPortability.Foundation {
        It 'resolves the Azure CLI command to its full Source path' {
            Mock Get-Command { [pscustomobject]@{ Name = 'az'; Source = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd' } }

            $resolved = Resolve-AzureCliCommandPath
            $resolved | Should Be 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
        }

        It 'resolves to null when Azure CLI is not found' {
            Mock Get-Command { $null }

            Resolve-AzureCliCommandPath | Should Be $null
        }

        It 'resolves to null when the resolved command has no Source' {
            Mock Get-Command { [pscustomobject]@{ Name = 'az'; Source = '' } }

            Resolve-AzureCliCommandPath | Should Be $null
        }
    }

    It 'launches a resolved Windows az.cmd and preserves arguments containing cmd.exe metacharacters literally, with no second command executed' {
        $fakeCliDir = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) '.native-argv-probe'
        $fakeCliBinDir = Join-Path $fakeCliDir 'wbin'
        New-Item -Path $fakeCliBinDir -ItemType Directory -Force | Out-Null
        $outputPath = Join-Path $fakeCliDir 'output.json'
        $injectedMarkerPath = Join-Path $fakeCliDir 'injected.txt'
        $captureSourcePath = Join-Path $fakeCliDir 'capture.cs'
        $nativePythonPath = Join-Path $fakeCliDir 'python.exe'
        $azCmdPath = Join-Path $fakeCliBinDir 'az.cmd'

        $captureSource = @'
using System;
using System.IO;
using System.Text;

internal static class ArgumentCapture
{
    private static string Escape(string value)
    {
        var builder = new StringBuilder(value.Length + 2);
        foreach (var character in value)
        {
            switch (character)
            {
                case '\\': builder.Append("\\\\"); break;
                case '"': builder.Append("\\\""); break;
                case '\r': builder.Append("\\r"); break;
                case '\n': builder.Append("\\n"); break;
                case '\t': builder.Append("\\t"); break;
                default: builder.Append(character); break;
            }
        }
        return builder.ToString();
    }

    public static void Main(string[] arguments)
    {
        var outputPath = Environment.GetEnvironmentVariable("FAKE_AZ_OUTPUT_PATH");
        var json = new StringBuilder("[");
        for (var index = 0; index < arguments.Length; index++)
        {
            if (index > 0) json.Append(',');
            json.Append('"').Append(Escape(arguments[index])).Append('"');
        }
        json.Append(']');
        File.WriteAllText(outputPath, json.ToString(), Encoding.UTF8);
    }
}
'@
        Set-Content -Path $captureSourcePath -Value $captureSource -Encoding ascii
        & "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe /out:$nativePythonPath $captureSourcePath
        $LASTEXITCODE | Should Be 0
        $env:FAKE_AZ_OUTPUT_PATH = $outputPath
        $env:FAKE_AZ_CMD_PATH = $azCmdPath
        Set-Content -Path $azCmdPath -Value '@echo off' , '"%~dp0..\python.exe" -IBm azure.cli %*' -Encoding ascii

        $originalPath = $env:PATH
        try {
            $env:PATH = "$fakeCliBinDir;$originalPath"
            Mock -ModuleName SubscriptionPortability.Foundation Get-Command { [pscustomobject]@{ Name = 'az'; Source = $env:FAKE_AZ_CMD_PATH } }

            $testArguments = @(
                'plain',
                'has spaces',
                'amp&value',
                'pipe|value',
                'redirect>value',
                'redirect<value',
                'percent%value%',
                'caret^value',
                'bang!value',
                'quote"value',
                'safe & echo INJECTED > "' + $injectedMarkerPath + '"'
            )

            $result = Invoke-AzureCliProcess -Arguments $testArguments
            $result.Success | Should Be $true
            $result.ExitCode | Should Be 0
            (Test-Path $injectedMarkerPath) | Should Be $false
            $result.StdOut | Should Not Match 'INJECTED'
            $result.StdErr | Should Not Match 'INJECTED'

            (Test-Path $outputPath) | Should Be $true
            $capturedArguments = @(Get-Content -Path $outputPath -Raw | ConvertFrom-Json)
            $expectedArguments = @('-IBm', 'azure.cli') + $testArguments
            $capturedArguments.Count | Should Be $expectedArguments.Count
            for ($i = 0; $i -lt $expectedArguments.Count; $i++) {
                $capturedArguments[$i] | Should Be $expectedArguments[$i]
            }
        }
        finally {
            Remove-Item Env:FAKE_AZ_CMD_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:FAKE_AZ_OUTPUT_PATH -ErrorAction SilentlyContinue
            $env:PATH = $originalPath
            Remove-Item -Path $fakeCliDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
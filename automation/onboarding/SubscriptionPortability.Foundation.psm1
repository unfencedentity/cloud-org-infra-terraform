Set-StrictMode -Version Latest

$script:ErrorActionPreference = "Stop"

$script:KnownRegionCodeMap = [ordered]@{
    deu = 'denmarkeast'
    swe = 'swedencentral'
    weu = 'westeurope'
    neu = 'northeurope'
    eus = 'eastus'
    wus = 'westus'
}

$script:RequiredProviderDefinitions = @(
    [pscustomobject]@{ Namespace = 'Microsoft.Network'; ResourceTypes = @('virtualNetworks', 'networkSecurityGroups', 'privateEndpoints', 'networkInterfaces'); Target = 'Workload' }
    [pscustomobject]@{ Namespace = 'Microsoft.Compute'; ResourceTypes = @('virtualMachines'); Target = 'Workload' }
    [pscustomobject]@{ Namespace = 'Microsoft.Storage'; ResourceTypes = @('storageAccounts'); Target = 'Workload' }
    [pscustomobject]@{ Namespace = 'Microsoft.KeyVault'; ResourceTypes = @('vaults'); Target = 'Workload' }
    [pscustomobject]@{ Namespace = 'Microsoft.ManagedIdentity'; ResourceTypes = @('userAssignedIdentities'); Target = 'Workload' }
    [pscustomobject]@{ Namespace = 'Microsoft.Web'; ResourceTypes = @('serverfarms', 'sites'); Target = 'Workload' }
    [pscustomobject]@{ Namespace = 'Microsoft.Insights'; ResourceTypes = @('components'); Target = 'Monitoring' }
    [pscustomobject]@{ Namespace = 'Microsoft.OperationalInsights'; ResourceTypes = @('workspaces'); Target = 'Monitoring' }
    [pscustomobject]@{ Namespace = 'Microsoft.RecoveryServices'; ResourceTypes = @('vaults'); Target = 'Workload' }
    [pscustomobject]@{ Namespace = 'Microsoft.Authorization'; ResourceTypes = @(); Target = 'Global' }
)

$script:UnavailableDisplayValue = '<unavailable>'

function Get-SafeDisplayIdentifier {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Identifier
    )

    if ([string]::IsNullOrWhiteSpace($Identifier)) {
        return $script:UnavailableDisplayValue
    }

    return (Get-MaskedIdentifier -Identifier $Identifier)
}

function Get-SafeCliText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $safe = $Text
    $safe = [regex]::Replace($safe, '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', '<masked-guid>')
    $safe = [regex]::Replace($safe, '(?i)(access_token|refresh_token|id_token|client_secret)\s*[:=]\s*[^\s\"\'']+', '$1=<redacted>')
    $safe = [regex]::Replace($safe, '(?i)bearer\s+[A-Za-z0-9\-\._~\+\/]+=*', 'bearer <redacted>')
    return $safe.Trim()
}

function Get-MaskedIdentifier {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Identifier
    )

    if ([string]::IsNullOrWhiteSpace($Identifier)) {
        return 'not-set'
    }

    $trimmed = $Identifier.Trim()
    if ($trimmed.Length -le 4) {
        return ('...' + $trimmed.ToLowerInvariant())
    }

    return ('...' + $trimmed.Substring($trimmed.Length - 4).ToLowerInvariant())
}

function Get-Sha256Hex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputText
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputText)
    $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
}

function Get-DeterministicSuffix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$WorkloadRegionCode,

        [ValidateRange(6, 16)]
        [int]$Length = 10
    )

    $normalized = @(
        $TenantId.Trim().ToLowerInvariant()
        $SubscriptionId.Trim().ToLowerInvariant()
        $Environment.Trim().ToLowerInvariant()
        $WorkloadRegionCode.Trim().ToLowerInvariant()
    ) -join '|'

    return (Get-Sha256Hex -InputText $normalized).Substring(0, $Length)
}

function Resolve-AssessmentOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [string]$OutputPath
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        return (Join-Path -Path '.generated\onboarding' -ChildPath ("{0}-profile.json" -f $Environment.Trim().ToLowerInvariant()))
    }

    return $OutputPath
}

function Get-KnownRegionCodeMap {
    [CmdletBinding()]
    param()

    return $script:KnownRegionCodeMap
}

function New-AssessmentResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Passed', 'Warning', 'Blocked', 'NotVerifiable')]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidatePattern('^[A-Za-z][A-Za-z0-9]{2,64}$')]
        [string]$Code,

        [AllowNull()]
        [object]$Data = $null
    )

    [pscustomobject]@{
        name    = $Name
        status  = $Status
        message = $Message
        code    = $Code
        data    = $Data
    }
}

function Get-AssessmentOutcome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Results
    )

    $blockers = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    $normalizedResults = foreach ($entry in $Results) {
        if ($null -eq $entry) {
            continue
        }

        $hasStatus = $entry.PSObject -and $entry.PSObject.Properties.Name -contains 'status'
        $isEnumerable = ($entry -is [System.Collections.IEnumerable]) -and -not ($entry -is [string])

        if ($isEnumerable -and -not $hasStatus) {
            foreach ($inner in $entry) {
                if ($null -ne $inner) {
                    $inner
                }
            }
        }
        else {
            $entry
        }
    }

    foreach ($result in $normalizedResults) {
        if ($null -eq $result) {
            continue
        }

        switch ($result.status) {
            'Blocked' {
                $prefix = if (-not [string]::IsNullOrWhiteSpace($result.code)) { "[{0}] " -f $result.code } else { '' }
                $blockers.Add(("{0}{1}: {2}" -f $prefix, $result.name, $result.message))
            }
            'NotVerifiable' {
                $prefix = if (-not [string]::IsNullOrWhiteSpace($result.code)) { "[{0}] " -f $result.code } else { '' }
                $blockers.Add(("{0}{1}: {2}" -f $prefix, $result.name, $result.message))
            }
            'Warning' {
                $warnings.Add(("{0}: {1}" -f $result.name, $result.message))
            }
        }
    }

    [pscustomobject]@{
        overallStatus = $(if ($blockers.Count -eq 0) { 'GO' } else { 'NO-GO' })
        blockers      = @($blockers)
        warnings      = @($warnings)
    }
}

function New-AzureStorageAccountName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [string]$Suffix
    )

    $prefixNormalized = ($Prefix.ToLowerInvariant() -replace '[^a-z0-9]', '')
    $suffixNormalized = ($Suffix.ToLowerInvariant() -replace '[^a-z0-9]', '')
    $name = ($prefixNormalized + $suffixNormalized)

    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = 'st' + $suffixNormalized
    }

    if ($name[0] -notmatch '[a-z]') {
        $name = 'st' + $name
    }

    if ($name.Length -gt 24) {
        $name = $name.Substring(0, 24)
    }

    return $name
}

function New-AzureKeyVaultName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [string]$Suffix
    )

    $prefixNormalized = ($Prefix.ToLowerInvariant() -replace '[^a-z0-9-]', '-') -replace '-{2,}', '-'
    $prefixNormalized = $prefixNormalized.Trim('-')
    $suffixNormalized = ($Suffix.ToLowerInvariant() -replace '[^a-z0-9]', '')
    $name = ("{0}-{1}" -f $prefixNormalized, $suffixNormalized).Trim('-')

    if ($name[0] -notmatch '[a-z]') {
        $name = 'k' + $name
    }

    $name = $name.Trim('-')
    if ($name.Length -gt 24) {
        $name = $name.Substring(0, 24).Trim('-')
    }

    if ($name[-1] -notmatch '[a-z0-9]') {
        $name = $name.TrimEnd('-')
    }

    return $name
}

function New-AzureWebAppName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [string]$Suffix
    )

    $prefixNormalized = ($Prefix.ToLowerInvariant() -replace '[^a-z0-9-]', '-') -replace '-{2,}', '-'
    $prefixNormalized = $prefixNormalized.Trim('-')
    $suffixNormalized = ($Suffix.ToLowerInvariant() -replace '[^a-z0-9]', '')
    $name = ("{0}-{1}" -f $prefixNormalized, $suffixNormalized).Trim('-')

    if ($name[0] -notmatch '[a-z0-9]') {
        $name = 'app-' + $name
    }

    if ($name.Length -gt 60) {
        $name = $name.Substring(0, 60).Trim('-')
    }

    return $name
}

function New-PortableNameSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$WorkloadRegionCode
    )

    $envCode = $Environment.Trim().ToLowerInvariant()
    $regionCode = $WorkloadRegionCode.Trim().ToLowerInvariant()
    $suffix = Get-DeterministicSuffix -TenantId $TenantId -SubscriptionId $SubscriptionId -Environment $Environment -WorkloadRegionCode $WorkloadRegionCode

    [pscustomobject]@{
        deterministicSuffix   = $suffix
        backendResourceGroup  = "rg-$envCode-tfstate-$regionCode-$suffix"
        backendStorageAccount = (New-AzureStorageAccountName -Prefix ("sttf$envCode$regionCode") -Suffix $suffix)
        workloadResourceGroup = "rg-$envCode-core-$regionCode-$suffix"
        applicationStorage    = (New-AzureStorageAccountName -Prefix ("stapp$envCode$regionCode") -Suffix $suffix)
        keyVault              = (New-AzureKeyVaultName -Prefix ("kv-app-$envCode-$regionCode") -Suffix $suffix)
        linuxWebApp           = (New-AzureWebAppName -Prefix ("app-$envCode-$regionCode") -Suffix $suffix)
    }
}

function New-PortableNameSetForFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$WorkloadRegionCode
    )

    $envCode = $Environment.Trim().ToLowerInvariant()
    $regionCode = $WorkloadRegionCode.Trim().ToLowerInvariant()
    $suffix = 'unavail0000'

    [pscustomobject]@{
        deterministicSuffix   = $suffix
        backendResourceGroup  = "rg-$envCode-tfstate-$regionCode-$suffix"
        backendStorageAccount = (New-AzureStorageAccountName -Prefix ("sttf$envCode$regionCode") -Suffix $suffix)
        workloadResourceGroup = "rg-$envCode-core-$regionCode-$suffix"
        applicationStorage    = (New-AzureStorageAccountName -Prefix ("stapp$envCode$regionCode") -Suffix $suffix)
        keyVault              = (New-AzureKeyVaultName -Prefix ("kv-app-$envCode-$regionCode") -Suffix $suffix)
        linuxWebApp           = (New-AzureWebAppName -Prefix ("app-$envCode-$regionCode") -Suffix $suffix)
    }
}

function New-OfflineAzureContext {
    [CmdletBinding()]
    param(
        [string]$ExpectedTenantId,
        [string]$ExpectedSubscriptionId
    )

    [pscustomobject]@{
        user = [pscustomobject]@{
            name = 'offline-context'
            type = 'offline'
        }
        tenantId = $(if ([string]::IsNullOrWhiteSpace($ExpectedTenantId)) { '00000000-0000-0000-0000-000000000000' } else { $ExpectedTenantId })
        id       = $(if ([string]::IsNullOrWhiteSpace($ExpectedSubscriptionId)) { '11111111-1111-1111-1111-111111111111' } else { $ExpectedSubscriptionId })
        name     = 'offline-subscription'
        state    = 'Unknown'
        isDefault = $false
    }
}

function New-UnavailableAzureContext {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        user = [pscustomobject]@{
            name = $script:UnavailableDisplayValue
            type = 'unavailable'
        }
        tenantId  = $null
        id        = $null
        name      = $script:UnavailableDisplayValue
        state     = 'Unknown'
        isDefault = $false
    }
}

function Invoke-AzureCliProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            ExitCode = 127
            StdOut   = ''
            StdErr   = 'Azure CLI executable was not found in PATH.'
            Success  = $false
        }
    }

    $process = $null
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'az'
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        foreach ($argument in $Arguments) {
            $null = $startInfo.ArgumentList.Add($argument)
        }

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo

        $null = $process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
            Success  = ($process.ExitCode -eq 0)
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = -1
            StdOut   = ''
            StdErr   = $_.Exception.Message
            Success  = $false
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Invoke-AzureCliJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [scriptblock]$ProcessInvoker,

        [switch]$AllowFailure
    )

    if ($null -eq $ProcessInvoker) {
        $ProcessInvoker = {
            param($InnerArguments)
            Invoke-AzureCliProcess -Arguments $InnerArguments
        }
    }

    $execution = & $ProcessInvoker $Arguments
    $exitCode = [int]$execution.ExitCode
    $stdout = if ($null -eq $execution.StdOut) { '' } else { [string]$execution.StdOut }
    $stderr = if ($null -eq $execution.StdErr) { '' } else { [string]$execution.StdErr }
    $safeStdErr = Get-SafeCliText -Text $stderr
    $failureKind = $null
    $safeMessage = 'Azure CLI command completed successfully.'

    if ($exitCode -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace($safeStdErr)) {
            $safeMessage = "Azure CLI returned a non-zero exit code: $safeStdErr"
        }
        else {
            $safeMessage = 'Azure CLI returned a non-zero exit code.'
        }

        if ($exitCode -eq 127) {
            $failureKind = 'AzureCliUnavailable'
            $safeMessage = 'Azure CLI executable was not found in PATH.'
        }
        else {
            $failureKind = 'NonZeroExit'
        }

        $result = [pscustomobject]@{
            ExitCode    = $exitCode
            StdOut      = $stdout
            StdErr      = $safeStdErr
            ParsedJson  = $null
            Success     = $false
            FailureKind = $failureKind
            SafeMessage = $safeMessage
            Succeeded   = $false
            Data        = $null
            RawOutput   = $safeStdErr
        }

        if ($AllowFailure) {
            return $result
        }

        throw "Azure CLI command failed: az $($Arguments -join ' ')$([Environment]::NewLine)$safeMessage"
    }

    if ([string]::IsNullOrWhiteSpace($stdout)) {
        $failureKind = 'EmptyStdOut'
        $safeMessage = 'Azure CLI returned empty stdout where JSON output was required.'
        $result = [pscustomobject]@{
            ExitCode    = $exitCode
            StdOut      = $stdout
            StdErr      = $safeStdErr
            ParsedJson  = $null
            Success     = $false
            FailureKind = $failureKind
            SafeMessage = $safeMessage
            Succeeded   = $false
            Data        = $null
            RawOutput   = $safeStdErr
        }

        if ($AllowFailure) {
            return $result
        }

        throw "Azure CLI command failed: az $($Arguments -join ' ')$([Environment]::NewLine)$safeMessage"
    }

    try {
        $data = $stdout | ConvertFrom-Json -Depth 32
    }
    catch {
        $failureKind = 'InvalidJson'
        $safeMessage = 'Azure CLI stdout was not valid JSON.'
        $result = [pscustomobject]@{
            ExitCode    = $exitCode
            StdOut      = ''
            StdErr      = $safeStdErr
            ParsedJson  = $null
            Success     = $false
            FailureKind = $failureKind
            SafeMessage = $safeMessage
            Succeeded   = $false
            Data        = $null
            RawOutput   = $safeStdErr
        }

        if ($AllowFailure) {
            return $result
        }

        throw "Azure CLI command failed: az $($Arguments -join ' ')$([Environment]::NewLine)$safeMessage"
    }

    return [pscustomobject]@{
        ExitCode    = 0
        StdOut      = $stdout
        StdErr      = $safeStdErr
        ParsedJson  = $data
        Success     = $true
        FailureKind = $null
        SafeMessage = 'Azure CLI command completed successfully.'
        Succeeded   = $true
        Data        = $data
        RawOutput   = $safeStdErr
    }
}

function Get-ActiveAzureContext {
    [CmdletBinding()]
    param()

    $result = Invoke-AzureCliJson -Arguments @('account', 'show', '-o', 'json')
    return $result.Data
}

function Get-ActiveAzureContextAssessment {
    [CmdletBinding()]
    param()

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            Context = (New-UnavailableAzureContext)
            Result  = (New-AssessmentResult -Name 'AzureContext' -Status 'Blocked' -Code 'AzureCliUnavailable' -Message 'Azure CLI executable is not available in PATH. Install Azure CLI before running a live assessment.')
        }
    }

    $result = Invoke-AzureCliJson -Arguments @('account', 'show', '-o', 'json') -AllowFailure
    if (-not $result.Success) {
        $statusCode = if ($result.FailureKind -eq 'InvalidJson' -or $result.FailureKind -eq 'EmptyStdOut') { 'AzureContextInvalid' } else { 'AzureContextUnavailable' }
        return [pscustomobject]@{
            Context = (New-UnavailableAzureContext)
            Result  = (New-AssessmentResult -Name 'AzureContext' -Status 'Blocked' -Code $statusCode -Message ('Active Azure account context is not usable for assessment: {0}' -f $result.SafeMessage))
        }
    }

    $context = $result.ParsedJson
    if ($null -eq $context -or [string]::IsNullOrWhiteSpace($context.tenantId) -or [string]::IsNullOrWhiteSpace($context.id)) {
        return [pscustomobject]@{
            Context = (New-UnavailableAzureContext)
            Result  = (New-AssessmentResult -Name 'AzureContext' -Status 'Blocked' -Code 'AzureContextInvalid' -Message 'Azure CLI returned account data missing tenantId or subscriptionId.')
        }
    }

    return [pscustomobject]@{
        Context = $context
        Result  = (New-AssessmentResult -Name 'AzureContext' -Status 'Passed' -Code 'AzureContextAvailable' -Message 'Active Azure account context is available for assessment.')
    }
}

function Get-SubscriptionStateAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Context.state)) {
        return (New-AssessmentResult -Name 'SubscriptionState' -Status 'NotVerifiable' -Code 'SubscriptionStateUnknown' -Message 'Active subscription state is not available in the Azure context payload.')
    }

    if ($Context.state -eq 'Enabled') {
        return (New-AssessmentResult -Name 'SubscriptionState' -Status 'Passed' -Code 'SubscriptionEnabled' -Message 'Active subscription is enabled.')
    }

    return (New-AssessmentResult -Name 'SubscriptionState' -Status 'Blocked' -Code 'SubscriptionDisabled' -Message ("Active subscription state is '$($Context.state)'."))
}

function Get-AccountLocationNames {
    [CmdletBinding()]
    param()

    $assessment = Get-AccountLocationAssessment
    if ($assessment.Result.status -ne 'Passed') {
        return @()
    }

    return @($assessment.Locations)
}

function Get-AccountLocationAssessment {
    [CmdletBinding()]
    param(
        [scriptblock]$ProcessInvoker
    )

    $result = Invoke-AzureCliJson -Arguments @('account', 'list-locations', '-o', 'json') -AllowFailure -ProcessInvoker $ProcessInvoker
    if (-not $result.Success) {
        return [pscustomobject]@{
            Locations   = @()
            FailureKind = $result.FailureKind
            Result      = (New-AssessmentResult -Name 'LocationCatalog' -Status 'Blocked' -Code 'LocationCatalogUnavailable' -Message ('Azure location catalog is unavailable for validation: {0}' -f $result.SafeMessage))
        }
    }

    $locations = @($result.Data | ForEach-Object {
        if ($_.name) {
            $_.name.ToLowerInvariant()
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($locations.Count -eq 0) {
        return [pscustomobject]@{
            Locations   = @()
            FailureKind = 'LocationCatalogEmpty'
            Result      = (New-AssessmentResult -Name 'LocationCatalog' -Status 'Blocked' -Code 'LocationCatalogUnavailable' -Message 'Azure location catalog is unavailable for validation: no locations were returned.')
        }
    }

    return [pscustomobject]@{
        Locations   = @($locations)
        FailureKind = $null
        Result      = (New-AssessmentResult -Name 'LocationCatalog' -Status 'Passed' -Code 'LocationCatalogAvailable' -Message 'Azure location catalog is available for validation.')
    }
}

function Test-ExpectedContextMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [string]$ExpectedTenantId,

        [string]$ExpectedSubscriptionId
    )

    $results = @()

    if (-not [string]::IsNullOrWhiteSpace($ExpectedTenantId)) {
        if ($Context.tenantId -eq $ExpectedTenantId) {
            $results += New-AssessmentResult -Name 'ExpectedTenantId' -Status 'Passed' -Code 'TenantMatched' -Message ('Expected tenant matched {0}.' -f (Get-MaskedIdentifier -Identifier $ExpectedTenantId))
        }
        else {
            $results += New-AssessmentResult -Name 'ExpectedTenantId' -Status 'Blocked' -Code 'TenantMismatch' -Message ('Expected tenant {0} does not match active tenant {1}.' -f (Get-MaskedIdentifier -Identifier $ExpectedTenantId), (Get-SafeDisplayIdentifier -Identifier $Context.tenantId))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedSubscriptionId)) {
        if ($Context.id -eq $ExpectedSubscriptionId) {
            $results += New-AssessmentResult -Name 'ExpectedSubscriptionId' -Status 'Passed' -Code 'SubscriptionMatched' -Message ('Expected subscription matched {0}.' -f (Get-MaskedIdentifier -Identifier $ExpectedSubscriptionId))
        }
        else {
            $results += New-AssessmentResult -Name 'ExpectedSubscriptionId' -Status 'Blocked' -Code 'SubscriptionMismatch' -Message ('Expected subscription {0} does not match active subscription {1}.' -f (Get-MaskedIdentifier -Identifier $ExpectedSubscriptionId), (Get-SafeDisplayIdentifier -Identifier $Context.id))
        }
    }

    return ,$results
}

function Test-LocationPair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegionCode,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string[]]$AvailableLocations,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $normalizedCode = $RegionCode.Trim().ToLowerInvariant()
    $normalizedLocation = $Location.Trim().ToLowerInvariant()

    if (-not $script:KnownRegionCodeMap.ContainsKey($normalizedCode)) {
        return (New-AssessmentResult -Name ("{0}RegionCode" -f $Label) -Status 'Blocked' -Message ("Region code '$normalizedCode' is not in the approved portability map."))
    }

    $expectedLocation = $script:KnownRegionCodeMap[$normalizedCode]
    if ($normalizedLocation -ne $expectedLocation) {
        return (New-AssessmentResult -Name ("{0}RegionCode" -f $Label) -Status 'Blocked' -Message ("Region code '$normalizedCode' expects location '$expectedLocation', but '$normalizedLocation' was supplied."))
    }

    if ($AvailableLocations -notcontains $normalizedLocation) {
        return (New-AssessmentResult -Name ("{0}Location" -f $Label) -Status 'Blocked' -Message ("Location '$normalizedLocation' is not available in the active subscription location catalog."))
    }

    return (New-AssessmentResult -Name ("{0}Location" -f $Label) -Status 'Passed' -Message ("Location '$normalizedLocation' is valid for region code '$normalizedCode'."))
}

function Get-RequiredProviderDefinitions {
    [CmdletBinding()]
    param()

    return $script:RequiredProviderDefinitions
}

function Get-ProviderRegistrationResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ProviderDefinitions
    )

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($definition in $ProviderDefinitions) {
        $provider = Invoke-AzureCliJson -Arguments @('provider', 'show', '--namespace', $definition.Namespace, '-o', 'json') -AllowFailure
        if (-not $provider.Success) {
            $result = New-AssessmentResult -Name $definition.Namespace -Status 'NotVerifiable' -Code 'ProviderStateUnavailable' -Message ('Could not read provider registration state: {0}' -f $provider.SafeMessage)
            $results.Add($result)
            continue
        }

        $state = $provider.Data.registrationState
        if ($state -eq 'Registered') {
            $result = New-AssessmentResult -Name $definition.Namespace -Status 'Passed' -Message 'Provider is registered.' -Data ([pscustomobject]@{ registrationState = $state })
            $results.Add($result)
        }
        else {
            $result = New-AssessmentResult -Name $definition.Namespace -Status 'Blocked' -Message ("Provider registration state is '$state'.") -Data ([pscustomobject]@{ registrationState = $state })
            $results.Add($result)
        }
    }

    return @($results)
}

function Get-ProviderResourceTypeLocationResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ProviderDefinitions,

        [Parameter(Mandatory = $true)]
        [string]$WorkloadLocation,

        [Parameter(Mandatory = $true)]
        [string]$MonitoringLocation
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($definition in $ProviderDefinitions) {
        if ($definition.ResourceTypes.Count -eq 0) {
            continue
        }

        $provider = Invoke-AzureCliJson -Arguments @('provider', 'show', '--namespace', $definition.Namespace, '-o', 'json') -AllowFailure
        if (-not $provider.Success) {
            foreach ($resourceType in $definition.ResourceTypes) {
                $result = New-AssessmentResult -Name ("{0}/{1}" -f $definition.Namespace, $resourceType) -Status 'NotVerifiable' -Code 'ProviderResourceTypeUnavailable' -Message ('Could not read provider resource types: {0}' -f $provider.SafeMessage)
                $results.Add($result)
            }
            continue
        }

        $targetLocation = if ($definition.Target -eq 'Monitoring') { $MonitoringLocation } else { $WorkloadLocation }
        foreach ($resourceType in $definition.ResourceTypes) {
            $resourceMetadata = @($provider.Data.resourceTypes | Where-Object { $_.resourceType -eq $resourceType }) | Select-Object -First 1
            if ($null -eq $resourceMetadata) {
                $result = New-AssessmentResult -Name ("{0}/{1}" -f $definition.Namespace, $resourceType) -Status 'NotVerifiable' -Message 'Resource type metadata was not published in the provider response.'
                $results.Add($result)
                continue
            }

            $locations = @($resourceMetadata.locations | ForEach-Object { $_.ToLowerInvariant() })
            if ($locations.Count -eq 0) {
                $result = New-AssessmentResult -Name ("{0}/{1}" -f $definition.Namespace, $resourceType) -Status 'NotVerifiable' -Message 'Provider metadata did not include supported locations.'
                $results.Add($result)
                continue
            }

            if ($locations -contains $targetLocation.ToLowerInvariant()) {
                $result = New-AssessmentResult -Name ("{0}/{1}" -f $definition.Namespace, $resourceType) -Status 'Passed' -Message ("Resource type supports location '$targetLocation'.")
                $results.Add($result)
            }
            else {
                $result = New-AssessmentResult -Name ("{0}/{1}" -f $definition.Namespace, $resourceType) -Status 'Blocked' -Message ("Resource type does not list location '$targetLocation' for the active subscription metadata.")
                $results.Add($result)
            }
        }
    }

    return @($results)
}

function Get-VmSkuAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$VmSize
    )

    $skuResult = Invoke-AzureCliJson -Arguments @('vm', 'list-skus', '-l', $Location, '--resource-type', 'virtualMachines', '--size', $VmSize, '-o', 'json') -AllowFailure
    if (-not $skuResult.Success) {
        return (New-AssessmentResult -Name 'VmSku' -Status 'NotVerifiable' -Code 'VmSkuUnavailable' -Message ('Azure CLI could not verify VM SKU availability: {0}' -f $skuResult.SafeMessage))
    }

    $sku = @($skuResult.Data | Where-Object { $_.name -eq $VmSize }) | Select-Object -First 1
    if ($null -eq $sku) {
        return (New-AssessmentResult -Name 'VmSku' -Status 'Blocked' -Message ("VM SKU '$VmSize' is not returned for location '$Location'."))
    }

    $restrictions = @($sku.restrictions)
    if ($restrictions.Count -gt 0) {
        $restrictionMessages = @($restrictions | ForEach-Object {
            if ($_.reasonCode) {
                $_.reasonCode
            }
            else {
                'restriction-present'
            }
        }) -join ', '

        return (New-AssessmentResult -Name 'VmSku' -Status 'Blocked' -Message ("VM SKU '$VmSize' has subscription or regional restrictions: $restrictionMessages.") -Data ([pscustomobject]@{ family = $sku.family; size = $sku.size }))
    }

    return (New-AssessmentResult -Name 'VmSku' -Status 'Passed' -Message ("VM SKU '$VmSize' is available in '$Location' with no published restrictions.") -Data ([pscustomobject]@{ family = $sku.family; size = $sku.size }))
}

function Get-ComputeQuotaAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Location,

        [AllowNull()]
        [object]$VmSkuMetadata
    )

    $usageResult = Invoke-AzureCliJson -Arguments @('vm', 'list-usage', '-l', $Location, '-o', 'json') -AllowFailure
    if (-not $usageResult.Success) {
        return (New-AssessmentResult -Name 'ComputeQuota' -Status 'NotVerifiable' -Code 'ComputeQuotaUnavailable' -Message ('Azure CLI could not inspect VM quota usage: {0}' -f $usageResult.SafeMessage))
    }

    $totalRegional = @($usageResult.Data | Where-Object { $_.name.value -eq 'cores' -or $_.name.localizedValue -eq 'Total Regional vCPUs' }) | Select-Object -First 1
    $familyUsage = $null

    if ($null -ne $VmSkuMetadata -and $VmSkuMetadata.PSObject.Properties.Name -contains 'family' -and -not [string]::IsNullOrWhiteSpace($VmSkuMetadata.family)) {
        $familyName = $VmSkuMetadata.family
        $familyUsage = @($usageResult.Data | Where-Object { $_.name.value -eq $familyName -or $_.name.localizedValue -like "*$familyName*" }) | Select-Object -First 1
    }

    if ($null -eq $totalRegional) {
        return (New-AssessmentResult -Name 'ComputeQuota' -Status 'NotVerifiable' -Message 'Regional vCPU quota entry was not present in the Azure CLI usage output.')
    }

    $remainingRegional = [int]$totalRegional.limit - [int]$totalRegional.currentValue
    $familyRemaining = $null
    if ($null -ne $familyUsage) {
        $familyRemaining = [int]$familyUsage.limit - [int]$familyUsage.currentValue
    }

    if ($remainingRegional -le 0) {
        return (New-AssessmentResult -Name 'ComputeQuota' -Status 'Blocked' -Message ("Regional vCPU quota is exhausted in '$Location'.") -Data ([pscustomobject]@{ totalRegional = $totalRegional; family = $familyUsage }))
    }

    if ($null -ne $familyRemaining -and $familyRemaining -le 0) {
        return (New-AssessmentResult -Name 'ComputeQuota' -Status 'Blocked' -Message 'The VM family quota published for the selected size is exhausted.' -Data ([pscustomobject]@{ totalRegional = $totalRegional; family = $familyUsage }))
    }

    if ($null -eq $familyUsage) {
        return (New-AssessmentResult -Name 'ComputeQuota' -Status 'Warning' -Message 'Regional vCPU quota is available, but the matching VM family quota could not be resolved from CLI usage data.' -Data ([pscustomobject]@{ totalRegional = $totalRegional }))
    }

    return (New-AssessmentResult -Name 'ComputeQuota' -Status 'Passed' -Message 'Regional and VM family quota entries indicate available capacity.' -Data ([pscustomobject]@{ totalRegional = $totalRegional; family = $familyUsage }))
}

function Get-AppServiceSkuAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$AppServiceSku
    )

    $locationResult = Invoke-AzureCliJson -Arguments @('appservice', 'list-locations', '--sku', $AppServiceSku, '--linux-workers-enabled', '-o', 'json') -AllowFailure
    if (-not $locationResult.Success) {
        return (New-AssessmentResult -Name 'AppServiceSku' -Status 'NotVerifiable' -Code 'AppServiceSkuUnavailable' -Message ('Azure CLI could not verify Linux App Service availability: {0}' -f $locationResult.SafeMessage))
    }

    $availableLocations = @($locationResult.Data | ForEach-Object {
        if ($_.name) {
            $_.name.ToLowerInvariant()
        }
        elseif ($_.value) {
            $_.value.ToLowerInvariant()
        }
        elseif ($_ -is [string]) {
            $_.ToLowerInvariant()
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($availableLocations.Count -eq 0) {
        return (New-AssessmentResult -Name 'AppServiceSku' -Status 'NotVerifiable' -Message 'Azure CLI returned no App Service location data for the selected SKU.')
    }

    if ($availableLocations -contains $Location.ToLowerInvariant()) {
        return (New-AssessmentResult -Name 'AppServiceSku' -Status 'Passed' -Message ("Linux App Service SKU '$AppServiceSku' is listed for '$Location'."))
    }

    return (New-AssessmentResult -Name 'AppServiceSku' -Status 'Blocked' -Message ("Linux App Service SKU '$AppServiceSku' is not listed for '$Location'."))
}

function New-SubscriptionPortabilityProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [object]$Context,

        [Parameter(Mandatory = $true)]
        [string]$WorkloadLocation,

        [Parameter(Mandatory = $true)]
        [string]$WorkloadRegionCode,

        [Parameter(Mandatory = $true)]
        [string]$MonitoringLocation,

        [Parameter(Mandatory = $true)]
        [string]$MonitoringRegionCode,

        [Parameter(Mandatory = $true)]
        [string]$AddressSpace,

        [Parameter(Mandatory = $true)]
        [string]$VmSize,

        [Parameter(Mandatory = $true)]
        [string]$AppServiceSku,

        [Parameter(Mandatory = $true)]
        [object]$ProposedNames,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ProviderResults,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$RegionResults,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$SkuResults,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$QuotaResults,

        [Parameter(Mandatory = $true)]
        [string]$OverallStatus,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Blockers,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Warnings
    )

    [pscustomobject]@{
        schemaVersion        = '1.0.0'
        generatedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
        assessmentOutcomeType = $(if ($OverallStatus -eq 'GO') { 'Approved' } else { 'Failure' })
        environment          = $Environment.Trim().ToLowerInvariant()
        tenantId             = $Context.tenantId
        subscriptionId       = $Context.id
        maskedTenantId       = (Get-SafeDisplayIdentifier -Identifier $Context.tenantId)
        maskedSubscriptionId = (Get-SafeDisplayIdentifier -Identifier $Context.id)
        workloadLocation     = $WorkloadLocation.Trim().ToLowerInvariant()
        workloadRegionCode   = $WorkloadRegionCode.Trim().ToLowerInvariant()
        monitoringLocation   = $MonitoringLocation.Trim().ToLowerInvariant()
        monitoringRegionCode = $MonitoringRegionCode.Trim().ToLowerInvariant()
        addressSpace         = $AddressSpace.Trim()
        vmSize               = $VmSize.Trim()
        appServiceSku        = $AppServiceSku.Trim().ToUpperInvariant()
        deterministicSuffix  = $ProposedNames.deterministicSuffix
        proposedNames        = [ordered]@{
            backendResourceGroup  = $ProposedNames.backendResourceGroup
            backendStorageAccount = $ProposedNames.backendStorageAccount
            workloadResourceGroup = $ProposedNames.workloadResourceGroup
            applicationStorage    = $ProposedNames.applicationStorage
            keyVault              = $ProposedNames.keyVault
            linuxWebApp           = $ProposedNames.linuxWebApp
        }
        providerResults      = @($ProviderResults)
        regionResults        = @($RegionResults)
        skuResults           = @($SkuResults)
        quotaResults         = @($QuotaResults)
        overallStatus        = $OverallStatus
        blockers             = @($Blockers)
        warnings             = @($Warnings)
    }
}

function Write-AssessmentSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$AssessmentProfile,

        [Parameter(Mandatory = $true)]
        [object]$Context,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $providerSummary = @($AssessmentProfile.providerResults | Group-Object -Property status | Sort-Object Name | ForEach-Object { "{0}={1}" -f $_.Name, $_.Count }) -join ', '

    Write-Information ("Active account: {0} ({1})" -f $Context.user.name, $Context.user.type) -InformationAction Continue
    Write-Information ("Tenant: {0}" -f $AssessmentProfile.maskedTenantId) -InformationAction Continue
    Write-Information ("Subscription: {0}" -f $AssessmentProfile.maskedSubscriptionId) -InformationAction Continue
    Write-Information ("Workload: {0} [{1}]" -f $AssessmentProfile.workloadLocation, $AssessmentProfile.workloadRegionCode) -InformationAction Continue
    Write-Information ("Monitoring: {0} [{1}]" -f $AssessmentProfile.monitoringLocation, $AssessmentProfile.monitoringRegionCode) -InformationAction Continue
    Write-Information ("VM SKU: {0}; App Service SKU: {1}" -f $AssessmentProfile.vmSize, $AssessmentProfile.appServiceSku) -InformationAction Continue
    Write-Information ("Provider status: {0}" -f $providerSummary) -InformationAction Continue

    if ($AssessmentProfile.blockers.Count -gt 0) {
        Write-Information 'Blockers:' -InformationAction Continue
        foreach ($blocker in $AssessmentProfile.blockers) {
            Write-Information ("- {0}" -f $blocker) -InformationAction Continue
        }
    }

    if ($AssessmentProfile.warnings.Count -gt 0) {
        Write-Information 'Warnings:' -InformationAction Continue
        foreach ($warning in $AssessmentProfile.warnings) {
            Write-Information ("- {0}" -f $warning) -InformationAction Continue
        }
    }

    Write-Information ("Profile output: {0}" -f $OutputPath) -InformationAction Continue
    Write-Information ("Final decision: {0}" -f $AssessmentProfile.overallStatus) -InformationAction Continue
}

Export-ModuleMember -Function @(
    'Get-MaskedIdentifier',
    'Get-SafeDisplayIdentifier',
    'Get-SafeCliText',
    'Get-Sha256Hex',
    'Get-DeterministicSuffix',
    'Resolve-AssessmentOutputPath',
    'Get-KnownRegionCodeMap',
    'New-AssessmentResult',
    'Get-AssessmentOutcome',
    'New-AzureStorageAccountName',
    'New-AzureKeyVaultName',
    'New-AzureWebAppName',
    'New-PortableNameSet',
    'New-PortableNameSetForFailure',
    'New-OfflineAzureContext',
    'New-UnavailableAzureContext',
    'Invoke-AzureCliProcess',
    'Invoke-AzureCliJson',
    'Get-ActiveAzureContext',
    'Get-ActiveAzureContextAssessment',
    'Get-SubscriptionStateAssessment',
    'Get-AccountLocationNames',
    'Get-AccountLocationAssessment',
    'Test-ExpectedContextMatch',
    'Test-LocationPair',
    'Get-RequiredProviderDefinitions',
    'Get-ProviderRegistrationResults',
    'Get-ProviderResourceTypeLocationResults',
    'Get-VmSkuAssessment',
    'Get-ComputeQuotaAssessment',
    'Get-AppServiceSkuAssessment',
    'New-SubscriptionPortabilityProfile',
    'Write-AssessmentSummary'
)
Set-StrictMode -Version Latest

$script:ErrorActionPreference = "Stop"

# Kept in sync with environments/dev/variables.tf and bootstrap/remote-state/variables.tf.
# This module is the only place these patterns are duplicated outside Terraform itself.
$script:ApplicationPattern = '^[a-z0-9]{1,10}$'
$script:EnvironmentPattern = '^[a-z0-9]{1,6}$'
$script:RegionCodePattern = '^[a-z]{3}$'
$script:LocationPattern = '^[a-z0-9]+$'
$script:InstanceNumberPattern = '^[0-9]{3}$'
$script:SupportedProfileSchemaVersions = @('1.0.0')

function Get-AssessmentProfileFromFile {
    <#
    .SYNOPSIS
    Reads and parses an onboarding assessment profile JSON file.

    .DESCRIPTION
    Performs only file I/O and JSON parsing. Does not validate profile content;
    call Assert-ValidAssessmentProfile separately to validate the parsed object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Assessment profile file '$Path' was not found."
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Assessment profile file '$Path' is empty."
    }

    try {
        return (ConvertFrom-Json -InputObject $raw -ErrorAction Stop)
    }
    catch {
        throw "Assessment profile file '$Path' is not valid JSON: $($_.Exception.Message)"
    }
}

function Assert-ValidAssessmentProfile {
    <#
    .SYNOPSIS
    Validates that a parsed assessment profile is complete, supported, and GO.

    .DESCRIPTION
    Throws a terminating error for malformed, incomplete, unsupported, or NO-GO profiles.
    Never inspects or requires profile fields beyond the documented onboarding profile schema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Profile
    )

    if ($null -eq $Profile -or $Profile -isnot [System.Management.Automation.PSCustomObject]) {
        throw 'Assessment profile is malformed: expected a JSON object.'
    }

    $requiredFields = @(
        'schemaVersion',
        'overallStatus',
        'assessmentOutcomeType',
        'environment',
        'workloadLocation',
        'workloadRegionCode',
        'monitoringLocation',
        'monitoringRegionCode'
    )

    $propertyNames = @($Profile.PSObject.Properties.Name)
    foreach ($field in $requiredFields) {
        if ($propertyNames -notcontains $field) {
            throw "Assessment profile is incomplete: missing required field '$field'."
        }
    }

    if ($script:SupportedProfileSchemaVersions -notcontains $Profile.schemaVersion) {
        throw "Assessment profile schemaVersion '$($Profile.schemaVersion)' is not supported by this generator. Supported versions: $($script:SupportedProfileSchemaVersions -join ', ')."
    }

    foreach ($field in @('environment', 'workloadLocation', 'workloadRegionCode', 'monitoringLocation', 'monitoringRegionCode')) {
        if ([string]::IsNullOrWhiteSpace($Profile.$field)) {
            throw "Assessment profile is incomplete: field '$field' is empty."
        }
    }

    if ($Profile.overallStatus -ne 'GO') {
        throw "Assessment profile decision is '$($Profile.overallStatus)', not GO. Terraform inputs were not generated."
    }

    if ($Profile.assessmentOutcomeType -ne 'Approved') {
        throw "Assessment profile is inconsistent: overallStatus is 'GO' but assessmentOutcomeType is '$($Profile.assessmentOutcomeType)'."
    }
}

function Assert-ValidApplicationName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Application
    )

    if ($Application -cnotmatch $script:ApplicationPattern) {
        throw "Application '$Application' is invalid: it must match $script:ApplicationPattern (consistent with environments/dev/variables.tf)."
    }
}

function Assert-ValidEnvironmentName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Environment
    )

    if ($Environment -cnotmatch $script:EnvironmentPattern) {
        throw "Environment '$Environment' is invalid: it must match $script:EnvironmentPattern (consistent with environments/dev/variables.tf)."
    }
}

function Assert-ValidRegionCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RegionCode,

        [Parameter(Mandatory = $true)]
        [string]$ParameterName
    )

    if ($RegionCode -cnotmatch $script:RegionCodePattern) {
        throw "$ParameterName '$RegionCode' is invalid: it must match $script:RegionCodePattern (consistent with environments/dev/variables.tf)."
    }
}

function Assert-ValidLocationName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$ParameterName
    )

    if ($Location -cnotmatch $script:LocationPattern) {
        throw "$ParameterName '$Location' is invalid: it must match $script:LocationPattern (consistent with environments/dev/variables.tf)."
    }
}

function Assert-ValidInstanceNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$InstanceNumber
    )

    if ($InstanceNumber -cnotmatch $script:InstanceNumberPattern) {
        throw "InstanceNumber '$InstanceNumber' is invalid: it must match $script:InstanceNumberPattern (consistent with environments/dev/variables.tf)."
    }
}

function Assert-ValidAdminSourceCidr {
    <#
    .SYNOPSIS
    Validates admin_source_cidr identically to the environments/dev Terraform variable.

    .DESCRIPTION
    When EnableVmPublicIp is false, AdminSourceCidr is not evaluated. When true,
    AdminSourceCidr must be a specific, valid IPv4 CIDR (prefix /1-/32); null, empty,
    "*", "0.0.0.0/0", and "Internet" are always rejected, matching admin_source_cidr's
    validation block in environments/dev/variables.tf.
    #>
    [CmdletBinding()]
    param(
        [bool]$EnableVmPublicIp,

        [AllowNull()]
        $AdminSourceCidr
    )

    if (-not $EnableVmPublicIp) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($AdminSourceCidr)) {
        throw 'AdminSourceCidr is required and must be a specific CIDR when EnableVmPublicIp is set.'
    }

    $trimmed = $AdminSourceCidr.Trim()
    $lower = $trimmed.ToLowerInvariant()
    if ($lower -eq '*' -or $lower -eq 'internet' -or $lower -eq '0.0.0.0/0') {
        throw "AdminSourceCidr '$AdminSourceCidr' is not allowed. Broad values such as *, 0.0.0.0/0, and Internet are always rejected."
    }

    $parts = $trimmed.Split('/')
    if ($parts.Count -ne 2) {
        throw "AdminSourceCidr '$AdminSourceCidr' must be an IPv4 address and prefix separated by /, e.g. 203.0.113.10/32."
    }

    $ipAddress = $null
    if (-not [System.Net.IPAddress]::TryParse($parts[0], [ref]$ipAddress) -or $ipAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "AdminSourceCidr '$AdminSourceCidr' does not contain a valid IPv4 address."
    }

    $prefix = 0
    if (-not [int]::TryParse($parts[1], [ref]$prefix) -or $prefix -lt 1 -or $prefix -gt 32) {
        throw "AdminSourceCidr '$AdminSourceCidr' must have a prefix length between /1 and /32."
    }
}

function Assert-ConsistentEnvironment {
    <#
    .SYNOPSIS
    Ensures an explicitly requested environment matches the assessed profile's environment.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RequestedEnvironment,

        [Parameter(Mandatory = $true)]
        [string]$ProfileEnvironment
    )

    if ([string]::IsNullOrWhiteSpace($RequestedEnvironment)) {
        return
    }

    if ($RequestedEnvironment.Trim().ToLowerInvariant() -ne $ProfileEnvironment.Trim().ToLowerInvariant()) {
        throw "Requested environment '$RequestedEnvironment' does not match the assessed profile's environment '$ProfileEnvironment'."
    }
}

function New-BootstrapRemoteStateTfVars {
    <#
    .SYNOPSIS
    Builds the bootstrap/remote-state terraform.auto.tfvars.json content from an assessment profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Profile,

        [Parameter(Mandatory = $true)]
        [string]$InstanceNumber
    )

    Assert-ValidAssessmentProfile -Profile $Profile
    Assert-ValidEnvironmentName -Environment $Profile.environment
    Assert-ValidLocationName -Location $Profile.workloadLocation -ParameterName 'workload_location'
    Assert-ValidRegionCode -RegionCode $Profile.workloadRegionCode -ParameterName 'workload_region_code'
    Assert-ValidInstanceNumber -InstanceNumber $InstanceNumber

    return [ordered]@{
        environment           = $Profile.environment
        workload_location     = $Profile.workloadLocation
        workload_region_code  = $Profile.workloadRegionCode
        instance_number       = $InstanceNumber
    }
}

function New-EnvironmentDevTfVars {
    <#
    .SYNOPSIS
    Builds the environments/dev terraform.auto.tfvars.json content from an assessment profile
    and the deployment-specific values Terraform requires but the profile does not carry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Profile,

        [Parameter(Mandatory = $true)]
        [string]$Application,

        [Parameter(Mandatory = $true)]
        [string]$InstanceNumber,

        [Parameter(Mandatory = $true)]
        [string]$SshPublicKey,

        [Parameter(Mandatory = $true)]
        [string]$AlertEmailAddress,

        [bool]$EnableVmPublicIp = $false,

        [AllowNull()]
        $AdminSourceCidr = $null
    )

    Assert-ValidAssessmentProfile -Profile $Profile
    Assert-ValidApplicationName -Application $Application
    Assert-ValidEnvironmentName -Environment $Profile.environment
    Assert-ValidLocationName -Location $Profile.workloadLocation -ParameterName 'workload_location'
    Assert-ValidRegionCode -RegionCode $Profile.workloadRegionCode -ParameterName 'workload_region_code'
    Assert-ValidLocationName -Location $Profile.monitoringLocation -ParameterName 'monitoring_location'
    Assert-ValidRegionCode -RegionCode $Profile.monitoringRegionCode -ParameterName 'monitoring_region_code'
    Assert-ValidInstanceNumber -InstanceNumber $InstanceNumber
    Assert-ValidAdminSourceCidr -EnableVmPublicIp $EnableVmPublicIp -AdminSourceCidr $AdminSourceCidr

    if ([string]::IsNullOrWhiteSpace($SshPublicKey)) {
        throw 'SshPublicKey is required and cannot be empty.'
    }

    if ($AlertEmailAddress -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        throw "AlertEmailAddress '$AlertEmailAddress' is not a valid email address."
    }

    return [ordered]@{
        application             = $Application
        environment              = $Profile.environment
        workload_location        = $Profile.workloadLocation
        workload_region_code     = $Profile.workloadRegionCode
        monitoring_location      = $Profile.monitoringLocation
        monitoring_region_code   = $Profile.monitoringRegionCode
        instance_number          = $InstanceNumber
        ssh_public_key           = $SshPublicKey
        enable_vm_public_ip      = $EnableVmPublicIp
        admin_source_cidr        = $AdminSourceCidr
        alert_email_address      = $AlertEmailAddress
    }
}

function Write-TerraformAutoTfVarsFile {
    <#
    .SYNOPSIS
    Serializes a Terraform auto-tfvars object to disk atomically, with overwrite protection.

    .DESCRIPTION
    Writes JSON via ConvertTo-Json (never manual string concatenation) to a temporary file in
    the destination directory, then renames it into place. The destination is never partially
    written: if serialization or the temporary write fails, the destination file is untouched;
    the temporary file is always removed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$Force
    )

    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        throw "Refusing to overwrite existing file '$Path' without -Force."
    }

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -Path $directory -ItemType Directory -Force
    }

    $json = $InputObject | ConvertTo-Json -Depth 10
    $tempPath = Join-Path -Path $directory -ChildPath (".{0}.{1}.tmp" -f (Split-Path -Path $Path -Leaf), [guid]::NewGuid().ToString('N'))

    try {
        Set-Content -LiteralPath $tempPath -Value $json -Encoding utf8 -NoNewline -ErrorAction Stop
        Move-Item -LiteralPath $tempPath -Destination $Path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function @(
    'Get-AssessmentProfileFromFile',
    'Assert-ValidAssessmentProfile',
    'Assert-ValidApplicationName',
    'Assert-ValidEnvironmentName',
    'Assert-ValidRegionCode',
    'Assert-ValidLocationName',
    'Assert-ValidInstanceNumber',
    'Assert-ValidAdminSourceCidr',
    'Assert-ConsistentEnvironment',
    'New-BootstrapRemoteStateTfVars',
    'New-EnvironmentDevTfVars',
    'Write-TerraformAutoTfVarsFile'
)

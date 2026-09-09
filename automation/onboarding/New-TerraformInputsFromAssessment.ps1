<#
.SYNOPSIS
Generates local Terraform auto-tfvars input files from a successful subscription portability assessment.

.DESCRIPTION
Reads a GO onboarding assessment profile produced by Invoke-SubscriptionPortabilityAssessment.ps1 and
writes bootstrap/remote-state/terraform.auto.tfvars.json and environments/dev/terraform.auto.tfvars.json.

Values present in the assessment profile (environment, workload/monitoring location and region code) are
taken from the profile. Deployment-specific values the profile does not carry (application, instance
number, SSH public key, alert email address, and the optional public SSH exception) must be supplied as
parameters.

This script performs no Azure calls, no Terraform commands, and never generates secret values. It only
writes local JSON files that are already git-ignored.

.PARAMETER ProfilePath
Path to a GO onboarding assessment profile JSON file.

.PARAMETER Application
Short application/workload identifier (matches environments/dev's `application` variable).

.PARAMETER Environment
Optional. If supplied, must match the assessment profile's environment. If omitted, the profile's
environment is used.

.PARAMETER InstanceNumber
Zero-padded 3-digit instance number (matches the `instance_number` variable in both Terraform roots).

.PARAMETER SshPublicKey
Public SSH key for the Linux VM admin account (matches `ssh_public_key`).

.PARAMETER AlertEmailAddress
Email address for Azure Monitor alert notifications (matches `alert_email_address`).

.PARAMETER EnableVmPublicIp
Opt-in to create a VM Public IP and inbound SSH rule. Defaults to false (secure default).

.PARAMETER AdminSourceCidr
Single explicit CIDR allowed to SSH when EnableVmPublicIp is set. Defaults to null.

.PARAMETER RepositoryRoot
Path to the repository root. Defaults to two levels above this script (automation/onboarding/..\..).

.PARAMETER Force
Overwrites existing generated files. Without this switch, existing files are left untouched.

.PARAMETER PassThru
Returns the resolved output file paths.

.EXAMPLE
./automation/onboarding/New-TerraformInputsFromAssessment.ps1 `
    -ProfilePath .generated/onboarding/dev-profile.json `
    -Application core `
    -InstanceNumber 001 `
    -SshPublicKey (Get-Content ~/.ssh/id_ed25519.pub -Raw) `
    -AlertEmailAddress ops-alerts@example.invalid

.EXAMPLE
./automation/onboarding/New-TerraformInputsFromAssessment.ps1 `
    -ProfilePath .generated/onboarding/dev-profile.json `
    -Application core `
    -InstanceNumber 001 `
    -SshPublicKey (Get-Content ~/.ssh/id_ed25519.pub -Raw) `
    -AlertEmailAddress ops-alerts@example.invalid `
    -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProfilePath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{1,10}$')]
    [string]$Application,

    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]{3}$')]
    [string]$InstanceNumber,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SshPublicKey,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AlertEmailAddress,

    [switch]$EnableVmPublicIp,

    [string]$AdminSourceCidr,

    [string]$RepositoryRoot,

    [switch]$Force,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'TerraformInputGenerator.psm1'
Import-Module $modulePath -Force

try {
    $resolvedRepositoryRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
    }
    else {
        Resolve-Path -Path $RepositoryRoot
    }

    $bootstrapOutputPath = Join-Path -Path $resolvedRepositoryRoot -ChildPath 'bootstrap\remote-state\terraform.auto.tfvars.json'
    $environmentOutputPath = Join-Path -Path $resolvedRepositoryRoot -ChildPath 'environments\dev\terraform.auto.tfvars.json'

    $assessmentProfile = Get-AssessmentProfileFromFile -Path $ProfilePath
    Assert-ValidAssessmentProfile -Profile $assessmentProfile
    Assert-ConsistentEnvironment -RequestedEnvironment $Environment -ProfileEnvironment $assessmentProfile.environment

    $adminSourceCidrValue = if ([string]::IsNullOrWhiteSpace($AdminSourceCidr)) { $null } else { $AdminSourceCidr }

    $bootstrapTfVars = New-BootstrapRemoteStateTfVars -Profile $assessmentProfile -InstanceNumber $InstanceNumber
    $environmentTfVars = New-EnvironmentDevTfVars -Profile $assessmentProfile -Application $Application -InstanceNumber $InstanceNumber `
        -SshPublicKey $SshPublicKey -AlertEmailAddress $AlertEmailAddress -EnableVmPublicIp:$EnableVmPublicIp.IsPresent -AdminSourceCidr $adminSourceCidrValue

    if ((Test-Path -LiteralPath $bootstrapOutputPath) -and -not $Force) {
        throw "Refusing to overwrite existing file '$bootstrapOutputPath' without -Force."
    }

    if ((Test-Path -LiteralPath $environmentOutputPath) -and -not $Force) {
        throw "Refusing to overwrite existing file '$environmentOutputPath' without -Force."
    }

    if ($PSCmdlet.ShouldProcess($bootstrapOutputPath, 'Write Terraform auto-tfvars JSON')) {
        Write-TerraformAutoTfVarsFile -InputObject $bootstrapTfVars -Path $bootstrapOutputPath -Force:$Force.IsPresent
    }

    if ($PSCmdlet.ShouldProcess($environmentOutputPath, 'Write Terraform auto-tfvars JSON')) {
        Write-TerraformAutoTfVarsFile -InputObject $environmentTfVars -Path $environmentOutputPath -Force:$Force.IsPresent
    }

    Write-Information ("Environment: {0}" -f $assessmentProfile.environment) -InformationAction Continue
    Write-Information ("Workload: {0} [{1}]" -f $assessmentProfile.workloadLocation, $assessmentProfile.workloadRegionCode) -InformationAction Continue
    Write-Information ("Monitoring: {0} [{1}]" -f $assessmentProfile.monitoringLocation, $assessmentProfile.monitoringRegionCode) -InformationAction Continue
    Write-Information ("Public SSH access: {0}" -f $EnableVmPublicIp.IsPresent) -InformationAction Continue
    Write-Information ("Bootstrap tfvars: {0}" -f $bootstrapOutputPath) -InformationAction Continue
    Write-Information ("Environment tfvars: {0}" -f $environmentOutputPath) -InformationAction Continue

    if ($PassThru) {
        return [pscustomobject]@{
            BootstrapTfVarsPath   = $bootstrapOutputPath
            EnvironmentTfVarsPath = $environmentOutputPath
        }
    }
}
catch {
    $message = $_.Exception.Message
    Write-Error ("Terraform input generation failed: {0}" -f $message)
    throw
}

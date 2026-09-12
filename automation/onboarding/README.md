# Subscription Portability Foundation

## Purpose

This capability provides a safe, reusable, read-only onboarding assessment for new Azure tenants and subscriptions.

The operator flow is:

1. `az login`
2. Run one onboarding command
3. Receive `GO` or `NO-GO` plus a generated profile
4. Later trigger one GitHub workflow

No Terraform deployment, backend creation, or Azure write operation is performed by this capability.

## Architecture

- `Invoke-SubscriptionPortabilityAssessment.ps1`
  - operator entry point
  - parameter validation
  - live or offline assessment orchestration
  - profile file generation
- `SubscriptionPortability.Foundation.psm1`
  - pure naming and masking functions
  - Azure CLI read-only wrappers
  - provider, region, SKU, and quota assessment functions
  - profile serialization helpers
- `tests/SubscriptionPortability.Foundation.Tests.ps1`
  - pure logic unit tests with no live Azure dependency

## Prerequisites

- PowerShell 7+
- Azure CLI available in `PATH` for live assessments
- Existing Azure CLI sign-in context from `az login`
- No tenant or subscription switching is performed automatically

## Read-Only Guarantee

The implementation uses only non-mutating Azure CLI commands during live assessment.

It does not:

- deploy infrastructure
- run Terraform
- register providers
- change Azure CLI context
- create identities or RBAC assignments
- query or expose secrets

The only local write is the generated JSON profile under `.generated/`.

## Failure Handling Model

Expected assessment failures are classified into a structured `NO-GO` profile and do not terminate the script with an unhandled exception.

Examples of expected failures:

- Azure CLI executable unavailable
- Azure account context unavailable
- Azure account context JSON invalid or incomplete
- subscription disabled
- expected tenant mismatch
- expected subscription mismatch

Unexpected programming defects are still surfaced as terminating errors after a safe error message is emitted.

When Azure context is unavailable, the generated failure profile uses:

- `tenantId = null`
- `subscriptionId = null`
- `maskedTenantId = "<unavailable>"`
- `maskedSubscriptionId = "<unavailable>"`

No synthetic tenant or subscription IDs are generated.

## Parameters

- `Environment`
- `WorkloadLocation`
- `WorkloadRegionCode`
- `MonitoringLocation`
- `MonitoringRegionCode`
- `AddressSpace`
- `VmSize`
- `AppServiceSku`
- `ExpectedTenantId`
- `ExpectedSubscriptionId`
- `OutputPath`
- `PassThru`
- `Offline`

Default values are aligned to the currently proven PowerShell deployment model:

- `Environment = dev`
- `WorkloadLocation = denmarkeast`
- `WorkloadRegionCode = deu`
- `MonitoringLocation = swedencentral`
- `MonitoringRegionCode = swe`
- `AddressSpace = 10.0.0.0/16`
- `VmSize = Standard_B1s`
- `AppServiceSku = B1`

Validation is intentionally strict for the portable assessment inputs:

- `ExpectedTenantId` and `ExpectedSubscriptionId` accept only canonical GUIDs in `8-4-4-4-12` hexadecimal form when supplied.
- `AddressSpace` must be a valid IPv4 CIDR block such as `10.0.0.0/16`.

## Examples

Live assessment against the current Azure CLI context:

```powershell
.\automation\onboarding\Invoke-SubscriptionPortabilityAssessment.ps1 `
    -ExpectedTenantId "<EXPECTED_TENANT_ID>" `
    -ExpectedSubscriptionId "<EXPECTED_SUBSCRIPTION_ID>" `
    -PassThru
```

Offline dry run for local validation:

```powershell
.\automation\onboarding\Invoke-SubscriptionPortabilityAssessment.ps1 `
    -Offline `
    -PassThru
```

## GO / NO-GO Meaning

- `GO`
  - no blocked checks
  - no unverifiable mandatory checks
- `NO-GO`
  - expected tenant or subscription mismatch
  - disabled subscription
  - missing provider registration
  - unsupported location or resource type
  - restricted or unavailable SKU
  - unverifiable mandatory live check

Warnings do not block `GO`, but they must be reviewed.

## Blocker Codes

Stable blocker code prefixes are included in blocker entries:

- `AzureCliUnavailable`
- `AzureContextUnavailable`
- `AzureContextInvalid`
- `SubscriptionDisabled`
- `TenantMismatch`
- `SubscriptionMismatch`

Additional `NotVerifiable` blocker codes can appear for dependent checks when context is unavailable.

## Azure CLI Stream Handling

- stdout and stderr are captured independently.
- JSON parsing is performed from stdout only.
- stderr warnings do not invalidate valid stdout JSON.
- non-zero exit codes, empty stdout, and invalid JSON are classified as structured failures.
- Azure CLI arguments are passed as argument arrays without `Invoke-Expression`.

## Generated Profile Schema

The profile JSON contains:

- `schemaVersion`
- `generatedAtUtc`
- `assessmentOutcomeType` (`Approved` or `Failure`)
- `environment`
- `tenantId`
- `subscriptionId`
- `maskedTenantId`
- `maskedSubscriptionId`
- `workloadLocation`
- `workloadRegionCode`
- `monitoringLocation`
- `monitoringRegionCode`
- `addressSpace`
- `vmSize`
- `appServiceSku`
- `deterministicSuffix`
- `proposedNames`
- `providerResults`
- `regionResults`
- `skuResults`
- `quotaResults`
- `overallStatus`
- `blockers`
- `warnings`

Runtime profiles can contain real tenant and subscription identifiers. They are written to `.generated/` and must never be committed.

## Security Handling

- Full tenant and subscription IDs are stored only in the generated local profile.
- Console output shows masked IDs only.
- No credentials, tokens, secrets, private keys, or personal email addresses are written.

## Terraform Input Generation

A successful `GO` profile can be converted into local Terraform input files:

```powershell
.\automation\onboarding\New-TerraformInputsFromAssessment.ps1 `
    -ProfilePath .\.generated\onboarding\dev-profile.json `
    -Application core `
    -InstanceNumber 001 `
    -SshPublicKey (Get-Content ~/.ssh/id_ed25519.pub -Raw) `
    -AlertEmailAddress ops-alerts@example.invalid
```

The generator creates:

- `bootstrap/remote-state/terraform.auto.tfvars.json`;
- `environments/dev/terraform.auto.tfvars.json`.

Both files are local runtime configuration and are excluded from Git. Public VM
access remains disabled unless it is explicitly enabled with a valid,
restricted administrator CIDR.

Use `-WhatIf` to preview file generation. Existing files are protected unless
`-Force` is supplied.

## Current Automation Boundary

Implemented:

- read-only subscription portability assessment;
- `GO` / `NO-GO` decision;
- local assessment profile generation;
- validated Terraform input generation.

Still handled separately:

- remote-state deployment;
- environment `backend.hcl` configuration;
- OIDC identity and federated credential provisioning;
- Terraform plan and apply workflows;
- GitHub environment approvals.

## Target Five-Minute Migration Workflow

1. Authenticate with Azure CLI.
2. Run the portability assessment.
3. Confirm a `GO` decision.
4. Generate the Terraform input files.
5. Bootstrap or select the remote-state backend.
6. Initialize Terraform with the environment backend.
7. Review the Terraform plan.
8. Run the approved deployment workflow.

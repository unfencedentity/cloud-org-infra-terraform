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

## Examples

Live assessment against the current Azure CLI context:

```powershell
./automation/onboarding/Invoke-SubscriptionPortabilityAssessment.ps1 `
  -ExpectedTenantId "00000000-0000-0000-0000-000000000000" `
  -ExpectedSubscriptionId "11111111-1111-1111-1111-111111111111"
```

Offline dry run for local validation:

```powershell
./automation/onboarding/Invoke-SubscriptionPortabilityAssessment.ps1 -Offline -PassThru
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

## Generated Profile Schema

The profile JSON contains:

- `schemaVersion`
- `generatedAtUtc`
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

## Capability 2 Boundary

This capability stops after assessment and profile generation.

Capability 2 remains responsible for:

- backend bootstrap
- persistent CI variables or secrets
- OIDC identity provisioning
- Terraform workflow execution

## Future Five-Minute Migration Workflow

Target experience:

1. `az login`
2. Run `Invoke-SubscriptionPortabilityAssessment.ps1`
3. Review `GO` or `NO-GO`
4. Trigger GitHub workflow once Capability 2 and CI/CD are in place
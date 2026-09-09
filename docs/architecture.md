# Architecture

This document describes the current architecture of this repository: the
Azure infrastructure Terraform manages, the ownership boundaries between
Terraform and PowerShell, and the subscription portability assessment flow
used before onboarding a tenant or subscription.

## High-Level Azure Architecture

The `environments/dev` Terraform root deploys an application landing zone
split across a workload region and a monitoring region:

- A virtual network with dedicated subnets for the application VM, private
  endpoints, and App Service VNet integration (with a `Microsoft.Web/serverFarms`
  delegation).
- A network security group attached to the application subnet.
- A Linux virtual machine with a user-assigned managed identity, a static
  public IP, and boot diagnostics.
- A Key Vault using RBAC authorization, accessed through the VM's managed
  identity and the deploying principal; Terraform does not create or store
  any secret values, and purge protection is enabled.
- A storage account reachable only through a private endpoint into the blob
  private DNS zone (public network access and shared-key authentication are
  both disabled).
- A Log Analytics workspace and Application Insights instance, deployed in
  the monitoring region, used as diagnostic and monitoring targets.
- A Recovery Services vault with a daily/weekly/monthly VM backup policy
  protecting the virtual machine.
- Azure Monitor: an action group (email notification), a VM CPU metric alert,
  a subscription-level Service Health activity log alert, and diagnostic
  settings routing VM, NSG, and Key Vault logs/metrics to Log Analytics.

The `bootstrap/remote-state` Terraform root deploys the infrastructure that
Terraform itself depends on: a resource group, an Azure AD-only storage
account with blob versioning and retention, a blob container for state files,
an RBAC role assignment granting the deploying principal blob data access, and
a management lock preventing deletion of the state storage account.

## Terraform Ownership Boundaries

- `bootstrap/remote-state` owns only the remote state backend. It is applied
  once per environment scope and is protected by `prevent_destroy` and a
  management lock; it is not touched by routine environment changes.
- `environments/<name>` owns the deployed application landing zone for that
  environment. Each environment has its own state file, backend
  configuration, and variables, and environments do not reference each
  other's state.
- `modules/` is reserved for shared Terraform modules but currently contains
  no modules; all environment resources are defined directly in the
  environment root.
- No Terraform code depends on, or is executed by, the PowerShell onboarding
  automation described below.
- Each Terraform root's `terraform.tfvars` and `backend.hcl` hold
  environment-specific, non-public values (resource group names, storage
  account names, keys). They are git-ignored; only the `.tfvars.example` and
  `.hcl.example` templates with placeholder values are tracked.

## Naming and Region Convention

All resource names and tags are derived from `terraform.tfvars` inputs
(`application`, `environment`, `workload_location`, `workload_region_code`,
`monitoring_location`, `monitoring_region_code`, `instance_number`) using an
`Application-Environment-Region-Instance` convention, matching the naming
concept used by the `cloud-org-infra` PowerShell repository. No environment,
region, or instance value is hardcoded in `.tf` files.

- Workload resources (VNet, subnets, NSG, VM, Key Vault, storage account, App
  Service, Recovery Services vault, etc.) are named `<type>-<name_prefix>` and
  deployed to `workload_location`, where `name_prefix` is
  `${application}-${environment}-${workload_region_code}-${instance_number}`.
- Monitoring resources whose region can legitimately differ from the workload
  (the Log Analytics workspace and Application Insights) are named
  `<type>-<monitoring_name_prefix>` and deployed to `monitoring_location`,
  using `monitoring_region_code` in place of `workload_region_code`.
- Globally-unique or length-restricted resources (Storage Account, Key Vault,
  the VM's `computer_name`) use a hyphen-free compact variant of
  `name_prefix`. The `bootstrap/remote-state` storage account additionally
  keeps its original fully-hashed, subscription-derived name for global
  uniqueness and to avoid revealing the environment/region in the name.
- Every resource that supports Azure tags is tagged with at least
  `Application`, `Environment`, `Region`, and `ManagedBy = Terraform`.
- `bootstrap/remote-state` uses the same convention with a fixed
  `Application = "tfstate"` tag, since the remote-state backend is not
  associated with a single application.

## Portability Assessment Flow

The onboarding automation under `automation/onboarding/` performs a read-only
assessment of whether a tenant/subscription is ready for an environment
deployment, without invoking Terraform or changing Azure state:

```
Invoke-SubscriptionPortabilityAssessment.ps1  (entrypoint)
        -> Invoke-AzureCliProcess / Invoke-AzureCliJson  (Azure CLI adapter)
        -> Azure context, subscription state, provider, region, SKU, quota checks
        -> Get-AssessmentOutcome  (GO / NO-GO classification)
        -> New-SubscriptionPortabilityProfile  (JSON profile written to .generated/)
```

- The **entrypoint** script validates operator-supplied parameters (or uses
  offline defaults), orchestrates the checks, and writes the resulting
  profile.
- The **Azure CLI adapter** (`Invoke-AzureCliProcess`) launches the resolved
  `az` executable directly through `ProcessStartInfo`, using an argument list
  rather than a shell command string. When the resolved command is the
  Windows `az.cmd` launcher, it instead launches the sibling native
  interpreter directly, bypassing `cmd.exe` entirely, so Azure CLI arguments
  are never re-parsed by a shell. `Invoke-AzureCliJson` wraps this to
  separate stdout/stderr, classify non-zero exit codes, and parse JSON.
- **Context/capability checks** validate the active Azure CLI account
  context, subscription state, expected tenant/subscription match, resource
  provider registration, resource type/location availability, VM SKU
  restrictions, compute quota, and App Service SKU availability.
- **GO/NO-GO** classification (`Get-AssessmentOutcome`) treats any `Blocked`
  or `NotVerifiable` result as a blocker; only warnings are allowed alongside
  `GO`.
- The **JSON profile** contains masked identifiers for display, full
  identifiers for automation, proposed deterministic resource names, and the
  full set of check results; it is written under `.generated/` and is not
  committed to version control.

## Role of `SubscriptionPortability.Foundation.psm1`

This module contains the assessment's implementation logic as pure,
independently testable functions:

- Identifier masking and safe text redaction for console/log output.
- Deterministic resource name and suffix generation from tenant/subscription
  identifiers.
- The Azure CLI process adapter and JSON wrapper described above.
- Individual assessment functions for Azure context, subscription state,
  region/location validity, resource provider registration, resource type
  location support, VM SKU, compute quota, and App Service SKU.
- Profile construction (`New-SubscriptionPortabilityProfile`) and console
  summary output (`Write-AssessmentSummary`).

It has no dependency on Terraform and performs no mutating Azure operations.

## Role of the Pester Test File

`automation/onboarding/tests/SubscriptionPortability.Foundation.Tests.ps1`
unit-tests the foundation module in isolation:

- Pure logic (masking, naming, outcome aggregation, profile serialization) is
  tested directly.
- Azure CLI interactions are tested using mocks and, for the Windows launcher
  path, a fake `az.cmd`/native-interpreter fixture, so the suite has no live
  Azure dependency and does not require `az login`.
- A dedicated security regression test verifies that arguments containing
  `cmd.exe` metacharacters are passed to the resolved Azure CLI executable
  literally, and that no second command can be executed through argument
  injection.

## Backend Bootstrap vs. Environment Deployment

| | `bootstrap/remote-state` | `environments/<name>` |
|---|---|---|
| Purpose | Creates the Terraform remote state backend | Deploys the application landing zone |
| Applied | Once per environment scope, before first environment deploy | Whenever environment infrastructure changes |
| Protected by | `prevent_destroy`, management lock | Standard Terraform state locking only |
| Depends on | Nothing else in this repository | The remote-state backend it is configured to use |

## Known Current Limitations

- `SubscriptionPortability.Foundation.psm1` is a single monolithic module
  covering naming, masking, the Azure CLI adapter, and every individual
  assessment check; it is not yet split into smaller, independently
  versioned modules.
- There is no completed automated deployment workflow: the repository
  contains no CI/CD pipeline definitions, and `terraform plan`/`apply` for
  both `bootstrap/remote-state` and `environments/dev` are currently run
  manually. The onboarding README references a future "one GitHub workflow"
  trigger that does not yet exist in this repository.
- `modules/` is currently empty; environment roots duplicate resource
  definitions rather than sharing modules.
- Only a single `dev` environment root currently exists.

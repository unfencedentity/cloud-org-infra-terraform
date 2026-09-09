# cloud-org-infra-terraform

[![Terraform Quality Gate](https://github.com/unfencedentity/cloud-org-infra-terraform/actions/workflows/terraform-quality.yml/badge.svg)](https://github.com/unfencedentity/cloud-org-infra-terraform/actions/workflows/terraform-quality.yml)

Terraform-based Azure landing zone infrastructure for a single organization, with a
PowerShell-based read-only preflight assessment used before onboarding a new
tenant or subscription.

## Purpose

This repository provisions and manages Azure infrastructure using Terraform, and
provides a safe, read-only PowerShell assessment that determines whether a
tenant/subscription is ready for deployment before any Terraform is run.

## Current Terraform Capabilities

The `environments/dev` root currently provisions a core application landing
zone, including:

- Resource group, virtual network, and subnets (application, private endpoint,
  App Service integration with delegation)
- Network security group and rules
- Public IP and network interface
- User-assigned managed identity
- Key Vault (RBAC-authorized) with role assignments for the managed identity and
  the deploying principal; no secret values are created by Terraform
- Storage account with a private endpoint and private DNS zone for blob,
  shared-key authentication disabled
- Log Analytics workspace and Application Insights
- Linux virtual machine with managed identity and boot diagnostics
- Recovery Services vault with a VM backup policy and protected VM
- Azure Monitor action group, metric alert, service health alert, and
  diagnostic settings for the VM, NSG, and Key Vault

The `bootstrap/remote-state` root provisions the Terraform remote state
backend itself: a resource group, a storage account (Azure AD auth only,
versioning and retention enabled, `prevent_destroy` lifecycle), a blob
container, an RBAC role assignment for the current principal, and a
management lock preventing accidental deletion of the state storage account.

The `modules/` directory exists for shared Terraform modules but is currently
empty; all resources are defined directly in each environment root.

## Repository Structure

```
automation/onboarding/   PowerShell preflight assessment and its Pester tests
bootstrap/remote-state/  Terraform root that creates the remote state backend
docs/                    Architecture documentation
environments/dev/        Terraform root for the dev environment
modules/                 Reserved for shared Terraform modules (currently empty)
```

## Separation of Concerns

- **PowerShell preflight** (`automation/onboarding/`): read-only Azure CLI
  checks that classify a tenant/subscription as `GO` or `NO-GO` and produce a
  local JSON profile. It never runs Terraform and never performs Azure write
  operations.
- **Terraform deployment** (`bootstrap/`, `environments/`): the only part of
  the repository that creates, changes, or destroys Azure resources.
- **Pester testing** (`automation/onboarding/tests/`): unit tests for the
  preflight PowerShell logic only; it has no live Azure dependency and does
  not test Terraform.

See [docs/architecture.md](docs/architecture.md) for the detailed flow between
these layers.

## Remote-State Bootstrap Workflow

The remote state backend is created once per environment scope from
`bootstrap/remote-state`, before any environment root can use a remote
backend:

1. Copy `bootstrap/remote-state/terraform.tfvars.example` to
   `bootstrap/remote-state/terraform.tfvars` and populate it with
   `environment`, `workload_location`, `workload_region_code`,
   `instance_number`, and `state_container_name`. This file is git-ignored
   and must never be committed.
2. Run `terraform init`, `terraform plan`, and `terraform apply` from
   `bootstrap/remote-state`.
3. Copy `backend.hcl.example` to `backend.hcl` in the corresponding
   environment directory and record the resulting resource group, storage
   account, and container names there. This file is also git-ignored.

The state storage account enforces Azure AD authentication, blob versioning,
30-day delete retention, and a `CanNotDelete` management lock, so it is not
intended to be modified through routine environment changes.

## Environment Deployment Workflow

Each environment (for example `environments/dev`) is an independent Terraform
root with its own `backend.hcl`, `terraform.tfvars`, and state file:

1. Confirm the remote-state backend for that environment already exists (see
   above).
2. Copy `terraform.tfvars.example` and `backend.hcl.example` in the
   environment directory to `terraform.tfvars` and `backend.hcl`, then fill in
   the real, environment-specific values. Both files are git-ignored so local
   configuration never gets committed.
3. Run `terraform init -backend-config="backend.hcl"` from the environment
   directory.
4. Run `terraform plan` and review the change set.
5. Run `terraform apply` to provision or update resources.

Before onboarding a new tenant or subscription for an environment, run the
PowerShell preflight assessment described in
[automation/onboarding/README.md](automation/onboarding/README.md) and confirm
a `GO` result first.

## Naming and Region Convention

Resource names and tags are generated from `terraform.tfvars` inputs using an
`Application-Environment-Region-Instance` convention, matching the naming
concept used by the `cloud-org-infra` PowerShell repository:

- `application`, `environment`, `workload_region_code`, and `instance_number`
  combine into a name prefix (for example `core-dev-deu-001`), which resource
  names are built from (for example `rg-core-dev-deu-001`,
  `vnet-core-dev-deu-001`, `vm-core-dev-deu-001`).
- `workload_location` (an Azure region display name, e.g. `denmarkeast`) is
  where workload resources — the VNet, VM, Key Vault, storage account, App
  Service, etc. — are deployed.
- `monitoring_location` and `monitoring_region_code` (e.g. `swedencentral` /
  `swe`) are used only for the Log Analytics workspace and Application
  Insights, the two monitoring resources whose region can legitimately differ
  from the workload region.
- Globally-unique resources (Storage Account, Key Vault, VM computer name)
  use a hyphen-free, deterministic compact name built from the same inputs to
  respect Azure naming-length restrictions.
- Every resource that supports tags receives at least `Application`,
  `Environment`, `Region`, and `ManagedBy = Terraform`.

## Automated Terraform Validation

GitHub Actions validates the Terraform configuration on every push to `develop` and every pull request targeting `main`.

The quality gate runs:

- `terraform fmt -check -recursive`;
- `terraform init -backend=false -input=false`;
- `terraform validate -no-color` for `bootstrap/remote-state`;
- `terraform validate -no-color` for `environments/dev`.

The workflow performs formatting and static configuration validation only. It does not authenticate to Azure or run `terraform plan`, `apply`, or `destroy`.

## Branch Workflow

Changes are made on `develop`, submitted as a pull request, and merged into
`main` after review. Direct pushes to `main` are not part of the workflow.

## Further Reading

- [docs/architecture.md](docs/architecture.md) — high-level architecture,
  Terraform ownership boundaries, and the portability assessment flow.
- [automation/onboarding/README.md](automation/onboarding/README.md) — detailed
  onboarding assessment usage, parameters, and safety guarantees.

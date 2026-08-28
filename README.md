# cloud-org-infra-terraform

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
- Key Vault (RBAC-authorized) with an example secret and role assignments
- Storage account with a private endpoint and private DNS zone for blob
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

1. Populate `bootstrap/remote-state/terraform.tfvars` with the target resource
   group name, location, and state container name.
2. Run `terraform init`, `terraform plan`, and `terraform apply` from
   `bootstrap/remote-state`.
3. Record the resulting resource group, storage account, and container names
   in the corresponding environment's `backend.hcl`.

The state storage account enforces Azure AD authentication, blob versioning,
30-day delete retention, and a `CanNotDelete` management lock, so it is not
intended to be modified through routine environment changes.

## Environment Deployment Workflow

Each environment (for example `environments/dev`) is an independent Terraform
root with its own `backend.hcl`, `terraform.tfvars`, and state file:

1. Confirm the remote-state backend for that environment already exists (see
   above).
2. Run `terraform init -backend-config="backend.hcl"` from the environment
   directory.
3. Run `terraform plan` and review the change set.
4. Run `terraform apply` to provision or update resources.

Before onboarding a new tenant or subscription for an environment, run the
PowerShell preflight assessment described in
[automation/onboarding/README.md](automation/onboarding/README.md) and confirm
a `GO` result first.

## Branch Workflow

Changes are made on `develop`, submitted as a pull request, and merged into
`main` after review. Direct pushes to `main` are not part of the workflow.

## Further Reading

- [docs/architecture.md](docs/architecture.md) — high-level architecture,
  Terraform ownership boundaries, and the portability assessment flow.
- [automation/onboarding/README.md](automation/onboarding/README.md) — detailed
  onboarding assessment usage, parameters, and safety guarantees.

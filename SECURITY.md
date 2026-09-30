# Security Policy

## Supported Versions

This repository is maintained as an infrastructure engineering project rather
than a versioned software product.

| Version | Supported |
| --- | --- |
| `main` | Yes |
| `develop` and feature branches | No |

Security fixes are applied to `main` after validation and review.

## Reporting a Vulnerability

Please report suspected vulnerabilities through GitHub's private vulnerability
reporting feature.

Do not open a public issue containing:

- credentials, tokens, private keys, or secrets;
- Terraform state or generated runtime configuration;
- tenant, subscription, or resource identifiers;
- exploit instructions or other sensitive evidence.

If private vulnerability reporting is unavailable, open a minimal public issue
requesting a private contact channel without including sensitive details.

A useful report should include:

- the affected file, workflow, module, or Azure resource;
- steps required to reproduce the issue;
- the potential security impact;
- a suggested remediation, if available.

## Security Scope

Relevant findings include:

- exposed credentials or Terraform state;
- excessive Azure RBAC permissions;
- insecure network access;
- unsafe GitHub Actions permissions;
- command or argument injection;
- secret leakage in logs or generated files;
- infrastructure defaults that unintentionally expose Azure resources.

Please allow time to validate and remediate a report before public disclosure.

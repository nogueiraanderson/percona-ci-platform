# 0001 — OpenTofu over Terraform

**Status:** Accepted (2026-04-30)

## Context

Need an HCL-based IaC tool for AWS provisioning. Choices: HashiCorp Terraform vs
OpenTofu (community fork, MPL-2.0).

## Decision

Use OpenTofu **1.11.6** (released 2026-04-08).

## Consequences

- License clarity (MPL-2.0) vs Terraform's BUSL.
- Variable interpolation in `module.source` / `module.version` is a first-class
  feature in OpenTofu 1.8+ — used in `terraform/versions.tf` to keep all module
  pins in one map.
- All `terraform-aws-modules` work unmodified; provider ecosystem is identical.
- CI uses `opentofu/setup-opentofu@v1`; local dev pins via `justfile`.

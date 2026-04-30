# 0004 — EKS Pod Identity is the default; IRSA is the fallback

**Status:** Accepted (2026-04-30)

## Context

Two ways to grant AWS IAM permissions to a Kubernetes ServiceAccount on EKS:

1. **IRSA** (since 2019) — OIDC trust between cluster and IAM, role assumed via
   the SDK's web-identity provider.
2. **Pod Identity** (GA Nov 2023) — a managed agent runs as a DaemonSet, vends
   credentials to pods over a pinned link-local endpoint.

Pod Identity is now the AWS-recommended default; it removes per-cluster OIDC
trust policy churn and supports cross-account associations cleanly.

## Decision

Use **EKS Pod Identity** for all five day-one addons:

- AWS Load Balancer Controller
- external-dns
- Karpenter
- AWS EBS CSI Driver
- External Secrets Operator

Wired via `terraform-aws-modules/eks-pod-identity/aws` v2.8.0 with
`attach_<addon>_policy = true`. The `eks-pod-identity-agent` managed addon is
mandatory — without it, every association silently no-ops.

IRSA stays available via `terraform-aws-modules/iam/aws//modules/iam-role-for-
service-accounts-eks` for edge cases (legacy SDK quirks).

## Consequences

- Adding a new addon: one `local.modules.pod_identity` block in
  `terraform/pod-identity.tf` instead of an IRSA role + OIDC trust patch.
- The Jenkins EC2 plugin's classloader-isolated SDK v1 has historically
  intercepted IRSA's web-identity provider; behaviour under Pod Identity is
  **unverified** and must be tested on the ps3 PoC before committing the master
  workload to it. See `docs/lessons-from-poc.md`.

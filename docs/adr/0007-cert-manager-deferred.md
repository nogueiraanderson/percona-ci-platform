# 0007 — cert-manager deferred to v1.5

**Status:** Accepted (2026-04-30)

## Context

Earlier drafts had cert-manager in the v1 sync waves alongside ALB Controller
and external-dns. After review, the only cert-issuance path on day one is the
ACM wildcard fronting the shared ALB (ADR 0003). cert-manager would install a
controller, CRDs, and a webhook with no consumers.

## Decision

Do **not** install cert-manager in v1. Cut it from `argocd-bootstrap/
applicationsets/addons.yaml` sync waves. Keep the chart pin commented in
`terraform/versions.tf` so re-enabling later is a one-Application file plus
uncomment.

## When this gets revisited

cert-manager comes back when one of these appears:

- An in-cluster TLS issuer is needed (mTLS between services, internal Ingress
  not fronted by the public ALB, private CA backed by AWS PCA).
- A workload requires Let's Encrypt for a hostname outside `cd.percona.com` (so
  outside the ACM wildcard).
- Webhook certs for any operator that does not self-sign.

## Consequences

- Smaller install footprint, fewer CRDs, no webhook timing dependencies in the
  bootstrap waves.
- ACM is the single source of truth for TLS until v1.5.
- The Pod Identity association count stays at five (was six with cert-manager).

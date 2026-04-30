# 0009 — Central scrape now, agent + remote_write later (Jenkins fleet)

**Status:** Accepted (2026-04-30)

## Context

Ten Jenkins masters across five regions need to ship metrics to the central
Prometheus in `us-east-1`. Two architectures:

- **Option A — central scrape**: Prometheus on EKS pulls
  `https://<host>/prometheus` over public DNS, bearer-token auth.
- **Option B — agent + remote_write**: each Jenkins master runs Prometheus in
  agent mode and pushes to the central Prometheus' `/api/v1/write` (or to
  Mimir / Grafana Cloud later).

Option A is fastest to ship. Option B is the long-term right answer: one
outbound 443 hole per master, no NAT-GW EIP allowlist on the Jenkins side, and
the central side becomes location-independent.

## Decision

**v1 ships Option A.** Central scrape from EKS Prometheus over public DNS,
60 s interval, bearer-token auth via `additionalScrapeConfigs`. One shared
`prom-scraper` user with one bearer token mirrored across all 10 masters by
PS-10543's bootstrap groovy. Token lives in AWS Secrets Manager; External
Secrets Operator syncs it into the cluster.

**Production target is Option B.** Migration is gated on:

1. PS-10543 (prometheus plugin install + scraper user) closing.
2. PS-10996 (verify EC2 plugin metrics) closing.
3. PS-10997 (Hetzner plugin metrics in Java) closing.
4. SG tightening across all 10 Jenkins masters (drop the `0.0.0.0/0:443`
   rule).

## Consequences

- Day one: Jenkins SGs need each EKS NAT-GW EIP allowlisted on 443. Brittle.
  Acknowledged tax.
- Cross-region NAT-GW egress is metered on every scrape. Volume is small (one
  ~100 KB scrape per master per 60 s) but visible in Cost Explorer.
- Migrating to Option B is a values-file edit on the EKS side; the operational
  change is on the Jenkins-pipelines side (deploy `prometheus` agent unit on
  each master).
- The shared `prom-scraper` user model accepts one-token blast radius. Per-
  master tokens were considered and rejected — operational overhead (N rendered
  scrape jobs, N secrets) without a real security win for a read-only metrics
  endpoint. Rotation: update Secrets Manager, re-run the bootstrap groovy.
- Prometheus Agent's WAL is **not** a durable outage-survival mechanism (≈2 h
  buffer). Long central outages need a real remote backend (Mimir / Grafana
  Cloud / AMP) — that decision is downstream of this ADR.

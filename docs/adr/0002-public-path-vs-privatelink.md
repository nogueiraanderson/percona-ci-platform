# 0002 — Public-path connectivity, PrivateLink reserved

**Status:** Accepted (2026-04-30)

## Context

Ten Jenkins masters live in five AWS regions, in ten separate VPCs. Four of
those VPCs reuse the CIDR `10.177.0.0/22`, so any flat L3 fabric (Transit
Gateway, Cloud WAN, VPC peering) is blocked without a disruptive re-IP.

The day-one workload is SSL termination + HTTP(S) reverse-proxy. It does not
require private IP reachability.

## Decision

Connect to each Jenkins master over the public internet via NAT-GW EIPs
allowlisted in the master's Security Group. Each EKS NAT-GW EIP is added to
each Jenkins SG on 443.

PrivateLink (cross-region GA Nov 2024) is reserved as the upgrade trigger if a
private path becomes a hard requirement.

## Consequences

- Sidesteps the CIDR overlap problem entirely.
- SG entries (10 masters × N NAT-GW EIPs) become a small operational tax — each
  EKS-side NAT-GW EIP change requires updating ten SGs.
- Outbound scrape traffic is metered as cross-region NAT-GW egress.
- Switching to PrivateLink later is a per-master change: stand up an Endpoint
  Service in front of the Jenkins NLB, consume from EKS via Interface Endpoint,
  flip the proxy upstream from public DNS to the endpoint hostname.

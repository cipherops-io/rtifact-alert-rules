# Severity tiers

This document explains how rtifact-alert-rules decides the `severity` and `priority` labels for each alert.

## The two-axis model

We use **two** orthogonal labels to classify alerts:

- `severity`: the standard Prometheus convention — `critical`, `warning`, `info`
- `priority`: the operational pager priority — `P0`, `P1`, `P2`, `P3`

This is intentionally redundant. Severity is what dashboards, Grafana, and most Alertmanager templates expect. Priority is what your on-call rotation cares about.

## When to use which

### `critical` + `P0`

Hard, immediate user impact OR control-plane outage. Examples:
- `EtcdNoLeader`
- `K8sAPIServerDown` (if you have one)
- `RabbitMQMemoryAlarm` (publishing is blocked cluster-wide)
- `CNPGClusterPrimaryNotReady`

### `critical` + `P1`

User impact, but a quorum/replica/secondary still works OR there's a 5-15 minute grace period. Examples:
- `CNPGClusterDegraded` (replica lost but primary OK)
- `KafkaOfflinePartitions`
- `K8sNodeNotReady`

### `critical` + `P2`

Critical but on a tier that doesn't get a 3am page. Often used by tenancy-aware platforms for non-prod tenants.

### `warning` + `P2`

Cause alerts ("this will become bad soon") and SLO yellow-line. Examples:
- `K8sPVCFillingUp` (15% free)
- `KafkaConsumerGroupLagHigh` (10k messages)
- `PrometheusHighCardinality`

### `warning` + `P3`

Tuning opportunities and informational. Examples:
- `RedisMemoryFragmentationHigh`
- `MySQLQCacheHitRatioLow`
- `MongoDBFlushAverageMsHigh`

### `info` + `P3`

Audit / awareness. Examples:
- `CNPGClusterFailoverOccurred` — happened, you should know, no action needed
- "Cluster autoscaler scaled up by N nodes"

## What we explicitly avoid

| Combo | Why |
|---|---|
| `critical` + `P3` | "Critical but don't worry about it" — pick one |
| `info` + `P0` | "Page me about this informational thing" — pick one |
| `severity: page` / `severity: pageable` | Non-standard. Use `critical` + `P0` instead. |
| Severity computed from a metric | Static labels only. If you need conditional severity, write two rules with different thresholds. |
| `for: 0s` on `warning` rules | Flaps will spam. Always use ≥ `5m` for warnings. |

## Per-stack tier defaults

Most stacks ship with at least one `critical+P1` "I'm down" alert. Stack-specific guidance:

| Stack | Lowest severity covered | Highest severity covered |
|---|---|---|
| `etcd` | warning P2 (defrag needed) | critical P1 (no leader, backend quota) |
| `argocd` | warning P2 (out of sync) | critical P1 (down, repo-server down) |
| `cnpg` / `postgresql` | warning P3 (autovacuum overdue) | critical P1 (primary down, dead replication slot) |
| `kafka` | warning P2 (under-replicated) | critical P1 (offline partitions, no controller) |
| `redis` | warning P3 (fragmentation) | critical P1 (down, cluster nodes down) |
| `prometheus` | warning P2 (high cardinality) | critical P1 (down, WAL corruption) |
| `vmagent` | warning P2 (queue backlog) | critical P1 (down, all remote-writes failing) |

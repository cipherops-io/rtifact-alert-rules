# Label contract

Every alert in `rtifact-alert-rules` must carry the same set of labels and annotations. This contract is what allows downstream Alertmanager routing, dashboards, and runbook automation to be uniform across every tech stack we cover.

## Required labels

| Label | Allowed values | Purpose |
|---|---|---|
| `severity` | `critical`, `warning`, `info` | Standard Prometheus severity convention. Also used by most Alertmanager configs as the primary routing key. |
| `priority` | `P0`, `P1`, `P2`, `P3` | On-call response priority. P0 = page now, P1 = page within 15min, P2 = ticket, P3 = informational. |
| `tech_stack` | controlled enum (see below) | Which technology this alert belongs to. Used for grouping and team-based routing. |
| `signal` | `symptom`, `cause`, `slo-burn` | SRE distinction. Symptom alerts = "user is suffering". Cause alerts = "we expect a problem soon". SLO-burn = error-budget burn-rate alerts. |
| `category` | see enum in `scripts/validate_labels.py` | High-level grouping for routing (workload, data, network, control-plane, etc.) |
| `runbook` | `runbooks/<category>/<stack>.md` | Path to the runbook for this stack, in this repo. |

## Required annotations

| Annotation | Purpose |
|---|---|
| `summary` | One-line, action-oriented summary used in pager/Slack notifications |
| `description` | Multi-line context with `{{ $labels.x }}` and `{{ $value }}` templating |
| `runbook_url` | Resolved URL to the runbook (typically the GitHub URL of the runbook md file) |

## Allowed `tech_stack` enum

Maintained in `scripts/validate_labels.py`. To add a new value, edit `ALLOWED_TECH_STACKS` and submit a PR.

Currently:

- **kubernetes**: `kubernetes`, `apiserver`, `coredns`, `kubelet`, `node-exporter`, `kube-state-metrics`, `etcd`
- **gitops**: `argocd`
- **databases**: `postgresql`, `cnpg`, `mysql`, `mongodb`, `redis`, `elasticsearch`, `clickhouse`
- **messaging**: `kafka`, `rabbitmq`
- **caching**: `memcached`
- **observability**: `prometheus`, `alertmanager`, `grafana`, `prometheus-operator`, `victoriametrics`, `vmagent`, `vmalert`, `loki`
- **ingress**: `nginx-ingress`
- **runtimes**: `java-springboot`, `python-fastapi`

## Severity vs priority — pick the right combo

Severity is **the standard Prometheus convention** used by virtually every dashboard and Alertmanager template in the wild. Priority is **operational**: it answers "do I get paged at 3am?".

You can have:

| Combo | Example | Why |
|---|---|---|
| `critical` + `P0` | etcd has no leader | Total outage of a critical system, page immediately |
| `critical` + `P1` | DB primary not ready | User-impacting, page within 15min |
| `critical` + `P2` | A non-critical-tier database is down | Operational issue but ticket-able |
| `warning` + `P2` | Replica lag > 30s | Will likely become critical, work it during the day |
| `warning` + `P3` | Cache hit ratio is low | Tuning opportunity, not an outage |
| `info` + `P3` | Failover occurred | Audit/awareness only |

Avoid:

- `critical` + `P3` (contradiction)
- `info` + `P0` (contradiction)

## Symptom vs cause vs slo-burn

- **`symptom`**: an end-user-perceivable problem (high error rate, request latency above SLO, queue not draining). Should usually page.
- **`cause`**: an internal condition that *will probably* lead to a symptom soon (high CPU, low disk, high replication lag). Should usually warn but not page, unless it's a hard contract violation (e.g. etcd no leader).
- **`slo-burn`**: error-budget burn-rate alerts using multi-window multi-burn-rate (MWMBR). Distinct because they have different routing/escalation policies.

## Anti-patterns

These are explicitly disallowed by the contract. Most are caught by the validator, some are PR-review concerns.

1. **No `runbook_url`.** Every alert must have one. If you don't know what to write, write "investigate using the upstream documentation" — even that is better than nothing.
2. **`for: 0s` on warnings.** A flap in a metric should not generate a notification. Use at least `for: 5m` for warnings, `for: 1m` for criticals.
3. **`severity: page`.** Use `critical` and let `priority` decide who gets paged.
4. **Adding labels not in the contract.** Routing logic depends on the contract being closed. If you need a new label, propose it via PR.
5. **Computing severity inside the expression.** `severity` should be a static label on the rule, not computed from a `vector(0)` trick.

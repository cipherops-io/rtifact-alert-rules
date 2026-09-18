# rtifact-alert-rules

> Production-grade Prometheus alert rules for the Kubernetes ecosystem — tested in CI, opinionated, and runbook-backed.

`rtifact-alert-rules` is a curated, validated, opinionated library of Prometheus alerting rules. Every rule is:

- **Tested in CI** with `promtool check rules` (syntax) and `promtool test rules` (logical correctness with synthetic series)
- **Labeled to a strict contract** (`severity`, `priority`, `tech_stack`, `signal`, `category`)
- **Runbook-backed** — every `tech_stack` has a markdown runbook in `runbooks/` that the CI verifies exists
- **Engine-portable** — plain Prometheus group YAML, works directly with Prometheus, [vmalert](https://docs.victoriametrics.com/vmalert/), Grafana Mimir, Thanos Ruler, Cortex
- **Curated** — no copy-paste duplicates, deprecated metric names removed, every expression hand-audited

It is **not** a "kitchen-sink" of every alert that has ever been written. Quality over quantity.

## What's covered

| Category | Files |
|---|---|
| **Kubernetes** | `apiserver`, `coredns`, `etcd`, `kube-state-metrics`, `kubelet`, `node-exporter`, `workloads` |
| **GitOps** | `argocd` |
| **Databases** | `postgresql`, `cnpg`, `mysql`, `mongodb`, `redis`, `elasticsearch`, `clickhouse` |
| **Messaging** | `kafka`, `rabbitmq` |
| **Caching** | `memcached` |
| **Ingress** | `nginx-ingress` |
| **Observability** | `prometheus`, `prometheus-operator`, `alertmanager`, `grafana`, `victoriametrics`, `vmagent`, `vmalert`, `loki` |
| **Runtimes** | `java-springboot`, `python-fastapi` |

See the auto-generated [`docs/catalog.md`](docs/catalog.md) for every alert with its severity, expression, and runbook link.

## Quick start

### Use a single rule file directly with Prometheus / vmalert

```bash
# Prometheus (in prometheus.yml):
rule_files:
  - /etc/prometheus/rules/postgresql.yml

# vmalert flag:
./vmalert -rule=./rules/metrics/databases/postgresql.yml -datasource.url=http://victoriametrics:8428
```

### Validate rules locally

```bash
make lint        # promtool check rules + yamllint
make test        # promtool test rules (executes the unit tests in tests/)
make validate    # check the label contract
make all         # everything above
```

### Apply on Prometheus Operator clusters

```bash
# Wrap as PrometheusRule CRD (see scripts/render-prom-operator.sh)
./scripts/render-prom-operator.sh > dist/prometheus-rules.yaml
kubectl apply -f dist/prometheus-rules.yaml -n monitoring
```

## Label contract

Every rule MUST carry these labels. CI enforces it.

| Label | Allowed values | Purpose |
|---|---|---|
| `severity` | `critical`, `warning`, `info` | Standard Prometheus severity convention |
| `priority` | `P0`, `P1`, `P2`, `P3` | Pager / on-call response priority |
| `tech_stack` | controlled enum (see `docs/conventions/label-contract.md`) | Which technology this alert belongs to |
| `signal` | `symptom`, `cause`, `slo-burn` | SRE distinction (what the user feels vs why) |
| `category` | `workload`, `data`, `network`, `control-plane`, `app`, `storage` | High-level grouping |
| `runbook` | `runbooks/<category>/<stack>.{md,yaml}` | Path to the runbook in this repo (CI checks the file exists) |

Every rule MUST also have annotations: `summary`, `description`, `runbook_url`.

See [`docs/conventions/label-contract.md`](docs/conventions/label-contract.md) for the full schema.

## Repo layout

```
rules/metrics/<category>/<stack>.yml   # source of truth (plain Prometheus groups)
rules/logs/<category>/<name>.yml       # log-based rules (reserved; empty for now)
tests/<category>/<stack>_test.yaml     # promtool test rules unit tests
runbooks/<category>/<stack>.md         # human runbook for that tech stack
runbooks/<category>/<stack>.yaml       # structured runbook (machine-readable RCA steps)
dashboards/<category>/<stack>*.json    # companion Grafana dashboards
docs/                                  # auto-generated catalog + design docs
scripts/                               # lint, test, render, catalog tools
.github/workflows/                     # CI for lint, test, label contract
```

## Contributing

PRs welcome. Every new alert MUST:

1. Use the label contract above
2. Have a `runbook_url` annotation pointing at a markdown file in `runbooks/`
3. Have at least one positive and one negative test case in `tests/<category>/<stack>_test.yaml`
4. Pass `make all` locally before opening the PR

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Why does this exist?

[`samber/awesome-prometheus-alerts`](https://github.com/samber/awesome-prometheus-alerts) is great for inspiration, but its rules are not tested, not labeled to a contract, and have no runbooks. We built this for production environments where you need:

- Rules that **actually parse** on your Prometheus version
- Rules that **actually fire** for the failure modes they claim to cover (verified by unit tests)
- A consistent label schema so your routing in Alertmanager works the same way for every rule
- Runbooks the on-call engineer can open at 3am

See [`docs/compare-vs-awesome.md`](docs/compare-vs-awesome.md) for an honest comparison.

## License

TBD — see issue #1.

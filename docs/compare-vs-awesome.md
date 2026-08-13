# How rtifact-alert-rules compares to awesome-prometheus-alerts

[`samber/awesome-prometheus-alerts`](https://github.com/samber/awesome-prometheus-alerts) is the most-cited collection of Prometheus rules in the wild and has 950+ rules across 90+ services. We respect it and we draw inspiration from it.

We built `rtifact-alert-rules` because we needed something different.

## Differences

| Dimension | `awesome-prometheus-alerts` | `rtifact-alert-rules` |
|---|---|---|
| **Distribution** | Markdown copy-paste; published rules YAML | Versioned YAML, Helm chart, OCI artifact (planned) |
| **CI testing** | None — rules are not executed | `promtool check rules` and `promtool test rules` on every PR |
| **Label contract** | None — every author chooses their own | Strict, machine-validated (`scripts/validate_labels.py`) |
| **Runbooks** | Mostly empty `runbook_url` annotations | Every `tech_stack` has a runbook; CI validates the file exists |
| **Engine** | Prometheus-only PromQL | Plain Prometheus groups (works with vmalert, Mimir, Thanos Ruler, Cortex) |
| **Coverage breadth** | 90+ services | ~25 services, narrower but deeper |
| **Coverage depth** | Often 1 file per service | One file per service, but with documented severity tiers and tested edge cases |
| **Stale-rule cleanup** | Community-driven, somewhat ad-hoc | We remove rules using deprecated metric names; CI catches them |
| **License** | MIT | TBD (likely Apache-2.0) |

## When to use `awesome-prometheus-alerts`

- You need to bootstrap monitoring for an obscure technology not in our coverage
- You want to browse a comprehensive catalog of "what could you alert on for X"
- Your team prefers copy-paste over Git submodules / Helm

## When to use `rtifact-alert-rules`

- You want rules that **actually parse** on the version of Prometheus you run
- You want rules that **actually fire** for the failure modes they claim (we have unit tests)
- You want a consistent label schema for Alertmanager routing
- You want runbooks the on-call can open
- You're using **VictoriaMetrics + vmalert** (we test against vmalert in CI; planned)

## Honest gaps in `rtifact-alert-rules`

- We cover ~25 stacks; awesome covers 90+
- No AI/ML stack rules yet (planned for v0.2)
- No SLO burn-rate rules yet (planned)
- Dashboard JSON covers only part of the catalog (see `dashboards/`); most stacks are rules-only

## We learn from each other

If we find a bug or stale metric name in our rules that's also in awesome-prometheus-alerts, we'll open an upstream PR there too.

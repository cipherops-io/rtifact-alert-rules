# Runbook: Prometheus

## PrometheusDown

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus
curl -s http://$PROM:9090/-/healthy
curl -s http://$PROM:9090/-/ready
```

## PrometheusTargetDown

A scrape target is down for >10min. Check the target itself and its `ServiceMonitor`/`PodMonitor`/scrape config.

```promql
up == 0
```

```bash
# Inspect the target page in the UI:
http://$PROM:9090/targets
```

## PrometheusScrapeLimitsExceeded

Targets are exceeding `body_size_limit` or `sample_limit`. Either raise the limits in the scrape config or tell the target to expose fewer metrics.

## PrometheusRuleEvaluationSlow

A rule group takes longer to evaluate than its `interval`. Inspect:

```bash
curl -s http://$PROM:9090/api/v1/rules | jq '.data.groups[] | {name: .name, lastEvalDur: .lastEvaluationDuration}'
```

Optimize the slow expression, increase the interval, or split the group.

## PrometheusWALCorruption

P1. Restart Prometheus to attempt repair. Data loss is possible.

## PrometheusTSDBCompactionFailed

Disk-related issue. Check disk space and IOPS.

## PrometheusHighCardinality

>2M active series. Find the culprit:

```bash
curl -s "http://$PROM:9090/api/v1/status/tsdb" | jq '.data.seriesCountByMetricName' | head -30
```

Drop high-cardinality labels via `metric_relabel_configs` or fix the source.

## PrometheusMissedScrapes

Scrapes dropped due to per-target limits. Same fixes as `PrometheusScrapeLimitsExceeded`.

## PrometheusRemoteWriteErrors / PrometheusRemoteWriteBehind

Remote storage (Mimir / Thanos / VM / Cortex) is failing or slow. Check the remote endpoint.

## References

- [Prometheus operations](https://prometheus.io/docs/practices/instrumentation/)
- [Cardinality troubleshooting](https://www.robustperception.io/cardinality-is-key)

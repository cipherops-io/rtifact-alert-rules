# Runbook: VictoriaMetrics

## VictoriaMetricsDown

P0. Metrics ingestion and querying are down.

```bash
kubectl -n monitoring get pods -l app=victoriametrics
curl -s http://$VM:8428/health
curl -s http://$VM:8428/-/ready
```

For the cluster version, check `vmstorage`, `vminsert`, `vmselect` separately.

## VictoriaMetricsTooManyRows

Insert rate is very high. Verify intent — if a new tenant or service started sending massively more metrics than expected, push back; otherwise scale.

## VictoriaMetricsHighChurnRate

>10% of inserted samples are creating new time series — this is a label cardinality bomb. Find it:

```bash
curl -s "http://$VM:8428/api/v1/status/tsdb" | jq '.data | {seriesCountByMetricName: .seriesCountByMetricName[:10]}'
```

Drop the offending labels at vmagent or with a relabel rule.

## VictoriaMetricsRowsRejectedOnIngestion

Rows being dropped. Look at the `reason` label on the metric:
- `bad_metric_name` → fix the source
- `out_of_order_samples` → check clock skew, retransmit storms
- `too_old_samples` → samples older than `-search.maxStalenessInterval`

## VictoriaMetricsTooHighStorageSpaceUsage

Resize the storage PVC, reduce retention (`-retentionPeriod`), or downsample (Enterprise).

## VictoriaMetricsConcurrentInsertsLimitReached

`-maxConcurrentInserts` exhausted. Either raise the limit or scale `vminsert` (cluster mode).

## VictoriaMetricsTooSlowQueryRate

p99 query latency >5s. Investigate slow queries:

```bash
curl -s "http://$VM:8428/api/v1/status/top_queries?topN=10" | jq .
```

Tune `-search.maxQueryDuration`, `-search.maxConcurrentRequests`.

## References

- [VictoriaMetrics single-server docs](https://docs.victoriametrics.com/single-server-victoriametrics/)
- [VictoriaMetrics cluster docs](https://docs.victoriametrics.com/cluster-victoriametrics/)
- [Cardinality explorer](https://docs.victoriametrics.com/cardinality-explorer/)

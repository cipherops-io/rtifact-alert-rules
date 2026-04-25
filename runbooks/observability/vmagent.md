# Runbook: vmagent

vmagent scrapes Prometheus targets and forwards samples via remote-write. It also has a persistent on-disk queue for buffering when remote storage is unreachable.

## VMAgentDown

```bash
kubectl get pods -l app=vmagent
curl -s http://$VMAGENT:8429/health
```

## VMAgentRemoteWriteErrors / VMAgentRemoteWriteAllErrors

Remote storage is rejecting writes.

```bash
kubectl logs -l app=vmagent --tail=200 | grep -i error
# Check the remote URL is reachable from inside the pod:
kubectl exec -it $POD -- curl -v $REMOTE_WRITE_URL/api/v1/write
```

Common causes: target VictoriaMetrics is full, auth credentials changed, network policy blocks egress.

## VMAgentPersistentQueueGrowing

The queue at `-remoteWrite.tmpDataPath` is growing because the destination cannot keep up. Will eventually run out of disk.

```bash
kubectl exec -it $POD -- du -sh /tmp/vmagent-remotewrite-data
```

Either fix the remote endpoint, scale vmagent, or drop some scrapes.

## VMAgentScrapesSkipped

Targets are exceeding sample limits. Drop noisy metrics with `metric_relabel_configs`:

```yaml
metric_relabel_configs:
  - source_labels: [__name__]
    regex: 'high_cardinality_metric_.*'
    action: drop
```

## VMAgentRemoteWriteRetries

Frequent retries indicate a flaky destination. Investigate destination availability and rate limits.

## VMAgentTargetScrapeFailures

Frequent scrape failures for a job. Inspect the target list:

```bash
curl -s "http://$VMAGENT:8429/targets" | head -100
```

## References

- [vmagent docs](https://docs.victoriametrics.com/vmagent/)
- [Relabeling guide](https://docs.victoriametrics.com/vmagent/#relabeling)

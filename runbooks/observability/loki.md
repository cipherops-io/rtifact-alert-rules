# Runbook: Loki

## LokiDown

```bash
kubectl -n loki get pods
curl -s http://$LOKI:3100/ready
```

For microservices mode (distributor, ingester, querier, etc.), check each component.

## LokiIngestionRateNearLimit / LokiIngestionRateExceeded

A tenant is hitting its `ingestion_rate_mb` limit. Either raise the limit (`limits_config.ingestion_rate_mb`), or push back on the source.

## LokiQueryTimeout

Queries timing out. Common: `LogQL` queries spanning weeks, very high-cardinality streams.

## LokiCompactorFailing

Compaction is failing — index growth unbounded.

```bash
kubectl -n loki logs deploy/loki-compactor --tail=200
```

Common: object storage permissions, network blip.

## LokiRingUnhealthy

The hash ring has unhealthy members. Check the ring page:

```bash
curl -s "http://$LOKI:3100/ring"
# Forget a permanently lost member:
curl -X POST "http://$LOKI:3100/ring?forget=$INSTANCE_ID"
```

## LokiChunkFlushFailing

P1. Logs may be lost. Check object storage availability and credentials.

## LokiHighQueueDepth

Querier capacity is insufficient. Scale `querier` replicas or `query-scheduler.max-outstanding-requests-per-tenant`.

## LokiRulerFailing

Loki-Ruler evaluates LogQL alert rules. If failing, log-based alerts won't fire.

## References

- [Loki operations](https://grafana.com/docs/loki/latest/operations/)
- [Loki troubleshooting](https://grafana.com/docs/loki/latest/operations/troubleshooting/)

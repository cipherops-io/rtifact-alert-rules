# Runbook: Alertmanager

## AlertmanagerDown

P0. Alerts are not being routed. Check pods immediately.

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=alertmanager
curl -s http://$AM:9093/-/healthy
```

## AlertmanagerConfigReloadFailed

Configuration is invalid. Check the secret and recent edits.

```bash
kubectl -n monitoring logs -l app.kubernetes.io/name=alertmanager --tail=200
amtool check-config /etc/alertmanager/config.yml
```

## AlertmanagerNotificationsFailing

Look at the integration label.

- `slack` failure → API token, rate limit, channel removed
- `pagerduty` failure → routing key invalid, service deleted
- `webhook` failure → endpoint down, TLS issue, payload too large

```bash
curl -s "http://$AM:9093/api/v2/status" | jq .
```

## AlertmanagerClusterFailedPeers / AlertmanagerClusterDown

Gossip cluster has issues. Causes: network partition, version skew, mesh port blocked. Verify all replicas can reach each other on the gossip port (default 9094).

## AlertmanagerSilencesGrowing

A lot of silences being created. Often a runbook is silencing alerts as a habit instead of fixing them. Audit:

```bash
amtool silence query --alertmanager.url=http://$AM:9093
```

## References

- [Alertmanager configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [amtool reference](https://github.com/prometheus/alertmanager/tree/main/cmd/amtool)

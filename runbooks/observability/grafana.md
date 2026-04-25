# Runbook: Grafana

## GrafanaDown

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=grafana
curl -s http://$GRAFANA:3000/api/health
```

## GrafanaHighRequestErrorRate

Grafana itself is returning 5xx. Common: database (sqlite/postgres) issue, plugin failure.

```bash
kubectl -n monitoring logs -l app.kubernetes.io/name=grafana --tail=200
```

## GrafanaDatasourceErrors

A datasource is returning errors. Check the datasource backend (Prometheus / Loki / VictoriaMetrics) directly.

## GrafanaSlowRequests

Dashboards are slow. Common: dashboards with hundreds of panels each running expensive queries, datasource is overloaded.

## References

- [Grafana documentation](https://grafana.com/docs/grafana/latest/)
- [Grafana troubleshooting](https://grafana.com/docs/grafana/latest/troubleshooting/)

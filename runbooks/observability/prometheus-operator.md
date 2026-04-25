# Runbook: Prometheus Operator

The operator reconciles `Prometheus`, `Alertmanager`, `ServiceMonitor`, `PodMonitor`, `PrometheusRule`, and related CRDs.

## PrometheusOperatorDown

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus-operator
kubectl -n monitoring logs -l app.kubernetes.io/name=prometheus-operator --tail=200
```

While the operator is down, existing Prometheus pods continue to scrape, but CRD changes are not picked up.

## PrometheusOperatorListErrors / PrometheusOperatorWatchErrors

API access errors. Check RBAC:

```bash
kubectl auth can-i list servicemonitors.monitoring.coreos.com --as=system:serviceaccount:monitoring:prometheus-operator
```

## PrometheusOperatorReconcileErrors

Some CRD reconciliation is failing. Look at the operator logs and the affected `Prometheus` / `Alertmanager` resources for events.

## PrometheusOperatorRejectedResources

A `PrometheusRule` or other CRD failed validation. The operator should have logged the reason.

```bash
kubectl -n monitoring logs deploy/prometheus-operator --tail=500 | grep -i 'reject\|invalid\|error'
```

## References

- [Prometheus Operator docs](https://prometheus-operator.dev/docs/)
- [API reference](https://prometheus-operator.dev/docs/operator/api/)

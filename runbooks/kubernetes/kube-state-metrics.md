# Runbook: kube-state-metrics

`kube-state-metrics` (KSM) is a service that listens to the Kubernetes API server and generates metrics about the state of the objects (deployments, pods, etc.). Most cluster-level alerts depend on its metrics.

## KubeStateMetricsDown

KSM is unreachable for 10+ minutes. While KSM is down, alerts that depend on `kube_*` metrics (which is most of `rules/kubernetes/`) will not fire.

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=kube-state-metrics
kubectl -n monitoring describe pod -l app.kubernetes.io/name=kube-state-metrics
kubectl -n monitoring logs -l app.kubernetes.io/name=kube-state-metrics --tail=200
```

Common causes: RBAC permissions revoked, OOM kill, image pull issue.

## KubeStateMetricsListErrors / KubeStateMetricsWatchErrors

KSM is failing list/watch operations against the API server. Causes:
- API server overload (cross-check API server alerts)
- RBAC permissions changed
- A specific CRD's lister is broken

## KubeStateMetricsShardingMismatch / KubeStateMetricsShardsMissing

If you've enabled sharding (`--total-shards`, `--shard`), the shards disagree on the count or one is missing. Verify the StatefulSet replicas and the env-var configuration of each shard.

## References

- [kube-state-metrics docs](https://github.com/kubernetes/kube-state-metrics)

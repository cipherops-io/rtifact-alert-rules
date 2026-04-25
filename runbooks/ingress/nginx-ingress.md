# Runbook: nginx-ingress

The [Kubernetes ingress-nginx controller](https://github.com/kubernetes/ingress-nginx).

## NginxIngressDown

P0. All HTTP/HTTPS ingress is offline.

```bash
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx describe pod $POD
kubectl -n ingress-nginx logs $POD --tail=200
```

## NginxIngressHigh5xxRate

Ingress is returning 5xx. Either:
- The upstream backend is failing (most common — check the service's own health)
- nginx-ingress itself is overloaded (check CPU and connections)

```bash
# Find which backend:
kubectl -n ingress-nginx logs $POD --tail=1000 | grep ' 5[0-9][0-9] ' | awk '{print $7, $9}' | sort | uniq -c | sort -rn | head
```

## NginxIngressHighLatency

p99 request latency >2s. Often the backend is slow, not the ingress itself.

## NginxIngressUpstreamErrors

Specific service is returning 5xx. Investigate that service's health.

## NginxIngressCertificateExpiringSoon

A TLS cert expires within 14 days.

If using cert-manager:

```bash
kubectl get certificate -A
kubectl describe certificate $NAME -n $NAMESPACE
```

If using static certs, rotate them in the Secret referenced by the Ingress.

## NginxIngressConfigReloadFailed

Last config reload failed — running on stale config. New ingresses won't take effect.

```bash
kubectl -n ingress-nginx logs $POD --tail=500 | grep -i 'reload\|invalid\|error'
```

Common: an Ingress with a malformed annotation. Inspect recent changes.

## NginxIngressHighConnections

>5000 active connections. Investigate traffic sources, raise `worker-connections`, or scale ingress replicas.

## References

- [ingress-nginx user guide](https://kubernetes.github.io/ingress-nginx/user-guide/)
- [Troubleshooting](https://kubernetes.github.io/ingress-nginx/troubleshooting/)

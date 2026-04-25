# Runbook: CoreDNS

CoreDNS is the cluster DNS server. Its outage breaks service discovery for every pod that uses cluster DNS.

## CoreDNSDown

Cluster DNS is unavailable. P0 incident.

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system describe pod -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=200

# Test DNS from a debug pod:
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

## CoreDNSPanicCount

CoreDNS is panicking. Look at logs and consider rolling back to the previous version.

```bash
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=500 | grep -i panic
kubectl -n kube-system rollout history deployment/coredns
kubectl -n kube-system rollout undo deployment/coredns
```

## CoreDNSLatencyHigh

p99 DNS resolution latency > 500ms. Causes:
- Upstream resolver is slow
- CoreDNS pods are CPU-throttled
- A buggy plugin (often `loop` plugin detecting recursion)

```bash
kubectl -n kube-system top pods -l k8s-app=kube-dns
kubectl -n kube-system get configmap coredns -o yaml
```

## CoreDNSErrorsHigh

CoreDNS is returning SERVFAIL/REFUSED. Often points at:
- A misconfigured Corefile
- An unreachable upstream DNS
- Records that don't exist (caller bug)

## CoreDNSForwardErrorsHigh

The upstream DNS (resolv.conf, often the node's resolver) is failing. Check the node-level DNS configuration.

```bash
kubectl -n kube-system get cm coredns -o yaml | grep -A 5 forward
# On a node:
cat /etc/resolv.conf
nslookup google.com
```

## CoreDNSCacheHitsLow

Low cache hit ratio. Often caused by short TTLs from the upstream or very high cardinality of unique queries. Consider:
- Increase the `cache` plugin TTL in the Corefile
- Investigate whether some workload is generating unbounded unique DNS lookups

## References

- [CoreDNS troubleshooting](https://coredns.io/manual/troubleshooting/)
- [DNS for services and pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

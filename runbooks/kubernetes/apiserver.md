# Runbook: Kubernetes API server

The Kubernetes API server is the front door to the cluster. Its outage means kubectl, controllers, and the scheduler all stop functioning.

## KubeAPIServerDown

No API server is reachable. This is a P0 incident.

```bash
# From outside the cluster (using a kubeconfig pointing to the LB):
curl -k https://$APISERVER:6443/healthz

# On a control-plane node:
sudo systemctl status kube-apiserver       # if running as systemd
crictl ps | grep apiserver                 # if running as static pod
crictl logs --tail 200 $(crictl ps -q --name=kube-apiserver)
journalctl -u kubelet -n 200               # kubelet manages static pods
```

Common causes: etcd is down, certificate expired, OOM kill of apiserver pod, control-plane LB misconfigured.

## KubeAPIServerErrors

5xx error rate is above 5%. Common causes:
- etcd is slow or failing (correlate with `EtcdHigh*` alerts)
- An admission webhook is timing out (see `KubeAPIServerAdmissionLatency`)
- A specific resource type has a broken CRD
- Authentication / authorization webhook is failing

```bash
kubectl get --raw /metrics | grep apiserver_request_total | head -50
kubectl get --raw /healthz?verbose
```

## KubeAPIServerLatencyHigh / KubeAPIServerLatencyVeryHigh

p99 latency above 1s (warning) or 4s (critical).

Investigate:
1. Etcd performance (`EtcdHighCommitDurations`, `EtcdHighFsyncDurations`)
2. Admission webhook latency (`KubeAPIServerAdmissionLatency`)
3. CPU / memory pressure on the apiserver pod
4. A noisy controller doing too many list/watch operations

## KubeAPIClientCertExpiring

Some kubelet or controller-manager client certificate expires within 7 days. Rotation is automatic in modern Kubernetes (`--rotate-certificates=true` on kubelet), but verify that CSRs are being approved.

```bash
kubectl get csr
kubectl certificate approve $CSR_NAME
```

For static / hand-issued certs, use kubeadm:

```bash
kubeadm certs check-expiration
kubeadm certs renew all
```

## KubeAPIServerAdmissionLatency

A webhook is slow. Find which:

```bash
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations
kubectl describe validatingwebhookconfiguration $NAME
```

To temporarily disable a misbehaving webhook (CAREFUL — security impact):

```bash
kubectl patch validatingwebhookconfiguration $NAME --type='json' \
  -p='[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]'
```

## KubeAPIServerEtcdRequestErrors

The apiserver is failing requests to etcd. Cross-check the etcd alerts (`EtcdDown`, `EtcdNoLeader`, `EtcdBackendQuotaExhausted`).

## References

- [Kubernetes API server troubleshooting](https://kubernetes.io/docs/tasks/debug/debug-cluster/)
- [SIG-API-machinery troubleshooting](https://github.com/kubernetes/community/tree/master/sig-api-machinery)

# Runbook: etcd

etcd is the source of truth for Kubernetes cluster state. Its health is the most critical thing to monitor in the control plane.

## EtcdDown / EtcdNoLeader

P0 incident. ALL Kubernetes API operations are blocked.

```bash
# From a control-plane node with etcdctl installed:
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table

ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list
```

If quorum is lost (more than half the members are down), restoring requires a backup. NEVER try to "fix" by removing members blindly — you can lose the cluster permanently.

## EtcdLeaderChangesHigh

Leader is being re-elected too often. Causes: network instability, slow disk, CPU starvation. Cross-check `EtcdHighFsyncDurations` and `EtcdHighNetworkPeerRTT`.

## EtcdHighCommitDurations / EtcdHighFsyncDurations

etcd is sensitive to disk I/O. p99 fsync above 25ms means the disk is too slow for etcd. Use SSD/NVMe. Avoid network-attached storage.

```bash
# Test disk speed from the node:
sudo fio --name=fsync_test --rw=write --fdatasync=1 --bs=4k --numjobs=1 --size=22m --runtime=60s
```

## EtcdDBSizeHigh / EtcdDBSizeCritical / EtcdBackendQuotaExhausted

The etcd database has a hard 8GB default limit. Approaching it will eventually reject all writes.

Compact and defrag to reclaim space:

```bash
# Get current revision:
REV=$(etcdctl endpoint status --write-out="json" | jq -r '.[0].Status.header.revision')

# Compact:
etcdctl compact $REV

# Defragment each member (one at a time!):
etcdctl defrag --endpoints=https://etcd-0.etcd:2379
etcdctl defrag --endpoints=https://etcd-1.etcd:2379
etcdctl defrag --endpoints=https://etcd-2.etcd:2379

# If quota was exhausted, clear the alarm:
etcdctl alarm disarm
```

## EtcdHighNetworkPeerRTT

Network between control-plane nodes is slow. p99 above 150ms is a problem. Investigate inter-node networking.

## EtcdHighGRPCErrors

etcd is returning gRPC errors. Often correlates with `EtcdNoLeader` or `EtcdBackendQuotaExhausted`.

## EtcdDefragNeeded

etcd database is heavily fragmented (>50% wasted). Run defragmentation as shown above. Schedule regular defrag (hourly or daily) via cron or a Kubernetes Job.

## EtcdHighApplyDurations

The cluster is overloaded. The fix is usually to:
- Reduce write rate (rate-limit some controllers)
- Increase etcd resources
- Move secrets / large objects out of etcd

## EtcdCertificateExpiringSoon

Renew client certs before they expire:

```bash
# kubeadm clusters:
kubeadm certs check-expiration
kubeadm certs renew etcd-server etcd-peer etcd-healthcheck-client apiserver-etcd-client
# Restart static pods after renewing
```

## References

- [etcd operations guide](https://etcd.io/docs/v3.5/op-guide/)
- [etcd performance documentation](https://etcd.io/docs/v3.5/op-guide/performance/)
- [etcd disaster recovery](https://etcd.io/docs/v3.5/op-guide/recovery/)

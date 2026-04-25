# Runbook: node-exporter (host-level metrics)

These alerts come from the [Prometheus node_exporter](https://github.com/prometheus/node_exporter) running on each node, exposing OS-level metrics.

## NodeExporterDown

A single node-exporter is down. Cluster monitoring of that one node is incomplete. Not a P0, but should be investigated within a few hours.

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus-node-exporter -o wide | grep $NODE
kubectl -n monitoring logs -l app.kubernetes.io/name=prometheus-node-exporter --field-selector spec.nodeName=$NODE
```

## NodeFilesystemAlmostOutOfSpace / NodeFilesystemOutOfSpace

A node filesystem has <10% (warning) or <3% (critical) free space.

```bash
ssh $NODE 'df -h | sort -k 5 -n -r | head -20'
ssh $NODE 'sudo du -h --max-depth=1 /var | sort -h | tail -20'
ssh $NODE 'sudo du -h --max-depth=1 /var/log | sort -h | tail -20'
```

Common cleanup:
- Container runtime image cache: `sudo crictl rmi --prune`
- journald logs: `sudo journalctl --vacuum-size=500M`
- Old kernel packages (Debian/Ubuntu): `sudo apt autoremove --purge`

## NodeFilesystemAlmostOutOfFiles

Inodes are running low. Often caused by huge numbers of small files (e.g. cache directories with millions of files).

```bash
ssh $NODE 'df -i'
ssh $NODE 'sudo find / -xdev -type f 2>/dev/null | awk "{print \$1}" | xargs -I{} dirname {} | sort | uniq -c | sort -nr | head'
```

## NodeMemoryHighUsage / NodeCPUHighUsage / NodeLoad15High

The node is under pressure. Check what's running:

```bash
kubectl top nodes
kubectl top pod --all-namespaces --sort-by=memory | head -20
ssh $NODE 'top -b -n1 -o %MEM | head -20'
```

If a particular pod is the culprit, set memory/CPU limits on it. If the node is consistently overloaded, scale out the cluster.

## NodeNetworkReceiveErrs / NodeNetworkTransmitErrs

Packet errors on a network interface. Often a sign of a bad NIC, cable, or driver. On cloud providers, often correlates with noisy-neighbor situations.

```bash
ssh $NODE 'ethtool -S $IFACE | grep -i err'
ssh $NODE 'dmesg | grep -i "$IFACE\|ethernet\|nic" | tail -20'
```

## NodeClockSkew

The node's clock is drifting. Check NTP:

```bash
ssh $NODE 'chronyc tracking || timedatectl status'
```

Clock skew impacts certificate validation, leader election (etcd), and distributed traces.

## NodeFileDescriptorUsage

The node is using >80% of its file descriptor limit. Check what's holding so many FDs:

```bash
ssh $NODE 'sudo lsof | awk "{print \$2}" | sort | uniq -c | sort -rn | head'
```

The `nofile` ulimit can be raised in `/etc/security/limits.conf` or systemd unit overrides.

## References

- [Node exporter README](https://github.com/prometheus/node_exporter)
- [Linux performance troubleshooting cheatsheet](http://www.brendangregg.com/linuxperf.html)

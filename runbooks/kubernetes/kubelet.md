# Runbook: kubelet

kubelet runs on every node and is responsible for managing pods on that node.

## KubeletDown

No kubelet metrics endpoint is reachable cluster-wide. This is unusual; more often a single node's kubelet is down (which would show as `KubeletNodeNotReady`).

```bash
# Verify Prometheus / vmagent service-monitor is matching the kubelet endpoint
kubectl get nodes -o wide
kubectl get --raw /api/v1/nodes/$NODE/proxy/healthz
```

## KubeletNodeNotReady

A node has been NotReady for 10+ minutes. Common causes:
- kubelet crashed
- Container runtime (containerd / docker) is unhealthy
- Network partition
- Disk is full (see `KubeletDiskPressure`)

```bash
kubectl describe node $NODE
# On the node itself:
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 200
sudo systemctl status containerd  # or docker
```

## KubeletMemoryPressure / KubeletDiskPressure / KubeletPIDPressure

The node is approaching a hard eviction threshold and pods will start being evicted.

For MemoryPressure:
```bash
kubectl top node $NODE
ssh $NODE 'free -h && top -b -n1 -o %MEM | head -30'
```

For DiskPressure:
```bash
ssh $NODE 'df -h && du -sh /var/lib/containerd /var/log /var/lib/docker 2>/dev/null'
# Common cleanup:
ssh $NODE 'sudo crictl rmi --prune'   # remove unused images
ssh $NODE 'sudo journalctl --vacuum-size=500M'
```

For PIDPressure:
```bash
ssh $NODE 'ps -ef | wc -l && cat /proc/sys/kernel/pid_max'
# Check for fork bombs or runaway containers
```

## KubeletNetworkUnavailable

The CNI plugin reports the node has no network. Check the CNI pods (Cilium / Calico / Flannel / etc.) on that node.

```bash
kubectl -n kube-system get pods -o wide --field-selector spec.nodeName=$NODE
```

## KubeletPodLifecycleEventGeneratorLatencyHigh

PLEG p99 relist latency > 10s. PLEG is responsible for pod lifecycle events; if it's slow the node will be marked NotReady. Common causes: too many pods on the node, slow disk I/O, or slow container runtime.

## KubeletPodStartupLatencyHigh

Pods take a long time to start. Common causes:
- Slow image pulls (large images, slow registry)
- Init containers doing slow work
- Sidecar / Service Mesh injection latency
- Long readiness probe initialDelaySeconds

## KubeletTooManyPods

Node is at >95% of its `pods` capacity (default 110 per node). Either scale out the cluster, or increase `--max-pods` per kubelet.

## KubeletClientCertExpiring

Should auto-rotate. If not:

```bash
kubectl get csr | grep $NODE
kubectl certificate approve $CSR_NAME
```

## References

- [kubelet documentation](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/)
- [Node troubleshooting](https://kubernetes.io/docs/tasks/debug/debug-cluster/)

# Runbook: Kubernetes workloads

Covers pod, deployment, statefulset, daemonset, job, cronjob, HPA, and PV/PVC alerts.

## KubePodCrashLooping

A container is restarting repeatedly. Common causes: bad config, missing env var, missing dependency, OOM, application bug.

```bash
kubectl describe pod -n $NAMESPACE $POD
kubectl logs -n $NAMESPACE $POD --previous
kubectl logs -n $NAMESPACE $POD -c $CONTAINER --previous
```

Check exit code in `kubectl describe` events. Exit 137 = OOMKilled. Exit 1 = application error. Exit 2 = misuse of shell builtin.

## KubePodOOMKilled

Container exceeded its memory limit. Either:
- The limit is too low → increase it
- The application has a memory leak → investigate

```bash
kubectl top pod -n $NAMESPACE $POD --containers
kubectl describe pod -n $NAMESPACE $POD | grep -A 3 'Limits:\|Requests:'
```

## KubeContainerWaiting

Container stuck in non-running state for >1h. Look at `reason` label.
- `ImagePullBackOff` / `ErrImagePull` → see KubePodImagePullBackOff
- `CreateContainerConfigError` → check ConfigMap/Secret refs
- `CrashLoopBackOff` → see KubePodCrashLooping

## KubePodNotReady

Pod is Running but failing readiness probe. Check the probe configuration and the application's `/ready` (or equivalent) endpoint.

```bash
kubectl describe pod -n $NAMESPACE $POD | grep -A 5 'Readiness:'
kubectl exec -n $NAMESPACE $POD -- curl -s localhost:$PORT/ready
```

## KubeDeploymentReplicasMismatch

Deployment has fewer available replicas than desired. Likely cause: pods are crashing, being evicted, or stuck pending.

```bash
kubectl get deployment -n $NAMESPACE $DEPLOYMENT
kubectl get pods -n $NAMESPACE -l app=$LABEL
kubectl describe deployment -n $NAMESPACE $DEPLOYMENT
```

## KubeDeploymentRolloutStuck

Rollout has not progressed for 15 minutes. Common: failing readiness, resource constraints, image pull issue.

```bash
kubectl rollout status -n $NAMESPACE deployment/$DEPLOYMENT
kubectl rollout history -n $NAMESPACE deployment/$DEPLOYMENT
# To roll back:
kubectl rollout undo -n $NAMESPACE deployment/$DEPLOYMENT
```

## KubeStatefulSetReplicasMismatch

StatefulSets fail in pod-order. Check the lowest-numbered NotReady pod first.

```bash
kubectl get pods -n $NAMESPACE -l app=$LABEL --sort-by=.metadata.name
```

## KubeDaemonSetNotScheduled

DaemonSet not running on every node. Causes: tolerations missing for tainted nodes, node selector mismatch, pod resources too high for node.

```bash
kubectl describe ds -n $NAMESPACE $DAEMONSET
kubectl get nodes --show-labels
```

## KubePodImagePullBackOff

Cannot pull container image. Check image name, tag exists in registry, and registry credentials (`imagePullSecrets`).

```bash
kubectl describe pod -n $NAMESPACE $POD | grep -A 3 'Failed'
kubectl get secret -n $NAMESPACE  # verify imagePullSecrets exist
# Test pull manually on the node:
ctr -n k8s.io images pull $IMAGE   # for containerd
docker pull $IMAGE                 # for docker
```

## KubeJobFailed

Batch job has failed. Check the failed pod logs.

```bash
kubectl describe job -n $NAMESPACE $JOB
kubectl logs -n $NAMESPACE -l job-name=$JOB --previous
```

## KubeCronJobSuspended

A CronJob is suspended (`spec.suspend: true`). Check whether this is intentional. Resume:

```bash
kubectl patch cronjob -n $NAMESPACE $CRONJOB -p '{"spec":{"suspend":false}}'
```

## KubePodEvicted

The node evicted the pod (typically due to memory/disk pressure). Check the node's condition (`KubeletMemoryPressure`, `KubeletDiskPressure`).

```bash
kubectl describe pod -n $NAMESPACE $POD | grep -A 5 Status
kubectl describe node $NODE
```

## KubePodPendingTooLong

Pod cannot be scheduled. Most common reason: insufficient resources or node selector / affinity mismatch.

```bash
kubectl describe pod -n $NAMESPACE $POD | grep -A 10 Events
kubectl get nodes -o wide
kubectl describe nodes | grep -A 5 'Allocated resources'
```

## KubePersistentVolumeError

A PV is in `Failed`, `Lost`, or `Pending` phase. Check the underlying storage backend and CSI driver logs.

```bash
kubectl get pv $PV -o yaml
kubectl describe pv $PV
kubectl logs -n kube-system -l app=csi-driver  # adjust label per CSI driver
```

## KubePVCFillingUp / KubePVCCriticalFull

A PVC has less than 15% (warning) / 5% (critical) free space.

Options:
1. Resize the PVC if the StorageClass allows online expansion
2. Clean up unused data inside the volume
3. Provision a new larger volume and migrate

```bash
kubectl get pvc -n $NAMESPACE $PVC
# Find the pod using the PVC:
kubectl get pods -n $NAMESPACE -o json | jq -r '.items[] | select(.spec.volumes[]?.persistentVolumeClaim?.claimName=="'$PVC'") | .metadata.name'
# Exec in to inspect usage:
kubectl exec -n $NAMESPACE $POD -- df -h
```

## KubeHpaMaxedOut

HPA is at its `maxReplicas`. Either increase the max, or investigate why the metric (CPU / memory / custom) is so high.

```bash
kubectl get hpa -n $NAMESPACE $HPA
kubectl describe hpa -n $NAMESPACE $HPA
# Patch maxReplicas if needed:
kubectl patch hpa -n $NAMESPACE $HPA -p '{"spec":{"maxReplicas":NEW_VALUE}}'
```

## References

- [Kubernetes troubleshooting clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/)
- [Debug pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [HPA documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

# Runbook: ClickHouse

## ClickHouseDown

```bash
clickhouse-client --host $HOST --query 'SELECT 1'
```

## ClickHouseHighMemoryUsage

```sql
SELECT * FROM system.metrics WHERE metric LIKE '%Memory%';
SELECT formatReadableSize(memory_usage) FROM system.processes ORDER BY memory_usage DESC LIMIT 10;
```

Tune `max_memory_usage`, `max_bytes_before_external_group_by`.

## ClickHouseReplicationQueueHigh

Replication queue is backed up:

```sql
SELECT * FROM system.replication_queue WHERE num_tries > 1 ORDER BY create_time LIMIT 20;
SELECT database, table, queue_size, inserts_in_queue, merges_in_queue
FROM system.replicas WHERE queue_size > 50;
```

## ClickHouseZooKeeperSessionLost / ClickHouseKeeperConnectionLost

ZooKeeper / Keeper is unreachable — distributed operations stop. Check Keeper/ZK pods directly.

## ClickHousePartsExplosion

Too many parts → merges can't keep up. Causes: tiny inserts (use bigger batches), too few cores for merging.

```sql
SELECT database, table, count() FROM system.parts WHERE active GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 20;
-- Force merge:
OPTIMIZE TABLE db.tbl FINAL;
```

## ClickHouseLongRunningMutation

```sql
SELECT * FROM system.mutations WHERE NOT is_done ORDER BY create_time;
-- Kill a mutation:
KILL MUTATION WHERE mutation_id = '...';
```

## ClickHouseQueryThreadsHigh / ClickHouseInsertDelayHigh

Cluster is overloaded. Tune `max_concurrent_queries`, scale horizontally, or rate-limit clients.

## ClickHouseDiskUsageHigh

Resize the PVC, enable tiered storage, or add `TTL ... TO DISK 'cold'` policies.

## ClickHouseMergesDelayed / ClickHouseBackgroundPoolOverloaded

Increase `background_pool_size` and `background_merges_mutations_concurrency_ratio`.

## ClickHouseDetachedPartsHigh

Investigate `system.detached_parts` and either reattach or drop them.

## ClickHouseDistributedSendFailed

Remote shards are unreachable or rejecting writes. Check inter-shard connectivity.

---

# clickhouse-operator (control plane)

The alerts below come from the Altinity `clickhouse-operator` metrics endpoint, not from
ClickHouse itself. They tell you whether the operator can converge your
`ClickHouseInstallation` (CHI) objects onto the cluster. **None of them observe query
latency, replication lag, parts, merges, or disk** — if a ClickHouse server is unhealthy
but the operator has nothing to reconcile, every one of these stays silent.

Orientation commands, useful for all of them:

```bash
# Which CHIs exist and what state does the operator think they are in?
kubectl get chi -A
kubectl describe chi <chi> -n <namespace>

# The operator's own logs are the only place the reconcile error text appears —
# the metrics are counters and carry no reason label.
kubectl -n <operator-namespace> logs deploy/clickhouse-operator -c clickhouse-operator --tail=200
kubectl -n <operator-namespace> logs deploy/clickhouse-operator -c clickhouse-operator | grep -iE "error|abort|fail"

# What the operator is acting on
kubectl get pods,sts,pvc -n <namespace> -l clickhouse.altinity.com/chi=<chi>
```

## ClickHouseOperatorMetricsAbsent

The operator stopped exporting `clickhouse_operator_chi`. Until this clears, every other
alert in this section is blind — reconcile failures will not be detected.

```bash
kubectl -n <operator-namespace> get deploy clickhouse-operator
kubectl -n <operator-namespace> get pods -l app=clickhouse-operator
kubectl -n <operator-namespace> describe pod -l app=clickhouse-operator | tail -30

# Is it the operator or the scrape? Hit the metrics port directly.
kubectl -n <operator-namespace> port-forward deploy/clickhouse-operator 8888:8888
curl -s localhost:8888/metrics | grep clickhouse_operator_chi

# If the pod is healthy, the ServiceMonitor/scrape config is the suspect.
kubectl -n <operator-namespace> get servicemonitor -l app=clickhouse-operator -o yaml
```

If the operator is genuinely down: CHI edits will not be applied, but **already-running
ClickHouse pods keep serving traffic**. This is a control-plane outage, not a data outage.

## ClickHouseOperatorHostReconcileErrors

The operator tried to reconcile a ClickHouse host and failed. The cluster keeps running on
its old configuration, so this is usually silent from the client's perspective — the danger
is believing a CHI change was applied when it was not.

```bash
# The error reason is only in the logs.
kubectl -n <operator-namespace> logs deploy/clickhouse-operator | grep -iE "reconcile.*(error|fail)" | tail -40

# Compare desired vs actual for the host that failed.
kubectl get chi <chi> -n <namespace> -o yaml | head -60
kubectl -n <namespace> get sts -l clickhouse.altinity.com/chi=<chi>
kubectl -n <namespace> describe pod <chi>-<cluster>-<shard>-<replica>-0 | tail -40
```

Common causes: the pod cannot become ready (probe failing, image pull, resource limits),
the PVC cannot be resized or bound, an invalid setting in the CHI `spec.configuration`, or
the operator lacking RBAC for a resource it needs to update.

## ClickHouseOperatorHostReconcileErrorsSustained

Same failure, now retrying and not making progress. Treat this as a stuck rollout: the
cluster is between two configurations and may be running mixed versions or mixed settings
across hosts.

```bash
# How far did the rollout get? Compare image/config across hosts.
kubectl -n <namespace> get pods -l clickhouse.altinity.com/chi=<chi> \
  -o custom-columns='POD:.metadata.name,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready'

# Events often name the blocker directly.
kubectl -n <namespace> get events --sort-by=.lastTimestamp | tail -40
```

Decide explicitly: roll forward (fix the blocker) or roll back the CHI to the last known
good spec. Leaving a cluster half-converged is the worst of the three options.

## ClickHouseOperatorCHIReconcileAborted

A CHI-level reconcile was abandoned before finishing, so the live cluster does not match the
CRD. Frequent aborts usually mean the CHI is being edited faster than it can converge — for
example a GitOps controller re-applying on every sync.

```bash
kubectl -n <operator-namespace> logs deploy/clickhouse-operator | grep -i abort | tail -20

# Is something rewriting the CHI repeatedly?
kubectl get chi <chi> -n <namespace> -o jsonpath='{.metadata.generation} {.metadata.resourceVersion}{"\n"}'
kubectl get chi <chi> -n <namespace> -o yaml | grep -A5 "managedFields" | head -20
```

## ClickHouseOperatorCHIReconcileStuck

A reconcile started, and over an hour later has neither completed nor aborted. The operator
is blocked waiting on something that will not happen on its own.

```promql
# Confirm the imbalance and see how long it has been open.
sum by (namespace, chi) (increase(clickhouse_operator_chi_reconciles_started[1h]))
sum by (namespace, chi) (increase(clickhouse_operator_chi_reconciles_completed[1h]))
sum by (namespace, chi) (increase(clickhouse_operator_chi_reconciles_aborted[1h]))
```

```bash
# Almost always a pod that will never become ready.
kubectl -n <namespace> get pods -l clickhouse.altinity.com/chi=<chi>
kubectl -n <namespace> get pvc -l clickhouse.altinity.com/chi=<chi>
kubectl -n <namespace> describe pod <pending-or-notready-pod> | tail -40
```

Look for: `Pending` on scheduling or PVC binding, a readiness probe that never passes, or a
host waiting on a ClickHouse startup that is replaying a large replication queue.

## ClickHouseOperatorHostReconcileSlow

Host reconciles are averaging over 10 minutes. Not an outage, but it means a rolling
upgrade will run far past its maintenance window, and it is usually an early warning for
`ClickHouseOperatorCHIReconcileStuck`.

```promql
# Average seconds per host reconcile.
increase(clickhouse_operator_host_reconciles_timings_sum[1h])
/ increase(clickhouse_operator_host_reconciles_timings_count[1h])

# Distribution, if you have enough samples for the buckets to be meaningful.
histogram_quantile(0.95,
  sum by (le, namespace, chi) (rate(clickhouse_operator_host_reconciles_timings_bucket[6h])))
```

Usual causes: slow ClickHouse startup (large part count to load, replication catch-up on
restart), slow image pulls, or pods waiting on node scale-up.

## ClickHouseOperatorHostRestartsHigh

More host restarts than a planned rolling upgrade would need. Every restart drops in-flight
queries and forces the replica to resync, so this is client-visible.

```bash
kubectl -n <namespace> get pods -l clickhouse.altinity.com/chi=<chi> \
  -o custom-columns='POD:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,STATE:.status.containerStatuses[0].state'

# Why did the container die? OOMKilled is the most common answer.
kubectl -n <namespace> describe pod <pod> | grep -A5 "Last State"
kubectl -n <namespace> logs <pod> --previous --tail=100
```

If `Last State` shows `OOMKilled`, raise the container memory limit and cap ClickHouse's own
`max_memory_usage` / `max_server_memory_usage` below it — otherwise the server will keep
being killed by the kernel rather than rejecting the query.

## ClickHouseOperatorPodsDisappearing

More pod deletes than adds over 30 minutes: the cluster is losing hosts rather than cycling
them, which reduces replica count and query capacity.

```bash
kubectl -n <namespace> get pods -l clickhouse.altinity.com/chi=<chi> -o wide
kubectl -n <namespace> get events --sort-by=.lastTimestamp | grep -iE "evict|preempt|kill|failedscheduling" | tail -30

# Are the nodes still there?
kubectl get nodes
kubectl -n <namespace> describe pod <missing-pod> 2>/dev/null || echo "pod is gone entirely"
```

Check for node drains/scale-down, eviction by a higher-priority workload, PodDisruptionBudget
misconfiguration allowing too many simultaneous evictions, or a PVC whose node affinity no
longer matches any available node.

## References

- [ClickHouse system tables](https://clickhouse.com/docs/en/operations/system-tables/)
- [ClickHouse troubleshooting](https://clickhouse.com/docs/en/troubleshooting/)
- [Altinity clickhouse-operator](https://github.com/Altinity/clickhouse-operator)

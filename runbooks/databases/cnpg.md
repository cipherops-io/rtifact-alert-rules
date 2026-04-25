# Runbook: CloudNativePG (CNPG)

CloudNativePG is a Kubernetes operator for PostgreSQL.

## CNPGClusterDown

The CNPG metric exporter is down. Likely the cluster itself is healthy but instrumentation is broken; verify via `kubectl cnpg status`:

```bash
kubectl cnpg status $CLUSTER -n $NAMESPACE
kubectl get pods -n $NAMESPACE -l cnpg.io/cluster=$CLUSTER
```

## CNPGClusterDegraded

Fewer ready instances than desired. A replica is down or being recreated.

```bash
kubectl cnpg status $CLUSTER -n $NAMESPACE
kubectl describe pod -n $NAMESPACE $UNHEALTHY_POD
kubectl logs -n $NAMESPACE $UNHEALTHY_POD -c postgres
```

## CNPGClusterHAWarning

Cluster has only 1 instance. Increase `spec.instances` to at least 3 for HA:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
spec:
  instances: 3   # minimum for HA
```

## CNPGClusterLongRunningTransactionWarning / Critical

A long-running transaction is holding locks and preventing autovacuum. Find and (carefully) cancel:

```sql
SELECT pid, usename, datname, state, age(clock_timestamp(), xact_start) AS tx_age, query
FROM pg_stat_activity
WHERE state != 'idle'
  AND xact_start IS NOT NULL
  AND age(clock_timestamp(), xact_start) > interval '5 minutes'
ORDER BY xact_start;

-- To cancel:
SELECT pg_cancel_backend(<pid>);
-- To force-terminate (WAL replay continues):
SELECT pg_terminate_backend(<pid>);
```

## CNPGClusterReplicationLagWarning / Critical

Replica is falling behind primary. Causes:
- Slow disk on the replica
- Network bottleneck
- Primary write pressure
- Replica is busy serving reads

```bash
kubectl cnpg status $CLUSTER -n $NAMESPACE   # shows replication state
```

```sql
-- on primary:
SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;
```

## CNPGClusterBackupOverdue

Backup hasn't succeeded in >24h. Check `Backup` resources and the backing storage.

```bash
kubectl get backup -n $NAMESPACE
kubectl describe backup -n $NAMESPACE $BACKUP
# For barman/object storage backed setups, check connectivity to the bucket
```

## CNPGClusterHighWALDiskUsage / CNPGClusterDataVolumeNearFull

Disk pressure. Options:
- Resize the PVC if the StorageClass allows
- Check for inactive replication slots (`CNPGClusterDeadReplicationSlot`)
- Trim WAL retention

## CNPGClusterWALArchiveFailing

WAL archive is failing — point-in-time recovery is at risk. Most often: object storage credentials expired or quota exceeded. Check the cluster status and barman/wal-g logs in the postgres container.

## CNPGClusterDeadReplicationSlot

An inactive replication slot is holding WAL → `pg_wal` will grow unboundedly. Drop it:

```sql
SELECT slot_name, active, restart_lsn FROM pg_replication_slots;
SELECT pg_drop_replication_slot('inactive_slot_name');
```

## CNPGClusterHighConnections

Approaching `max_connections`. Add PgBouncer (via `Pooler` CR) or raise `max_connections`:

```yaml
spec:
  postgresql:
    parameters:
      max_connections: "300"
```

## CNPGClusterPrimaryNotReady

P0. Primary pod is not ready, writes are failing. Trigger a switchover/failover:

```bash
kubectl cnpg promote $CLUSTER $NEW_PRIMARY_POD -n $NAMESPACE
```

## CNPGClusterFailoverOccurred

Informational. A switchover or failover happened. Verify the cluster is now healthy and update post-failover monitoring (e.g., new primary pod name in dashboards).

## References

- [CloudNativePG documentation](https://cloudnative-pg.io/documentation/)
- [Troubleshooting](https://cloudnative-pg.io/documentation/current/troubleshooting/)

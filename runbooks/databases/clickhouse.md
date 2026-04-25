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

## References

- [ClickHouse system tables](https://clickhouse.com/docs/en/operations/system-tables/)
- [ClickHouse troubleshooting](https://clickhouse.com/docs/en/troubleshooting/)

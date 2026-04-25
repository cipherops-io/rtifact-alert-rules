# Runbook: Redis

## RedisDown

```bash
redis-cli -h $HOST PING
kubectl get pods -l app=redis
```

## RedisHighMemoryUsage / RedisEvictedKeysHigh

Approaching `maxmemory`. Either:
- Raise `maxmemory`
- Audit large keys: `redis-cli --bigkeys`
- Tune the `maxmemory-policy` (allkeys-lru is the most forgiving)

```bash
redis-cli MEMORY STATS
redis-cli --bigkeys
redis-cli --memkeys
```

## RedisMemoryFragmentationHigh

Redis frees memory back to the allocator but the OS doesn't always reclaim it.

```bash
redis-cli MEMORY PURGE                  # forces jemalloc to release pages
# Schedule a rolling restart during low traffic if fragmentation persists.
```

## RedisKeyspaceHitRatioLow

Cache misses are high → backend pressure. Investigate:
- Is the working set larger than `maxmemory`?
- Are TTLs too aggressive?
- Cache stampede on cold start?

## RedisConnectedClientsHigh / RedisBlockedClientsHigh

Investigate which clients are blocking:

```bash
redis-cli CLIENT LIST | sort -t'=' -k 6 -n -r | head
```

`BLPOP`/`BRPOP`/`XREAD BLOCK` are common sources of blocked clients.

## RedisMasterLinkDown / RedisReplicationOffsetHigh

Replication is broken or lagging.

```bash
redis-cli INFO replication
# Force a resync if needed (CAREFUL — full data transfer):
redis-cli REPLICAOF NO ONE
redis-cli REPLICAOF $MASTER 6379
```

## RedisSlowLogGrowing

```bash
redis-cli SLOWLOG GET 20
redis-cli SLOWLOG RESET
```

Common culprits: `KEYS *` (use `SCAN`), large `HGETALL`, expensive `ZRANGEBYSCORE`.

## RedisRDBSaveError

Background save failed. Likely disk-full. Check `INFO persistence`:

```bash
redis-cli INFO persistence | grep -E 'rdb|aof'
```

## RedisAOFRewriteRunningLong

AOF rewrite running >10min. Disk I/O is too slow, or the AOF is too large.

## RedisClusterNodeDown / RedisClusterSlotsImporting

Cluster topology issue.

```bash
redis-cli CLUSTER NODES
redis-cli CLUSTER INFO
redis-cli --cluster check $HOST:6379
```

## RedisCPUSaturation

Redis is single-threaded for command execution. Investigate:
- Slow commands (`SLOWLOG`)
- Lua scripts running too long
- High pubsub traffic

Consider sharding (Redis Cluster) for horizontal scale.

## References

- [Redis admin documentation](https://redis.io/docs/management/)
- [Redis latency monitoring](https://redis.io/docs/management/optimization/latency/)

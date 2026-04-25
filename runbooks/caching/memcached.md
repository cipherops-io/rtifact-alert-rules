# Runbook: Memcached

## MemcachedDown

```bash
kubectl get pods -l app=memcached
echo stats | nc $HOST 11211 | head -30
```

## MemcachedHighMemoryUsage / MemcachedHighEvictionRate

Memcached evicts least-recently-used items when full. Either:
- Increase memory (`-m`) — requires restart
- Audit which keys are largest
- Apply more aggressive TTLs at the application level

```bash
echo 'stats slabs' | nc $HOST 11211
```

## MemcachedLowHitRatio

Cache is underperforming. Investigate:
- Are TTLs too short?
- Is the working set bigger than capacity?
- Is the cache being warmed correctly on startup?

## MemcachedConnectionsHigh

Approaching `-c` (max_connections, default 1024). Increase or fix application connection management.

## MemcachedCPUSaturation

Memcached can use multiple threads (`-t N`). Increase if CPU is saturated, or scale horizontally.

## MemcachedHighItemExpiry

Items expiring before being read. TTLs may be set too short for usage pattern.

## MemcachedSetFailureHigh

`SET` commands failing. Common: items larger than `-I` (default 1MB), no memory available even after eviction.

## MemcachedRejectedConnections

Memcached temporarily disabled the listener due to connection exhaustion. Tune `-c` or fix client connection leaks.

## MemcachedRestartDetected

Cache was wiped (uptime <60s). Investigate why it crashed (OOM kill?). Cold cache will hammer the backend.

## References

- [Memcached docs](https://memcached.org/about)
- [Memcached stats reference](https://github.com/memcached/memcached/blob/master/doc/protocol.txt)

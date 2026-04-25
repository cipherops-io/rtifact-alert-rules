# Runbook: MongoDB

## MongoDBDown

```bash
kubectl get pods -l app=mongodb
mongosh "mongodb://$HOST:27017/admin" --eval 'db.runCommand({ping: 1})'
```

## MongoDBReplicationMemberUnhealthy

```javascript
rs.status()
// Look at members[].state and members[].health
```

If the unhealthy member needs full resync:
```bash
# Stop mongod on the bad member, delete data dir, restart — primary will resync.
```

## MongoDBConnectionsHigh

```javascript
db.serverStatus().connections
db.currentOp({ "active" : true })
```

Increase `net.maxIncomingConnections` or the driver's `maxPoolSize`.

## MongoDBCursorsTimedOut

Application is opening cursors and not closing them. Look at slow query log:

```javascript
db.setProfilingLevel(1, { slowms: 100 })
db.system.profile.find().sort({ ts: -1 }).limit(10)
```

## MongoDBHighDiskUsage

Resize the PVC. Inspect storage:

```javascript
db.stats()
db.collection.stats()
```

## MongoDBOplogWindowLow

Oplog is too small for the rate of writes. If a replica falls behind by more than the oplog window, it needs full resync. Resize the oplog:

```javascript
use local
db.oplog.rs.stats()
db.adminCommand({replSetResizeOplog: 1, size: 16384})  // size in MB
```

## MongoDBLockRatioHigh

Global lock contention. Investigate concurrent writers and consider sharding.

```javascript
db.serverStatus().locks
```

## MongoDBFlushAverageMsHigh

Slow disk I/O. Check the underlying storage; consider SSD/NVMe.

## MongoDBWiredTigerCacheEvictions

Working set doesn't fit in cache. Raise `wiredTiger.engineConfig.cacheSizeGB` (default is 50% of (RAM - 1GB), max 256GB).

## References

- [MongoDB ops manual](https://www.mongodb.com/docs/manual/administration/)
- [Replica set diagnostics](https://www.mongodb.com/docs/manual/tutorial/troubleshoot-replica-sets/)

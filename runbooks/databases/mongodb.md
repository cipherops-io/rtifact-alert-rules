# Runbook: MongoDB (self-hosted)

> The alerts link to the structured runbook [`mongodb.yaml`](mongodb.yaml), which drives the automated investigation (metric queries and live reads). This page is the human-readable companion with the manual commands.

These alerts read metrics from [percona/mongodb_exporter](https://github.com/percona/mongodb_exporter) v0.40+ in its default naming mode (no `--compatible-mode`). One exporter runs next to every mongod and connects to it directly. Commands below assume the Percona Operator for MongoDB layout: `mongod` and `backup-agent` containers, data at `/data/db`. MongoDB Atlas has its own runbook: [`mongodb-atlas.yaml`](mongodb-atlas.yaml).

Replica-set alerts carry `rs_nm` (replica set name) and, for member alerts, `member_idx` (the member's `host:port` as listed in `rs.status()`). Every alert carries `cluster`, `namespace` and `job`: the exporter's scrape job and namespace, which identify the MongoDB deployment. Instance alerts also carry the exporter's `instance` and `pod`.

Connect to a specific member with `directConnection=true`, so the shell does not get routed to the primary:

```bash
mongosh "mongodb://$USER@$HOST:27017/admin?directConnection=true"
```

## MongoDBExporterDown

The metrics agent cannot scrape the exporter, so no other MongoDB alert can fire for that instance.

```bash
kubectl -n $NS get pod $POD -o wide
kubectl -n $NS logs $POD -c metrics --tail=100     # exporter container name varies by chart
kubectl -n $NS exec $POD -c metrics -- wget -qO- localhost:9216/metrics | head
```

Common causes: the exporter container crash-loops after a password rotation, or the scrape port or path changed in the ServiceMonitor / PodMonitor.

## MongoDBDown

The exporter is running, but `ping` to its mongod fails.

```bash
kubectl -n $NS get pod $POD
kubectl -n $NS describe pod $POD | grep -A5 -E "Last State|OOMKilled"
kubectl -n $NS logs $POD -c mongod --previous --tail=200
```

In the mongod log, look for `Fatal assertion`, `No space left on device`, `WiredTiger error` and `Received signal`. If mongod is healthy, test the exporter's credentials: `db.runCommand({ping: 1})` as the exporter user.

## MongoDBAllInstancesDown

Every mongod behind the service is unreachable: a full database outage. Follow [MongoDBDown](#mongodbdown) on each member, starting with the one that held the most recent data (the former primary). Check for a shared cause first: node pool or zone outage, storage class / CSI failure, expired TLS certificates or keyfile, or a failed rolling upgrade.

Inhibit `MongoDBDown` with this alert (equal on `cluster`, `namespace`, `job`) so a full outage pages once.

## MongoDBReplicaSetNoPrimary

Members are still running, but none of them is primary, so writes fail.

```javascript
rs.status().members.map(m => ({name: m.name, state: m.stateStr, health: m.health, msg: m.lastHeartbeatMessage}))
rs.conf().members.map(m => ({host: m.host, votes: m.votes, priority: m.priority}))
```

- Count healthy voting members. An election needs a strict majority of `votes`.
- If members cannot see each other, check DNS for the member hostnames and network policies on port 27017.
- Force a reconfiguration (`rs.reconfig(cfg, {force: true})`) only as a last resort when a majority is permanently lost. It can roll back writes.

## MongoDBReplicationMemberUnhealthy

Other members cannot reach `member_idx` through heartbeats. Check the member like in [MongoDBDown](#mongodbdown). If its pod is gone (deleted, Pending, node lost), check the StatefulSet and PVC:

```bash
kubectl -n $NS get sts,pod,pvc -l app.kubernetes.io/name=$SERVICE
```

If the member came back but cannot catch up ("too stale"), resync it: stop mongod, empty its data directory, and start it again. It runs an initial sync from another member.

## MongoDBReplicaSetMemberNotServing

The member is reachable but in a non-serving state:

| State | Meaning | Action |
|---|---|---|
| 0 STARTUP | Loading config | Should pass in seconds. Check the log if stuck. |
| 5 STARTUP2 | Initial sync running | Expected after adding or resyncing a member. Check progress with `db.adminCommand({replSetGetStatus: 1, initialSync: 1})` |
| 3 RECOVERING | Not ready (maintenance, rollback done, or too stale) | `RS102 too stale to catch up` in the log means a resync is needed |
| 9 ROLLBACK | Undoing writes that never reached a majority | Rolled-back documents are written to `<dbpath>/rollback/`; review them with the application owner |
| 6 UNKNOWN / 10 REMOVED | Not in the current config, or not seen yet | Compare `rs.conf()` with the deployed members |

## MongoDBReplicaSetPrimaryElected

Informational. Confirm whether the election was planned (rolling restart, stepdown, upgrade). If it was not planned, find why the old primary stepped down:

```bash
kubectl -n $NS logs $OLD_PRIMARY_POD -c mongod | grep -E "Stepping down|Starting an election|transition to"
```

## MongoDBReplicaSetFrequentElections

The election term increased at least 3 times in an hour. Check:

- whether one member keeps restarting (`MongoDBInstanceRestarted`, pod restarts);
- heartbeat failures in the mongod logs (`heartbeat failed`, `Error in heartbeat`) and packet loss between nodes;
- priority takeovers: a higher-priority member rejoining keeps taking the primary role back;
- `settings.electionTimeoutMillis` in `rs.conf()` (10000 by default). Lowering it makes elections more frequent on a flaky network.

## MongoDBReplicationLagHigh

```javascript
rs.printSecondaryReplicationInfo()
rs.status().members.map(m => ({name: m.name, state: m.stateStr, optimeDate: m.optimeDate, syncSourceHost: m.syncSourceHost}))
```

- Check the secondary's CPU, disk latency and IOPS; a secondary on slower storage than the primary lags under write bursts.
- Replicated updates and deletes use the same indexes as on the primary. A collection scan per op on the secondary shows up as `Applied op ... took` slow lines in its log.
- A poor sync source (another lagging secondary) adds delay. Check `syncSourceHost`.
- Delayed members (`secondaryDelaySecs`) are excluded from this alert.

## MongoDBReplicationLagCritical

Same checks as [MongoDBReplicationLagHigh](#mongodbreplicationlaghigh), plus compare the lag with the oplog window on the primary:

```javascript
rs.printReplicationInfo()   // "log length start to end"
```

If the lag will exceed the window, grow the oplog on the sync source now (see [MongoDBOplogWindowLow](#mongodboplogwindowlow)), or plan a resync of the member.

## MongoDBMajorityCommitLagging

The majority commit point is stuck, so `w: "majority"` writes (the default) hang and WiredTiger keeps history in cache.

```javascript
rs.status().optimes                       // lastCommittedWallTime vs lastAppliedWallTime
rs.status().members.map(m => ({name: m.name, state: m.stateStr, health: m.health, optimeDate: m.optimeDate}))
db.adminCommand({getDefaultRWConcern: 1})
```

Bring enough data-bearing voting members back in sync. In a primary-secondary-arbiter set with the secondary down, either restore the secondary quickly or temporarily set its `votes: 0, priority: 0` so the majority can advance. Undo that afterwards.

## MongoDBFlowControlEngaged

The primary is throttling writes because the commit point lags by more than `flowControlTargetLagSeconds` (10s by default).

```javascript
db.serverStatus().flowControl
```

Fix the lagging secondary ([MongoDBReplicationLagHigh](#mongodbreplicationlaghigh)). Disabling flow control (`setParameter enableFlowControl: false`) only moves the pressure to the WiredTiger cache.

## MongoDBOplogWindowLow

The value is an estimate: oplog `maxSize` divided by the last hour's oplog insert byte rate. Confirm on the member:

```javascript
rs.printReplicationInfo()
db.getSiblingDB("local").oplog.rs.stats().maxSize
```

Resize the oplog on every member (no restart needed). The size is in MB:

```javascript
db.adminCommand({replSetResizeOplog: 1, size: 51200})
```

If a batch job or migration causes the write burst, consider throttling it. `storage.oplogMinRetentionHours` guarantees a time-based minimum (the estimate does not account for it).

## MongoDBWriteConcernTimeouts

Writes returned `writeConcernError` because not enough members acknowledged them within `wtimeout`.

```javascript
db.serverStatus().metrics.getLastError
```

Check member health and lag first. If the application sets a very short `wtimeout`, align it with the expected replication latency.

## MongoDBConnectionsHigh

```javascript
db.serverStatus().connections
db.currentOp(true).inprog.reduce((a, op) => { const k = (op.client || "?").split(":")[0] + " " + (op.appName || ""); a[k] = (a[k] || 0) + 1; return a }, {})
```

- Total pool size = `maxPoolSize` (default 100 per driver client) × number of application instances. Scaling the app out multiplies it.
- A connection storm after a failover shows up as a spike in `connections.totalCreated`.
- The limit is `net.maxIncomingConnections`, capped by the open-file limit of the mongod process.

## MongoDBConnectionsExhausted

Same investigation as [MongoDBConnectionsHigh](#mongodbconnectionshigh), but act now: reduce `maxPoolSize` or restart the leaking client. Raise `net.maxIncomingConnections` only if the host has memory headroom (each connection uses about 1 MB).

## MongoDBOperationsQueued

```javascript
db.serverStatus().globalLock
db.currentOp({$or: [{secs_running: {$gte: 5}}, {waitingForLock: true}]})
```

Kill a runaway operation with `db.killOp(opid)`. Look for collection scans (`planSummary: COLLSCAN`), index builds and `collMod` / `compact` taking exclusive locks, and check the [WiredTiger cache alerts](#mongodbwiredtigercachefull).

## MongoDBWriteLatencyHigh

```javascript
db.serverStatus().opLatencies
db.setProfilingLevel(1, {slowms: 100})
db.system.profile.find({op: {$in: ["insert", "update", "remove"]}}).sort({millis: -1}).limit(10)
```

Check disk write latency, WiredTiger dirty cache, `writeConcern` waits (`waitForWriteConcernDurationMillis` in slow log lines) and lock queues. Remember to set the profiler back to level 0.

## MongoDBWiredTigerCacheFull

```javascript
const c = db.serverStatus().wiredTiger.cache
({used: c["bytes currently in the cache"] / c["maximum bytes configured"], dirty: c["tracked dirty bytes in the cache"] / c["maximum bytes configured"]})
```

- The default cache size is 50% of (RAM − 1 GB). In a container, mongod derives it from the memory limit; an explicit `storage.wiredTiger.engineConfig.cacheSizeGB` that does not fit the limit causes OOM kills.
- Look for large scans in the slow query log; an index often fixes cache churn.
- If the working set has outgrown the node, give it more memory or shard the data.

## MongoDBWiredTigerCacheDirtyHigh

Writes are arriving faster than WiredTiger can flush them. Check disk throughput and latency (`iostat -x`, volume metrics), the write rate, and [MongoDBMajorityCommitLagging](#mongodbmajoritycommitlagging): a stuck commit point pins history in cache. Slow or burst-credit-limited volumes (for example gp2 or standard persistent disks) are a frequent cause.

## MongoDBCursorsTimedOut

```javascript
db.serverStatus().metrics.cursor
db.getSiblingDB("admin").aggregate([{$currentOp: {idleCursors: true}}, {$match: {type: "idleCursor"}}, {$group: {_id: {ns: "$ns", app: "$appName"}, n: {$sum: 1}}}, {$sort: {n: -1}}])
```

Fix the application to iterate cursors to the end or close them, and use `limit` / batch sizes. Avoid `noCursorTimeout` cursors.

## MongoDBLowDiskSpace

Free space on the data volume is below `indexBuildMinAvailableDiskSpaceMB` (500 MB by default). mongod stops when the volume fills up.

```bash
kubectl -n $NS exec $POD -c mongod -- df -h /data/db
kubectl -n $NS exec $POD -c mongod -- du -sh /data/db/journal /data/db/diagnostic.data
```

Grow the PVC if the storage class allows expansion (`kubectl -n $NS edit pvc ...`). Then reclaim space: drop unused collections or indexes, or run `compact` on a secondary.

## MongoDBPrimaryFsyncLocked

All writes on the node are blocked.

```javascript
db.currentOp().fsyncLock          // true while locked
db.fsyncUnlock()                  // repeat until lockCount is 0
```

Before unlocking, confirm that no filesystem or volume snapshot is still being taken.

## MongoDBSecondaryFsyncLocked

The secondary cannot apply replicated writes while locked. Check the backup job that locked it, then unlock as in [MongoDBPrimaryFsyncLocked](#mongodbprimaryfsynclocked).

## MongoDBPBMBackupFailed

```bash
pbm status
pbm list
pbm logs --event=backup --tail=100 --severity=E
```

Common causes: remote storage credentials or quota, a pbm-agent not running on one member, or a member with a stale `pbm-agent` version.

## MongoDBPBMNoRecentBackup

Confirm that the scheduler (CronJob, `pbm` schedule in an operator CR, or system cron) still runs and its last run's exit status. Check `pbm status` for a backup stuck in `running`. Run a backup by hand if needed: `pbm backup --type=logical` (or `physical`).

## MongoDBPBMAgentUnhealthy

```bash
pbm status            # agents section: "OK", "FAILED status", "NOT FOUND"
kubectl -n $NS logs $POD -c backup-agent --tail=100
```

Restart the agent next to the affected mongod. Check that it can reach both its mongod and the remote storage.

## MongoDBInstanceRestarted

Informational. If the restart was not planned, check the end of the previous log (`kubectl logs --previous`) and the pod's last termination reason (OOMKilled, Error, liveness probe failure).

## References

- [Replica set troubleshooting](https://www.mongodb.com/docs/manual/tutorial/troubleshoot-replica-sets/)
- [serverStatus output](https://www.mongodb.com/docs/manual/reference/command/serverStatus/)
- [WiredTiger cache tuning](https://www.mongodb.com/docs/manual/core/wiredtiger/#memory-use)
- [Percona Backup for MongoDB](https://docs.percona.com/percona-backup-mongodb/)

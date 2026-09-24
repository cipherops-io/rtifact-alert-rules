# Runbook: ClickHouse

This runbook covers two different sources of alerts, and they fail independently:

| Section | Metrics | Tells you |
|---|---|---|
| [ClickHouse server](#clickhouse-server-data-plane) | `chi_clickhouse_*` | Whether the ClickHouse servers are healthy: queries, inserts, replication, parts, disks |
| [clickhouse-operator](#clickhouse-operator-control-plane) | `clickhouse_operator_*` | Whether the operator can converge your `ClickHouseInstallation` (CHI) objects |

Both come from the same pod (`clickhouse-operator`, containers `clickhouse-operator` and
`metrics-exporter`), but a healthy operator says nothing about a healthy server, and a
broken operator does not by itself break a running cluster.

## Orientation

Every `chi_clickhouse_*` series carries:

- `chi` — the ClickHouseInstallation name
- `hostname` — the host FQDN, e.g. `chi-prod3-cluster-0-1.clickhouse.svc.cluster.local`
- `namespace` — the CHI's namespace. **Note:** when Prometheus already sets `namespace` on
  the scrape target, ClickHouse's own namespace arrives as `exported_namespace`. If
  `namespace` in an alert looks like the operator's namespace, that is why.

The pod name is the first label of `hostname`:

```bash
# hostname chi-prod3-cluster-0-1.clickhouse.svc.cluster.local -> pod chi-prod3-cluster-0-1
POD=$(echo "$HOSTNAME_LABEL" | cut -d. -f1)
NS=$(echo "$HOSTNAME_LABEL" | cut -d. -f2)

kubectl -n "$NS" get pod "$POD" -o wide
kubectl -n "$NS" logs "$POD" -c clickhouse --tail=200
kubectl -n "$NS" exec -it "$POD" -c clickhouse -- clickhouse-client
```

Opening a client on the alerting host is the first step in almost every procedure below:

```bash
kubectl -n "$NS" exec -it "$POD" -c clickhouse -- clickhouse-client --query "SELECT 1"
```

If the server-side alerts are firing for a whole CHI at once, check the operator section
too — a bad rollout shows up on both sides.

---

# ClickHouse server (data plane)

### A note on the event-counter alerts

Several alerts below read a `chi_clickhouse_event_*` counter and are written as
two branches:

```promql
increase(<counter>[10m]) > 0
or (<counter> > 0 unless <counter> offset 10m)
```

ClickHouse only publishes a `system.events` counter **after the event has
happened once** since server start — before that the series does not exist at
all. It then appears already carrying its value and stays flat, so `increase()`
alone would never see the jump and a one-off event would go unreported. The
second branch covers exactly that: *nonzero, and not there one window ago*.

Two consequences when you are triaging:

- An alert from the second branch means **the counter just appeared** — check
  `SELECT event, value FROM system.events WHERE event = '<Name>'` for the total,
  and the server log around the alert's start time for the actual error.
- These alerts **resolve on their own within one window** if the event does not
  recur. A resolve is not evidence that the problem was fixed.

## ClickHouseServerDown

The metrics-exporter cannot run `SELECT ... FROM system.metrics` against this host. That is
a real query over the native protocol, so this fires when the server is down, unreachable,
or too overloaded to answer at all.

```bash
kubectl -n "$NS" get pod "$POD" -o wide
kubectl -n "$NS" describe pod "$POD" | tail -40
kubectl -n "$NS" logs "$POD" -c clickhouse --tail=200
kubectl -n "$NS" logs "$POD" -c clickhouse --previous --tail=100   # if it restarted
```

Work through, in order:

1. **Is the pod running?** `Pending` → scheduling or PVC binding. `CrashLoopBackOff` →
   read the previous logs; `OOMKilled` in `Last State` is the usual answer.
2. **Is it up but not ready?** A server replaying a large replication queue or loading many
   parts can take minutes to accept connections. `Loading data parts` in the log means wait.
3. **Is the server up but refusing connections?** `Too many simultaneous queries` or
   `Connection limit reached` in the log — see [ClickHouseTooManyConnections](#clickhousetoomanyconnections).
4. **Is it only the exporter that cannot connect?** Check the credentials the exporter uses;
   a rotated password looks exactly like a down server from this alert's point of view.

```bash
# Does the server answer from inside the pod, bypassing the service and the exporter?
kubectl -n "$NS" exec "$POD" -c clickhouse -- clickhouse-client --query "SELECT 1"
```

If a shard has other live replicas, remove this host from rotation (or let the readiness
probe do it) while you work. If it is the last replica of its shard, that shard's data is
unavailable and this is a full incident.

## ClickHouseServerMetricsAbsent

No `chi_clickhouse_metric_*` series at all. Every ClickHouse server alert is blind until
this clears — treat it as an outage of your observability, not of ClickHouse.

```bash
kubectl -n <operator-namespace> logs deploy/clickhouse-operator -c metrics-exporter --tail=100

# Hit the exporter directly.
kubectl -n <operator-namespace> port-forward deploy/clickhouse-operator 8888:8888
curl -s localhost:8888/metrics | grep -c chi_clickhouse_metric_

# If the exporter is healthy, suspect the scrape config.
kubectl -n <operator-namespace> get servicemonitor -l app=clickhouse-operator -o yaml
```

Common causes: the `metrics-exporter` container is crash-looping, the CHI has no running
hosts at all (check `kubectl get chi -A`), or the exporter's ClickHouse user/password is
wrong so every fetch fails.

## ClickHouseMetricsFetchErrors

The server answers `system.metrics` but one other fetch keeps failing. The `fetch_type`
label names which one.

Note the spelling depends on your operator version — up to 0.25.x the values are
dotted or spaced (`system.replicas`, `system.mutations`, `system.disks`,
`system.detached_parts`, `system parts`, `table sizes`); from 0.27.x they are
underscored (`system_replicas`, `system_mutations`, …). The rules match both, but
your own ad-hoc queries need the spelling your cluster actually emits:

```promql
# What does this cluster call them?
group by (fetch_type) (chi_clickhouse_metric_fetch_errors)
```

```bash
kubectl -n <operator-namespace> logs deploy/clickhouse-operator -c metrics-exporter | grep -i "$FETCH_TYPE" | tail -20
```

Then run the same query by hand on the alerting host — the error text is the whole answer:

```sql
SELECT count() FROM system.parts;        -- system_parts
SELECT count() FROM system.mutations;    -- system_mutations
SELECT count() FROM system.detached_parts;
SELECT * FROM system.disks;
```

Usual causes: the exporter's user lacks `SELECT` on that system table (grant it), or the
query times out because the server has tens of thousands of tables/parts. Until it is
fixed, the alerts fed by that family (parts, mutations, disks, detached parts) cannot fire.

## ClickHouseServerRestarted

Informational. Uptime is under 5 minutes.

```bash
kubectl -n "$NS" get pod "$POD" -o custom-columns='POD:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount,START:.status.startTime'
kubectl -n "$NS" describe pod "$POD" | grep -A5 "Last State"
```

- During a planned rolling upgrade: expected, one host at a time. Confirm with
  `kubectl get chi <chi> -n "$NS" -o jsonpath='{.status.status}'`.
- `Last State: OOMKilled`: raise the container memory limit **and** cap ClickHouse's own
  `max_server_memory_usage` below it, otherwise the kernel keeps killing the server instead
  of ClickHouse rejecting one query.
- Repeated restarts with no CHI change: see
  [ClickHouseOperatorHostRestartsHigh](#clickhouseoperatorhostrestartshigh).

Expect replication lag and elevated part counts for a few minutes after any restart.

## ClickHouseReadonlyReplica

Replicated tables on this host have lost their ZooKeeper/Keeper state and refuse all writes.
Inserts and ALTERs against them fail; reads still work but go stale.

```sql
-- Which tables, and why?
SELECT database, table, is_readonly, is_session_expired, zookeeper_exception, absolute_delay
FROM system.replicas
WHERE is_readonly;

-- Is Keeper reachable from this host at all?
SELECT * FROM system.zookeeper WHERE path = '/' LIMIT 5;
```

1. **Keeper/ZooKeeper down or unreachable** — fix that first; replicas recover on their own
   once sessions re-establish. Check the Keeper pods and
   [ClickHouseKeeperHardwareExceptions](#clickhousekeeperhardwareexceptions).
2. **Session expired but Keeper is healthy** — usually a long GC/IO stall on this host, or
   `session_timeout_ms` too low for the observed latency.
3. **Metadata missing in Keeper** (`No node` in `zookeeper_exception`) — the table's path was
   deleted or restored from a stale snapshot. Do not drop the table: restore the Keeper data
   or re-create the replica with `SYSTEM RESTORE REPLICA db.table`.

```sql
-- After Keeper is healthy again, on the affected host:
SYSTEM RESTART REPLICA db.table;
-- Only when Keeper metadata for the table is genuinely gone:
SYSTEM RESTORE REPLICA db.table;
```

## ClickHouseReplicationLagHigh

This replica is more than 5 minutes behind. Queries routed here return stale results.

```sql
SELECT database, table, absolute_delay, queue_size, inserts_in_queue, merges_in_queue,
       log_max_index - log_pointer AS behind
FROM system.replicas
ORDER BY absolute_delay DESC
LIMIT 20;

-- What is the queue actually working on, and is anything failing?
SELECT database, table, type, num_tries, last_exception, create_time
FROM system.replication_queue
ORDER BY num_tries DESC
LIMIT 20;
```

- `num_tries` climbing on one entry → that entry is stuck and blocks the queue behind it.
  See [ClickHouseReplicationQueueHigh](#clickhousereplicationqueuehigh).
- Lag with an empty queue → this replica is not receiving; check Keeper and the
  interserver port between hosts.
- Lag across every replica → the cluster is saturated; look at merges, disk IO and
  [ClickHouseTooManyRunningQueries](#clickhousetoomanyrunningqueries).

Route reads away from this host until it catches up if stale results are not acceptable.

## ClickHouseReplicationQueueHigh

The queue is not draining. Lag, part count and disk usage all grow from here.

```sql
SELECT database, table, queue_size, inserts_in_queue, merges_in_queue
FROM system.replicas
WHERE queue_size > 100;

-- The blocked entry, if there is one.
SELECT database, table, type, source_replica, num_tries, last_exception, postpone_reason
FROM system.replication_queue
WHERE num_tries > 1
ORDER BY create_time
LIMIT 20;
```

- `last_exception` mentioning a missing part → see
  [ClickHouseReplicatedPartFetchFailures](#clickhousereplicatedpartfetchfailures).
- `postpone_reason` about too many fetches/merges → the background pool is the bottleneck;
  raise `background_fetches_pool_size` / `background_pool_size` or reduce ingest.
- Queue full of `MERGE_PARTS` entries → merges are the bottleneck; see
  [ClickHouseMaxPartCountForPartition](#clickhousemaxpartcountforpartition).

Do not drop queue entries to make the alert stop — that is how replicas silently diverge.

## ClickHouseReplicatedDataLoss

ClickHouse found a part referenced in Keeper that exists on no replica. Those rows are gone
from the cluster; only re-ingestion brings them back.

```bash
kubectl -n "$NS" logs "$POD" -c clickhouse | grep -i "ReplicatedDataLoss\|No active replica has part" | tail -40
```

```sql
SELECT database, table, is_readonly, is_session_expired, last_queue_update_exception
FROM system.replicas;
```

1. Identify which table and which partition the missing parts belong to (log lines name the
   part).
2. Check whether any replica still has the data: run `SELECT count() FROM db.table` for the
   affected partition on each host — counts that differ tell you which replica to keep.
3. Re-ingest that time range from the upstream source (Kafka, S3, the producer's own
   retention) if the rows matter.
4. Root-cause the Keeper side: this usually follows Keeper data loss, a restore from a stale
   Keeper snapshot, or PVCs being wiped while Keeper metadata survived. Fix that before the
   next incident.

## ClickHouseReplicatedPartFetchFailures

This replica is failing to download parts from its peers, so it stays behind on those tables.

```sql
SELECT database, table, type, source_replica, num_tries, last_exception
FROM system.replication_queue
WHERE type = 'GET_PART'
ORDER BY num_tries DESC
LIMIT 20;
```

```bash
# Can this host reach the source replica's interserver port (9009 by default)?
kubectl -n "$NS" exec "$POD" -c clickhouse -- wget -qO- --timeout=5 "http://$SOURCE_HOST:9009/" || echo "unreachable"
```

Check, in order: the source replica is running and not read-only; the interserver port is
allowed by NetworkPolicy; `interserver_http_host` resolves correctly from this pod; and both
sides have free disk (a fetch needs room for the whole part).

## ClickHouseDataAfterMergeDiffersFromReplica

Two replicas merged the same inputs and produced different bytes. ClickHouse resolves it by
discarding the local result and fetching the peer's copy, so the cluster converges — but the
divergence itself needs a cause.

```bash
kubectl -n "$NS" logs "$POD" -c clickhouse | grep -i "differs from" | tail -20

# Are all replicas on the same version? Mixed versions is the most common cause.
kubectl -n "$NS" get pods -l clickhouse.altinity.com/chi="$CHI" \
  -o custom-columns='POD:.metadata.name,IMAGE:.spec.containers[0].image'
```

- **Mixed versions** — finish the rolling upgrade; merge behaviour can change between versions.
- **Non-deterministic expressions** in DEFAULT/MATERIALIZED columns or in the sorting key
  (`now()`, `rand()`, dictionary lookups that change) — fix the schema, this will keep
  happening.
- **Neither** — suspect storage corruption on one host: check kernel logs and look for
  `ClickHouseDetachedPartsPresent` with reason `broken` on the same host.

## ClickHouseKeeperSessionUnstable

A healthy server holds exactly one Keeper/ZooKeeper session. More than one means sessions
are expiring and being re-established.

```sql
SELECT * FROM system.metrics WHERE metric LIKE 'ZooKeeper%';
SELECT event, value FROM system.events WHERE event LIKE 'ZooKeeper%' ORDER BY value DESC LIMIT 10;
```

```bash
# Keeper side: are the pods healthy and is a leader elected?
kubectl -n "$NS" get pods -l "app=clickhouse-keeper" -o wide
kubectl -n "$NS" exec <keeper-pod> -- sh -c 'echo mntr | nc 127.0.0.1 9181' | grep -E "zk_server_state|zk_avg_latency|zk_outstanding_requests"
```

Look for Keeper latency spikes, a Keeper pod restarting, or a `session_timeout_ms` that is
too tight for the network. Left alone this ends in
[ClickHouseReadonlyReplica](#clickhousereadonlyreplica).

## ClickHouseKeeperHardwareExceptions

Connection-level Keeper failures (connection loss, session timeout) — not logical errors.
Replicated INSERTs, merge assignments and ALTERs all need Keeper, so writes stall while this
continues.

```bash
kubectl -n "$NS" logs "$POD" -c clickhouse | grep -i "zookeeper\|keeper" | grep -iE "exception|timeout|session" | tail -40

kubectl -n "$NS" get pods -l "app=clickhouse-keeper"
kubectl -n "$NS" exec <keeper-pod> -- sh -c 'echo mntr | nc 127.0.0.1 9181'
```

Check the Keeper ensemble first: a lost quorum, a slow Keeper disk (Keeper fsyncs every
write — it needs fast storage), or Keeper being OOMKilled. ClickHouse-side tuning
(`session_timeout_ms`, `operation_timeout_ms`) only papers over a Keeper that is too slow.

## ClickHouseRejectedInserts

Writes are failing with `Too many parts`. The client either retries or loses the data.

```sql
-- Which table is over the limit?
SELECT database, table, partition, count() AS parts
FROM system.parts
WHERE active
GROUP BY database, table, partition
ORDER BY parts DESC
LIMIT 20;

-- Are merges running, or are they blocked?
SELECT database, table, elapsed, progress, num_parts FROM system.merges;
SELECT * FROM system.metrics WHERE metric LIKE 'Background%Pool%';
```

Immediate relief, in order of preference:

1. **Reduce the insert rate / increase batch size on the client.** This is the actual fix —
   see [ClickHouseSmallInsertBatches](#clickhousesmallinsertbatches).
2. **Let merges catch up**: check the merge pool is not starved by mutations
   (`system.mutations`) or by a full disk (a merge needs free space for its output).
3. **Raise `parts_to_throw_insert`** only as a temporary shield, and only while merges are
   demonstrably catching up. Raising it on a cluster that cannot merge just delays the wall.

```sql
-- Force a merge on the worst partition once ingest has slowed.
OPTIMIZE TABLE db.tbl PARTITION '2026-09-24' FINAL;
```

## ClickHouseDelayedInserts

ClickHouse is throttling writers because a partition crossed `parts_to_delay_insert`.
Producers see slower INSERTs and ingest lag builds upstream. This is the stage before
[ClickHouseRejectedInserts](#clickhouserejectedinserts) — same investigation, more time.

```sql
SELECT database, table, partition, count() AS parts
FROM system.parts WHERE active
GROUP BY database, table, partition ORDER BY parts DESC LIMIT 10;

SELECT event, value FROM system.events WHERE event IN ('DelayedInserts','RejectedInserts','DelayedInsertsMilliseconds');
```

## ClickHouseMaxPartCountForPartition

Merges are falling behind ingest. Queries over that partition open every part, so reads slow
down as the count climbs, and throttling/rejection follow.

```sql
SELECT database, table, partition, count() AS parts, formatReadableSize(sum(bytes)) AS size
FROM system.parts WHERE active
GROUP BY database, table, partition
ORDER BY parts DESC LIMIT 20;

-- Merge pool saturation
SELECT * FROM system.metrics
WHERE metric IN ('BackgroundMergesAndMutationsPoolTask','BackgroundMergesAndMutationsPoolSize');
```

Causes, in the order they actually occur:

1. **Too-small insert batches** (most common) — fix the writer, or enable `async_insert`.
2. **Too many partitions** — a partition key like `toStartOfHour(ts)` on high-cardinality
   data means every insert touches many partitions. Partition by month or day.
3. **Merge pool starved** by long mutations, or merges blocked by low disk space.
4. **Genuinely undersized host** — raise `background_pool_size` /
   `background_merges_mutations_concurrency_ratio` only if there is CPU and IO to spare.

## ClickHouseDistributedFilesToInsertHigh

Rows accepted by a Distributed table are queued on local disk instead of being written to
their shards. They are not queryable yet and are lost if this host's volume is lost.

```sql
SELECT database, table, data_files, data_compressed_bytes, last_exception
FROM system.distribution_queue
ORDER BY data_files DESC;
```

The `last_exception` names the unreachable shard. Then:

```bash
kubectl -n "$NS" get pods -l clickhouse.altinity.com/chi="$CHI" -o wide
```

Fix the target shard (down pod, read-only replica, rejected inserts on that side) and the
queue drains on its own. `SYSTEM FLUSH DISTRIBUTED db.tbl` retries immediately once the
shard is back. Do not delete the queue directory unless you accept losing those rows.

## ClickHouseSmallInsertBatches

Under 1000 rows per INSERT. Every INSERT makes at least one part, so this is the root cause
behind most part-count, throttling and rejection incidents on this cluster.

```sql
SELECT
    toStartOfHour(event_time) AS h,
    count() AS inserts,
    sum(written_rows) AS rows,
    round(sum(written_rows) / count()) AS rows_per_insert
FROM system.query_log
WHERE type = 'QueryFinish' AND query_kind = 'Insert' AND event_time > now() - INTERVAL 6 HOUR
GROUP BY h ORDER BY h;

-- Who is writing like this?
SELECT initial_user, client_name, count() AS inserts, round(avg(written_rows)) AS avg_rows
FROM system.query_log
WHERE type = 'QueryFinish' AND query_kind = 'Insert' AND event_time > now() - INTERVAL 1 HOUR
GROUP BY initial_user, client_name ORDER BY inserts DESC LIMIT 20;
```

Fixes, best first:

1. **Batch in the client** — accumulate rows and insert 10k–1M at a time.
2. **`async_insert=1` with `wait_for_async_insert=1`** — ClickHouse batches for you. The
   right answer when you cannot change many small writers.
3. **A Buffer table** — works, but see
   [ClickHouseStorageBufferErrorOnFlush](#clickhousestoragebuffererroronflush): rows in a
   Buffer are not durable.

## ClickHouseStorageBufferErrorOnFlush

A Buffer table could not flush to its destination. Buffer rows live in memory, so a flush
that never succeeds is silent data loss — the client's INSERT already returned success.

```bash
kubectl -n "$NS" logs "$POD" -c clickhouse | grep -i "StorageBuffer\|Error on flush" | tail -30
```

```sql
-- What is sitting in the buffers right now?
SELECT * FROM system.metrics WHERE metric LIKE 'StorageBuffer%';
```

The destination table is the suspect: it may be read-only
([ClickHouseReadonlyReplica](#clickhousereadonlyreplica)), rejecting inserts
([ClickHouseRejectedInserts](#clickhouserejectedinserts)), out of disk, or schema-mismatched
with the Buffer table after an ALTER. Fix the destination, then flush manually:

```sql
OPTIMIZE TABLE db.buffer_table;   -- forces a flush attempt
```

## ClickHouseTooManyRunningQueries

Queries are arriving faster than they finish. Latency rises for everyone on this host and
memory pressure grows with each concurrent query.

```sql
SELECT query_id, user, elapsed, formatReadableSize(memory_usage) AS mem, query
FROM system.processes
ORDER BY elapsed DESC
LIMIT 20;

SELECT user, count() FROM system.processes GROUP BY user ORDER BY 2 DESC;
```

```sql
-- Kill one runaway query:
KILL QUERY WHERE query_id = '<id>';
-- Or everything from one user, when a client is hammering the cluster:
KILL QUERY WHERE user = '<user>' AND elapsed > 60;
```

Then decide why: a slow query pattern that piles up (fix the query or add the right ORDER BY
/ partition filter), a retry storm from a client that timed out, or genuine growth that needs
more replicas. `max_concurrent_queries` and per-user quotas keep one workload from taking the
host down — set them rather than relying on this alert.

## ClickHouseLongestRunningQuery

One query has been running over 10 minutes, holding its memory and thread slots the whole time.

```sql
SELECT query_id, user, elapsed, formatReadableSize(memory_usage) AS mem,
       read_rows, formatReadableSize(read_bytes) AS read, query
FROM system.processes
ORDER BY elapsed DESC LIMIT 5;
```

Check whether the client is still waiting — if it timed out, the query is pure waste:

```sql
KILL QUERY WHERE query_id = '<id>';
```

For the fix, `EXPLAIN` the query and look for a missing partition/primary-key filter, a JOIN
with the large table on the right-hand side, or `SELECT *` over wide rows. Set
`max_execution_time` for interactive users so ad-hoc queries cannot run unbounded.

## ClickHouseQueryPreempted

Queries are stopped and waiting because higher-priority queries are running. Low-priority
work (reports, backfills) can stall indefinitely.

```sql
SELECT query_id, user, elapsed, query FROM system.processes ORDER BY elapsed DESC LIMIT 20;
SELECT * FROM system.metrics WHERE metric = 'QueryPreempted';
```

Either the `priority` settings in the users profile are too aggressive, or the host is simply
oversubscribed — see [ClickHouseTooManyRunningQueries](#clickhousetoomanyrunningqueries).
Give the background workload its own profile with a bounded `max_threads` instead of relying
on preemption, or move it to a dedicated replica.

## ClickHouseTooManyConnections

Over 100 client connections (HTTP + native + MySQL + PostgreSQL) for 10 minutes. Each costs a
server thread and memory; at `max_connections` new clients are refused.

```sql
SELECT metric, value FROM system.metrics
WHERE metric IN ('HTTPConnection','TCPConnection','MySQLConnection','PostgreSQLConnection','InterserverConnection');

-- Who is connected, and are they doing anything?
SELECT user, client_name, count() FROM system.processes GROUP BY user, client_name ORDER BY 3 DESC;
```

A count that only grows and never falls is a client pool leaking connections. A count that
spikes with slow queries is a retry storm — fix the slow queries first. Cap it server-side
with `max_connections` and per-user `max_concurrent_queries_for_user` so one client cannot
exhaust the server.

## ClickHouseDiskSpaceLow

Under 10% free. ClickHouse needs free space to merge (a merge writes the whole output part
before deleting its inputs), so merges stop first, part counts climb, and inserts fail.

```sql
SELECT name, path, formatReadableSize(free_space) AS free,
       formatReadableSize(total_space) AS total,
       round(100 * free_space / total_space, 1) AS free_pct
FROM system.disks;

-- Where is the space going?
SELECT database, table, formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts WHERE active
GROUP BY database, table ORDER BY sum(bytes_on_disk) DESC LIMIT 20;

-- Space that is not live data:
SELECT count(), formatReadableSize(sum(bytes_on_disk)) FROM system.parts WHERE NOT active;
SELECT count() FROM system.detached_parts;
```

Fastest wins, in order:

1. **Drop old partitions** if retention allows: `ALTER TABLE db.tbl DROP PARTITION '...'`.
2. **Remove detached parts** you have already triaged (see
   [ClickHouseDetachedPartsPresent](#clickhousedetachedpartspresent)).
3. **Resize the PVC** — `kubectl -n "$NS" patch pvc <pvc> -p '{"spec":{"resources":{"requests":{"storage":"<new>"}}}}'`
   with a storage class that allows expansion. Do this *before* the disk is full; expansion
   on a completely full volume is much harder.
4. **Add a TTL to cold storage** (`TTL ts + INTERVAL 30 DAY TO VOLUME 'cold'`) for the long term.

## ClickHouseDiskWillFillWithin24h

Under 30% free and, on the last 6 hours' trend, full within a day. Same remedies as
[ClickHouseDiskSpaceLow](#clickhousediskspacelow), with time to do them properly.

```promql
# Confirm the trend and see the prediction.
chi_clickhouse_metric_DiskFreeBytes
predict_linear(chi_clickhouse_metric_DiskFreeBytes[6h], 24 * 3600)
```

```sql
-- Is growth organic, or did retention stop deleting?
SELECT toDate(min_time) AS d, count() AS parts, formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts WHERE active
GROUP BY d ORDER BY d LIMIT 40;
```

Old dates that should have aged out mean a TTL rule stopped running (check
`system.mutations` for stuck TTL merges) — fix that rather than resizing the volume.

## ClickHouseDetachedPartsPresent

Parts are detached for a reason other than an operator action. Detached parts are invisible
to queries — those rows are missing from this replica's results — and still take disk space.

```sql
SELECT database, table, disk, reason, count() AS parts
FROM system.detached_parts
GROUP BY database, table, disk, reason
ORDER BY parts DESC;
```

Read the `reason`:

- **`broken` / `broken-on-start`** — checksum failure or corrupt files. Do not reattach.
  Confirm the data exists on another replica, then drop them:
  `ALTER TABLE db.tbl DROP DETACHED PART '<name>' SETTINGS allow_drop_detached = 1;`
  Repeated `broken` parts on one host mean failing storage — replace the volume.
- **`unexpected`** — the part is not in Keeper (often after a restore or a hard restart).
  `SYSTEM RESTORE REPLICA` or reattach once you have verified the rows are not duplicated.
- **`covered-by-broken`** — collateral from a broken part; drop with the part it belongs to.
- **`ignored` / `noquorum` / `clone`** — triage individually; check the server log around the
  detach time for the originating error.

Always verify row counts against a healthy replica before dropping anything.

## ClickHouseTooManyMutations

Over 100 unfinished mutations on one table. Mutations rewrite whole parts in the background
pool, so a queue this deep starves merges and inflates disk usage.

```sql
SELECT database, table, mutation_id, command, create_time, parts_to_do, is_done, latest_fail_reason
FROM system.mutations
WHERE NOT is_done
ORDER BY create_time
LIMIT 30;
```

The usual cause is a client issuing `ALTER TABLE ... UPDATE/DELETE` per row or per small
batch. That is not what mutations are for — use `ReplacingMergeTree`/`CollapsingMergeTree`, or
lightweight `DELETE`, and batch the rest.

```sql
-- Cancel mutations that are no longer wanted (oldest first; they are applied in order):
KILL MUTATION WHERE database = 'db' AND table = 'tbl' AND mutation_id = '<id>';
```

## ClickHouseMutationsNotProgressing

`parts_to_do` has not gone down in an hour. The mutation is stuck, the ALTER is not applied,
and everything queued behind it on that table waits.

```sql
SELECT database, table, mutation_id, command, parts_to_do, latest_fail_time, latest_fail_reason
FROM system.mutations
WHERE NOT is_done
ORDER BY create_time;
```

`latest_fail_reason` is the answer most of the time:

- **Memory limit exceeded** — the mutation cannot rewrite a large part within
  `max_memory_usage`; raise it for the merge pool or split the partition.
- **No space left** — see [ClickHouseDiskSpaceLow](#clickhousediskspacelow); a mutation needs
  room for the rewritten parts.
- **Missing/corrupt part** — see
  [ClickHouseDetachedPartsPresent](#clickhousedetachedpartspresent).
- **Empty `latest_fail_reason` but no progress** — the background pool is saturated by merges
  or other mutations; check `system.metrics` for
  `BackgroundMergesAndMutationsPoolTask` at its pool size.

If the mutation is no longer needed, `KILL MUTATION` it — a stuck mutation blocks the table's
queue indefinitely.

## ClickHouseDistributedConnectionExceptions

This host exhausted its retries connecting to a remote shard. Distributed queries touching
that shard fail, or silently return partial results when `skip_unavailable_shards` is on.

```sql
SELECT cluster, shard_num, replica_num, host_name, port, errors_count, estimated_recovery_time
FROM system.clusters
WHERE errors_count > 0;
```

```bash
kubectl -n "$NS" get pods -l clickhouse.altinity.com/chi="$CHI" -o wide
kubectl -n "$NS" exec "$POD" -c clickhouse -- clickhouse-client --host <remote-host> --query "SELECT 1"
```

Check the remote pod is running, the native port (9000) is reachable — NetworkPolicy and
service DNS included — and the remote host is not itself refusing connections. Also look at
[ClickHouseDistributedFilesToInsertHigh](#clickhousedistributedfilestoinserthigh): the same
unreachable shard usually shows up there as a growing write queue.

## ClickHouseNetworkErrors

Network or DNS errors on this host. ClickHouse resolves replica and shard hostnames through
cluster DNS on every new connection, so DNS trouble surfaces here before anywhere else.

These come from two different places, and `system.errors` is the one that carries the
actual error text:

```sql
-- ClickHouse error codes. NETWORK_ERROR is what this alert watches.
SELECT name, value, last_error_time, last_error_message
FROM system.errors
WHERE name IN ('NETWORK_ERROR','DNS_ERROR','SOCKET_TIMEOUT','NO_REMOTE_SHARD_AVAILABLE')
ORDER BY value DESC;

-- DNS resolution failures.
SELECT event, value FROM system.events WHERE event = 'DNSError';
```

There is no `NetworkErrors` ProfileEvent in ClickHouse — if you find a rule or dashboard
referring to `chi_clickhouse_event_NetworkErrors`, it has never matched anything.

```bash
# Does DNS work from inside the pod?
kubectl -n "$NS" exec "$POD" -c clickhouse -- nslookup "$(echo "$HOSTNAME_LABEL" | cut -d. -f1-3)"
kubectl -n "$NS" exec "$POD" -c clickhouse -- getent hosts <keeper-service>
```

Check CoreDNS health and its error rate (the `coredns` alerts in this repo cover it),
NetworkPolicy changes, and CNI-level packet loss. ClickHouse caches DNS; after fixing DNS run
`SYSTEM DROP DNS CACHE` on the affected hosts.

## ClickHouseKafkaConsumerErrors

The Kafka table engine is erroring. While consumers are failing, the materialized views
behind those Kafka tables stop ingesting and the destination tables fall behind the topic.

```bash
kubectl -n "$NS" logs "$POD" -c clickhouse | grep -i "StorageKafka\|kafka" | grep -iE "error|exception" | tail -40
```

```sql
SELECT event, value FROM system.events WHERE event LIKE 'Kafka%' ORDER BY event;
-- Is the materialized view chain still attached?
SELECT database, name, engine FROM system.tables WHERE engine IN ('Kafka','MaterializedView');
```

Usual causes: broker unreachable or auth rotated, a schema mismatch between the topic payload
and the Kafka table (a poison message blocks the partition — `kafka_skip_broken_messages`
bounds it), or the destination table rejecting inserts. Check consumer lag on the broker side
before declaring ClickHouse healthy again.

## ClickHouseKafkaCommitFailures

Offsets are not being committed, so the same messages are re-read after the next rebalance —
duplicate rows downstream — and the consumer group may rebalance in a loop.

```bash
kubectl -n "$NS" logs "$POD" -c clickhouse | grep -i "commit" | tail -30
```

```sql
SELECT event, value FROM system.events WHERE event LIKE 'KafkaCommit%' OR event LIKE 'KafkaRebalance%';
```

Look for a consumer that takes longer than `max.poll.interval.ms` to process a batch (it gets
kicked out of the group before it can commit), broker-side session timeouts, or a destination
table that is slow enough to stall the flush. Reducing `kafka_max_block_size` or raising
`max.poll.interval.ms` usually resolves it; deduplicate downstream with `ReplacingMergeTree`
while it is broken.

---

# clickhouse-operator (control plane)

The alerts below come from the Altinity `clickhouse-operator` metrics endpoint, not from
ClickHouse itself. They tell you whether the operator can converge your
`ClickHouseInstallation` (CHI) objects onto the cluster. **None of them observe query
latency, replication lag, parts, merges, or disk** — if a ClickHouse server is unhealthy
but the operator has nothing to reconcile, every one of these stays silent. Those failure
modes are covered by [ClickHouse server (data plane)](#clickhouse-server-data-plane) above.

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
- [Altinity operator alert rules (upstream)](https://github.com/Altinity/clickhouse-operator/tree/master/deploy/prometheus) —
  the ClickHouse server rules in this repo are adapted from `prometheus-alert-rules-clickhouse.yaml`
- [ClickHouse Keeper operations](https://clickhouse.com/docs/en/guides/sre/keeper/clickhouse-keeper)
- [MergeTree settings (parts_to_delay_insert, parts_to_throw_insert)](https://clickhouse.com/docs/en/operations/settings/merge-tree-settings)

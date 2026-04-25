# Runbook: PostgreSQL

For CNPG-managed PostgreSQL, see also [`cnpg.md`](cnpg.md).

## PostgreSQLDown

```bash
kubectl get pods -l app=postgres
psql -h $HOST -U $USER -c 'SELECT 1'
```

## PostgreSQLTooManyConnections

```sql
SELECT datname, usename, application_name, state, COUNT(*)
FROM pg_stat_activity
GROUP BY 1, 2, 3, 4
ORDER BY 5 DESC;
```

Solutions: add a connection pooler (PgBouncer), raise `max_connections`, fix application-side connection leaks.

## PostgreSQLDeadlockDetected

```sql
SELECT * FROM pg_locks WHERE NOT granted;
```

Review application transaction ordering. Use `SET deadlock_timeout = '500ms'` to detect faster.

## PostgreSQLLongRunningTransaction / PostgreSQLIdleInTransaction

```sql
SELECT pid, usename, state, age(now(), xact_start) AS age, query
FROM pg_stat_activity
WHERE state IN ('active', 'idle in transaction')
  AND xact_start IS NOT NULL
ORDER BY xact_start;

SELECT pg_terminate_backend(<pid>);
```

## PostgreSQLReplicationLag / PostgreSQLReplicationSlotLag

```sql
-- on primary:
SELECT client_addr, state, sent_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- check replication slots:
SELECT slot_name, active, restart_lsn,
       pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_bytes
FROM pg_replication_slots;
```

A slot lag of >1GB means the slot is essentially abandoned. Drop it if confirmed stale: `SELECT pg_drop_replication_slot('name');`

## PostgreSQLHighDiskUsage / PostgreSQLHighWALSize

Resize the PVC, or investigate retained WAL via inactive replication slots.

## PostgreSQLAutovacuumOverdue

A table hasn't been autovacuumed in >12h. Check why:

```sql
SELECT relname, n_dead_tup, n_live_tup, last_autovacuum
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 20;
```

Common: autovacuum is being held up by long-running transactions, or `autovacuum_naptime` is too high.

## PostgreSQLHighCheckpointWriteRatio

Tune `checkpoint_completion_target` (default 0.9), or increase `shared_buffers` and `max_wal_size`.

## PostgreSQLCommitRatioLow

Application is rolling back >5% of transactions. Investigate application errors and deadlocks.

## PgBouncerHighWaitingClients

Client connections are queuing in PgBouncer. Either raise `default_pool_size` / `max_client_conn`, or fix slow queries.

## References

- [PostgreSQL admin docs](https://www.postgresql.org/docs/current/admin.html)
- [PgBouncer config reference](https://www.pgbouncer.org/config.html)

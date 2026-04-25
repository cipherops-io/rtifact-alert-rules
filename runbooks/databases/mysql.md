# Runbook: MySQL

## MySQLDown

```bash
kubectl get pods -l app=mysql
mysqladmin -h $HOST -u $USER -p ping
```

## MySQLTooManyConnections / MySQLHighThreadsRunning

```sql
SHOW PROCESSLIST;
SHOW STATUS LIKE 'Threads%';
SHOW VARIABLES LIKE 'max_connections';
```

Add ProxySQL/MaxScale, fix application connection leaks, or raise `max_connections`.

## MySQLSlowQueries

Enable / inspect the slow query log:

```sql
SHOW VARIABLES LIKE 'slow_query%';
SHOW VARIABLES LIKE 'long_query_time';

-- Use sys schema:
SELECT * FROM sys.statements_with_runtimes_in_95th_percentile LIMIT 10;
```

## MySQLReplicationLag / MySQLReplicationNotRunning

```sql
SHOW REPLICA STATUS\G
-- Look at: Replica_IO_Running, Replica_SQL_Running, Seconds_Behind_Source, Last_Error
```

If stopped due to error:

```sql
STOP REPLICA;
START REPLICA;
-- If it's a specific bad transaction (use carefully):
SET GLOBAL sql_replica_skip_counter = 1;
START REPLICA;
```

## MySQLInnoDBLogWaits

Increase `innodb_log_buffer_size`. Default 16MB; raise to 64MB or more for high-write workloads.

## MySQLHighDiskUsage

Resize the PVC. Inspect tablespace usage:

```sql
SELECT table_schema AS db, table_name,
       ROUND(((data_length + index_length) / 1024 / 1024 / 1024), 2) AS size_gb
FROM information_schema.tables
ORDER BY size_gb DESC LIMIT 10;
```

## MySQLBufferPoolHighUsage

The InnoDB buffer pool is full. Either:
- Increase `innodb_buffer_pool_size` (recommend 70-80% of available RAM for dedicated DB hosts)
- Investigate large queries reading too much data

## MySQLDeadlocks

```sql
SHOW ENGINE INNODB STATUS\G
-- Look for the LATEST DETECTED DEADLOCK section.
```

## MySQLTableLockWaits

Check for `MyISAM` tables (which use table-level locks) — convert to InnoDB.

## MySQLAbortedConnections

Often caused by `max_allowed_packet` being too small for client requests, or network issues.

```sql
SHOW VARIABLES LIKE 'max_allowed_packet';
SHOW STATUS LIKE 'Aborted%';
```

## MySQLLongRunningTransaction

```sql
SELECT trx_id, trx_started, trx_state, trx_query
FROM information_schema.innodb_trx
ORDER BY trx_started;

-- Kill:
KILL <thread_id>;
```

## References

- [MySQL Reference Manual](https://dev.mysql.com/doc/)
- [InnoDB tuning guide](https://dev.mysql.com/doc/refman/8.0/en/innodb-performance.html)

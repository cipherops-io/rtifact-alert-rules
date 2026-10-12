# Runbook: Elasticsearch

## ElasticsearchDown

```bash
curl -s "http://$HOST:9200/_cluster/health?pretty"
```

## ElasticsearchClusterRed

Primary shards are missing — DATA UNAVAILABLE. P0. Find the unallocated shards:

```bash
curl -s "http://$HOST:9200/_cluster/allocation/explain?pretty"
curl -s "http://$HOST:9200/_cat/shards?v" | grep UNASSIGNED
```

Common causes: node permanently lost AND `index.number_of_replicas: 0`. Last-resort recovery: restore from snapshot.

## ElasticsearchClusterYellow

Replica shards are unassigned. Cluster is functional but has no redundancy.

```bash
curl -s "http://$HOST:9200/_cluster/allocation/explain?pretty"
```

## ElasticsearchNodeLeft

A node has dropped from the cluster. Bring it back, or remove it:

```bash
curl -s "http://$HOST:9200/_nodes?pretty"
```

## ElasticsearchJVMHeapHigh / ElasticsearchJVMGCDurationHigh

Heap pressure. Common: too many indices/shards, large fielddata, expensive aggregations. Don't increase heap above 32GB (compressed oops boundary).

## ElasticsearchCircuitBreakerTripped

Elasticsearch protected itself from OOM. Look at which breaker tripped (`fielddata`, `request`, `parent`).

## ElasticsearchDiskWatermarkHigh / Flood

Disk usage above 85% / 95%. At flood-stage, indices go read-only.

```bash
curl -s "http://$HOST:9200/_cat/allocation?v"
# Reset flood-stage flag after cleanup:
curl -X PUT "http://$HOST:9200/_all/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index.blocks.read_only_allow_delete": null}'
```

## ElasticsearchUnassignedShards

```bash
curl -s "http://$HOST:9200/_cat/shards?v" | grep UNASSIGNED
curl -s "http://$HOST:9200/_cluster/allocation/explain?pretty"
# Force allocation (use carefully, can lose data):
curl -X POST "http://$HOST:9200/_cluster/reroute" -H 'Content-Type: application/json' -d '{
  "commands": [
    { "allocate_replica": { "index": "name", "shard": 0, "node": "node-name" } }
  ]
}'
```

## ElasticsearchPendingTasks

Master is overloaded. Reduce churn (fewer index creates/deletes), increase master node resources.

## ElasticsearchSnapshotFailed

```bash
curl -s "http://$HOST:9200/_snapshot/_status?pretty"
```

Common causes: object storage unreachable, missing IAM permissions.

## References

- [Elasticsearch cluster health](https://www.elastic.co/guide/en/elasticsearch/reference/current/cluster-health.html)
- [Sizing and capacity planning](https://www.elastic.co/blog/how-many-shards-should-i-have-in-my-elasticsearch-cluster)

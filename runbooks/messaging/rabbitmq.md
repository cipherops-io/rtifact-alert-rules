# Runbook: RabbitMQ

## RabbitMQDown

```bash
kubectl get pods -l app=rabbitmq
rabbitmqctl status
rabbitmq-diagnostics check_running
```

## RabbitMQQueueDepthHigh / RabbitMQQueueDepthCritical

```bash
rabbitmqctl list_queues name messages messages_ready messages_unacknowledged consumers
```

Either scale consumers, fix consumer-side error rate, or set queue policies (lazy queues, max-length).

## RabbitMQNoConsumers

A queue has messages and zero consumers. Likely the consuming service is down or hasn't reconnected.

## RabbitMQUnackedMessagesHigh

Consumers have prefetched but aren't acking. Either:
- Consumer is stuck/slow
- Consumer is losing connection (unack'd messages get redelivered on disconnect)
- Reduce `prefetch_count` to limit blast radius

## RabbitMQMemoryHigh / RabbitMQMemoryAlarm

P0 if alarm is active — ALL publishing is blocked across the cluster. Either:
- Drain queues by speeding up consumers
- Raise `vm_memory_high_watermark`
- Convert classic queues to lazy queues to push messages to disk

```bash
rabbitmqctl set_vm_memory_high_watermark 0.6
```

## RabbitMQDiskFreeAlarm / RabbitMQDiskFreeWarning

Same publishing block as memory alarm if active. Free disk or move data dir.

## RabbitMQNodeDown

Cluster member down. Check pod status, restart if needed. For a permanently lost node:

```bash
rabbitmqctl forget_cluster_node $NODE
```

## RabbitMQNetworkPartition

P0. Cluster split-brain. Manual intervention required:

```bash
rabbitmqctl cluster_status
# Pick the authoritative side, restart the minority partition.
```

Configure `cluster_partition_handling` (recommend `pause_minority`).

## RabbitMQChannelCountHigh / RabbitMQConnectionCountHigh

Likely a client leak. Find the offender:

```bash
rabbitmqctl list_connections user peer_host channels state | sort -k 3 -n -r | head
```

## RabbitMQDeadLetterQueueGrowing

Consumers are rejecting/timing out. Inspect the DLQ contents to understand the failure pattern.

## RabbitMQRedeliveryRateHigh

Consumers are nacking or disconnecting before acking. Investigate consumer error logs.

## References

- [RabbitMQ production checklist](https://www.rabbitmq.com/production-checklist.html)
- [RabbitMQ networking & partitions](https://www.rabbitmq.com/clustering.html#network-partitions)

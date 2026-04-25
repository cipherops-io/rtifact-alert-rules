# Runbook: Apache Kafka

## KafkaBrokerDown

```bash
kubectl get pods -l app=kafka
# From a debug pod with kafka tools:
kafka-broker-api-versions.sh --bootstrap-server $BROKER:9092
```

## KafkaUnderReplicatedPartitions

A partition does not have all its replicas in-sync. Common cause: a broker is slow or has just restarted.

```bash
kafka-topics.sh --bootstrap-server $BROKER:9092 --describe \
  --under-replicated-partitions
```

## KafkaOfflinePartitions

P0. Some partitions are unavailable for read/write. Indicates ALL replicas are down.

```bash
kafka-topics.sh --bootstrap-server $BROKER:9092 --describe --unavailable-partitions
```

Bring the relevant brokers back online. If permanent, use unclean leader election (data loss possible) as last resort.

## KafkaConsumerGroupLagHigh / KafkaConsumerGroupLagCritical

```bash
kafka-consumer-groups.sh --bootstrap-server $BROKER:9092 --describe --group $GROUP
```

Either scale consumers, or fix consumer slowness.

## KafkaConsumerGroupLagGrowing

The consumer is permanently falling behind. Investigate consumer code: are they doing slow IO per message? Should processing be batched or async?

## KafkaLeaderElectionRateHigh

Frequent leader changes = broker instability. Check broker JVM (GC pauses), disk I/O, network.

## KafkaISRShrinkRateHigh

Replicas are falling out of in-sync. Causes: replica I/O slow, network slow between brokers.

## KafkaDiskUsageHigh

Resize the broker PVC. Reduce `log.retention.bytes` or `log.retention.hours` for high-volume topics.

## KafkaNetworkProcessorIdleLow / KafkaRequestHandlerIdleLow

Broker is overloaded. Increase `num.network.threads` and `num.io.threads`, or scale brokers.

## KafkaProducerRequestErrorRateHigh

Producers are hitting errors. Common: ACL misconfiguration, network blip, broker overload.

## KafkaLogFlushLatencyHigh

Disk I/O bottleneck. Use SSD/NVMe. Avoid network-attached storage for Kafka data.

## KafkaActiveControllerCountAbnormal

P0. Either no controller (cluster broken) or split-brain (data corruption risk).

```bash
# Force re-election (CAREFUL):
zookeeper-shell.sh $ZK:2181 deleteall /controller
# In KRaft mode:
kafka-metadata-shell.sh
```

## References

- [Apache Kafka operations](https://kafka.apache.org/documentation/#operations)
- [Confluent monitoring guide](https://docs.confluent.io/platform/current/kafka/monitoring.html)

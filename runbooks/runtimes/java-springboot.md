# Runbook: Java / Spring Boot

These alerts assume Micrometer is exposing JVM and HTTP metrics via Prometheus.

## SpringBootAppDown

```bash
kubectl get pods -l app=$APP
curl -s http://$APP:$PORT/actuator/health
kubectl logs -l app=$APP --tail=200
```

## SpringBootHighErrorRate

5xx rate >1%. Inspect logs and trace IDs:

```bash
kubectl logs -l app=$APP --tail=1000 | grep -E 'ERROR|WARN|Exception'
```

## SpringBootHighResponseTime

p99 latency >2s. Use APM (e.g., OpenTelemetry, NewRelic) traces or thread dumps to find the slow span:

```bash
kubectl exec -it $POD -- jstack 1 > /tmp/thread-dump.txt
```

## SpringBootJVMHeapHigh

Heap >85%. Heap dump for analysis:

```bash
kubectl exec -it $POD -- jcmd 1 GC.heap_dump /tmp/heap.hprof
kubectl cp $POD:/tmp/heap.hprof ./heap.hprof
# Open with Eclipse MAT or VisualVM
```

## SpringBootJVMGCPauseHigh

GC pause >1s. Switch to G1 or ZGC, increase heap if undersized.

## SpringBootThreadPoolExhausted

Tomcat pool >95% used. Either:
- Slow downstream calls (find with thread dump)
- Sudden traffic burst (add HPA on requests-per-second)
- Increase `server.tomcat.threads.max`

## SpringBootDBConnectionPoolExhausted

HikariCP pool exhausted. Investigate slow queries blocking connections, or raise pool size:

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 50
```

## SpringBootCircuitBreakerOpen

Resilience4j circuit breaker open. Check the downstream service. Adjust `failureRateThreshold` if too sensitive.

## SpringBootKafkaConsumerLagHigh

Consumer not keeping up. Scale consumers (each topic-partition can be served by at most one consumer per group).

## SpringBootHighCPUUsage

```bash
kubectl exec -it $POD -- top -H -p 1     # find hot threads
kubectl exec -it $POD -- jstack 1
```

Match the high-CPU thread IDs (`top -H` shows them in decimal; convert to hex to match `jstack`).

## SpringBootScheduledJobFailed

Spring Batch job failures. Inspect `BATCH_JOB_EXECUTION` and `BATCH_STEP_EXECUTION` tables.

## SpringBootActuatorHealthDegraded

A health indicator (`db`, `redis`, `kafka`, etc.) is DOWN. Check that specific dependency.

## SpringBootHighRejectedTasks

Executor service is rejecting submitted tasks — thread pool full and queue full. Increase pool/queue sizes.

## References

- [Spring Boot Actuator](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html)
- [Micrometer reference](https://micrometer.io/docs/)

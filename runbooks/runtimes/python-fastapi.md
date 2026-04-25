# Runbook: Python / FastAPI

These alerts assume `prometheus_client` and `prometheus-fastapi-instrumentator` (or similar) are exposing metrics.

## FastAPIAppDown

```bash
kubectl get pods -l app=$APP
curl -s http://$APP:$PORT/health
kubectl logs -l app=$APP --tail=200
```

## FastAPIHighErrorRate / FastAPIErrorRateCritical

5xx rate elevated. Common causes: dependency failure, unhandled exception in async handler, validation error.

```bash
kubectl logs -l app=$APP --tail=500 | grep -E 'ERROR|Exception|Traceback'
```

## FastAPIHighResponseTime

p99 >2s. Often: blocking sync code in an async handler. Use [`py-spy`](https://github.com/benfred/py-spy) to profile:

```bash
kubectl exec -it $POD -- py-spy dump --pid 1
kubectl exec -it $POD -- py-spy top --pid 1
```

## FastAPIHighCPUUsage

CPU >80%. As above — check for blocking sync calls (DB drivers without async support, requests instead of httpx, etc.).

## FastAPIDBConnectionPoolExhausted

SQLAlchemy pool exhausted. Either fix slow queries or raise pool size:

```python
engine = create_async_engine(URL, pool_size=20, max_overflow=20)
```

## FastAPIKafkaConsumerLagHigh

Scale consumer instances (topic-partition mapping rules apply).

## FastAPIBackgroundTaskFailing

Celery task error rate elevated.

```bash
celery -A app inspect active
celery -A app inspect stats
celery flower  # web UI for inspection
```

## FastAPIHighOpenConnections

File descriptor leak. Use `lsof` from inside the container:

```bash
kubectl exec -it $POD -- ls -1 /proc/1/fd | wc -l
```

Common cause: not closing httpx/requests sessions.

## References

- [FastAPI docs](https://fastapi.tiangolo.com/)
- [py-spy profiler](https://github.com/benfred/py-spy)
- [SQLAlchemy connection pool](https://docs.sqlalchemy.org/en/20/core/pooling.html)

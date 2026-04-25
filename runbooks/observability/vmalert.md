# Runbook: vmalert

vmalert evaluates Prometheus alerting and recording rules against a VictoriaMetrics datasource and forwards firing alerts to Alertmanager.

## VMAlertDown

```bash
kubectl get pods -l app=vmalert
curl -s http://$VMALERT:8880/health
```

While vmalert is down, alerts will not fire and recording rules will not produce new samples.

## VMAlertConfigReloadFailed

A rule file is invalid. Check the logs:

```bash
kubectl logs -l app=vmalert --tail=200 | grep -i 'reload\|invalid\|error'
# Validate locally:
vmalert -dryRun -rule=./your-rule.yaml
```

## VMAlertRuleEvaluationErrors

Some rule group is failing evaluation. Common causes: PromQL/MetricsQL incompatibility, missing metric, datasource error.

```bash
curl -s "http://$VMALERT:8880/api/v1/groups" | jq '.data.groups[] | select(.lastError != "") | {name: .name, error: .lastError}'
```

## VMAlertRemoteWriteErrors

vmalert writes recording-rule results back to a remote-write endpoint. If failing, recording rules' outputs are lost.

## VMAlertNotifierErrors

vmalert cannot deliver alerts to Alertmanager. Check Alertmanager health and the `-notifier.url` configuration.

```bash
kubectl exec -it $POD -- curl -v $ALERTMANAGER_URL/api/v2/status
```

## VMAlertRuleEvaluationSlow

A rule group takes >5s on average to evaluate. Optimize the heaviest expressions:

```bash
curl -s "http://$VMALERT:8880/api/v1/groups" | jq '.data.groups[] | {name: .name, lastEvalDur: .lastEvaluationDuration}'
```

## References

- [vmalert docs](https://docs.victoriametrics.com/vmalert/)
- [vmalert dryRun and unittest](https://docs.victoriametrics.com/vmalert/#tests)

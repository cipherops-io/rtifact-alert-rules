# Default log-based alert rules (future)

Place rule files here using the same layout as metrics:

```
logs/<category>/<name>.yml
```

When `defaultRules.logs.enabled` is `true` in `values.yaml`, the chart bundles  
`default-alert-rules/logs/*/*.yml` into a ConfigMap and mounts it on the **logs**
vmalert container at `/default-rules/` with `-rule=/default-rules/*.yml`.

This directory is intentionally empty until log-alert rules are curated.

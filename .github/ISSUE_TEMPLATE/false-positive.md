---
name: False positive report
about: An existing alert fires on a healthy system
title: "[false-positive] <alert name>"
labels: bug
---

## Alert name

<!-- e.g. CNPGClusterHighDiskUsage -->

## Tech stack and exporter version

<!-- e.g. cloudnative-pg 1.24.0 -->

## What did the alert fire on?

<!-- paste the firing labels and value -->

```
labels: { ... }
value: ...
```

## Why is this a false positive?

<!-- explain why the system is actually healthy -->

## Proposed fix

<!-- new expression, different threshold, longer 'for' duration, etc. -->

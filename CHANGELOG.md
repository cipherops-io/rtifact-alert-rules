# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial repo structure with rules across kubernetes, gitops, databases, messaging, caching, observability, ingress, runtimes
- 17 migrated rule files: argocd, cnpg, postgresql, mysql, mongodb, redis, elasticsearch, clickhouse, kafka, rabbitmq, memcached, prometheus, loki, etcd, kubernetes-workloads, java-springboot, python-fastapi
- Gap-fill rule files: apiserver, coredns, kubelet, node-exporter, kube-state-metrics, nginx-ingress, alertmanager, grafana, prometheus-operator, victoriametrics, vmagent, vmalert
- `make lint test validate catalog all` Makefile targets
- Label-contract validator (`scripts/validate_labels.py`)
- Catalog generator (`scripts/generate_catalog.py`)
- GitHub Actions workflows for lint, unit tests, label contract
- Sample unit tests for cnpg, kafka, redis, kubernetes-workloads
- One runbook per `tech_stack` (skeleton format)

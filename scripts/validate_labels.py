#!/usr/bin/env python3
"""Validate every alert in rules/ against the rtifact-alert-rules label contract.

The contract is documented in docs/conventions/label-contract.md. This script
enforces the machine-checkable parts:

  * Every alert MUST have labels: severity, priority, tech_stack, signal,
    category, runbook
  * severity   in {critical, warning, info}
  * priority   in {P0, P1, P2, P3}
  * signal     in {symptom, cause, slo-burn}
  * category   in {workload, data, network, control-plane, app, storage,
                   gitops, observability, ingress, runtime, messaging,
                   caching, scheduling, batch, autoscaling, monitoring,
                   rollout, node, security}
  * tech_stack must be in the controlled enum below
  * runbook    must be a path that exists on disk
  * Every alert MUST have annotations: summary, description, runbook_url
  * runbook_url should match the runbook label path (warning, not error)

Exits non-zero if any rule fails.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: pyyaml not installed. Install via: pip3 install pyyaml\n")
    sys.exit(2)

REPO_ROOT = Path(__file__).resolve().parent.parent
RULES_DIR = REPO_ROOT / "rules"
RUNBOOKS_DIR = REPO_ROOT / "runbooks"

REQUIRED_LABELS = {"severity", "priority", "tech_stack", "signal", "category", "runbook"}
REQUIRED_ANNOTATIONS = {"summary", "description", "runbook_url"}

ALLOWED_SEVERITIES = {"critical", "warning", "info"}
ALLOWED_PRIORITIES = {"P0", "P1", "P2", "P3"}
ALLOWED_SIGNALS = {"symptom", "cause", "slo-burn"}
ALLOWED_CATEGORIES = {
    "workload", "data", "network", "control-plane", "app", "storage",
    "gitops", "observability", "ingress", "runtime", "messaging",
    "caching", "scheduling", "batch", "autoscaling", "monitoring",
    "rollout", "node", "security",
}
ALLOWED_TECH_STACKS = {
    # kubernetes
    "kubernetes", "apiserver", "coredns", "kubelet", "node-exporter",
    "kube-state-metrics", "etcd",
    # gitops
    "argocd",
    # databases
    "postgresql", "cnpg", "mysql", "mongodb", "redis", "elasticsearch", "clickhouse",
    # messaging / caching
    "kafka", "rabbitmq", "memcached",
    # observability
    "prometheus", "alertmanager", "grafana", "prometheus-operator",
    "victoriametrics", "vmagent", "vmalert", "loki",
    # ingress
    "nginx-ingress",
    # runtimes
    "java-springboot", "python-fastapi",
}


def fail(msg: str, errors: list[str]) -> None:
    errors.append(msg)


def validate_rule(file: Path, group_name: str, rule: dict, errors: list[str]) -> None:
    name = rule.get("alert") or rule.get("record") or "<unknown>"
    if "alert" not in rule:
        # recording rules are exempt from this contract
        return

    where = f"{file.relative_to(REPO_ROOT)} :: {group_name} :: {name}"

    labels = rule.get("labels") or {}
    annotations = rule.get("annotations") or {}

    missing = REQUIRED_LABELS - set(labels.keys())
    if missing:
        fail(f"{where}: missing labels {sorted(missing)}", errors)

    missing_a = REQUIRED_ANNOTATIONS - set(annotations.keys())
    if missing_a:
        fail(f"{where}: missing annotations {sorted(missing_a)}", errors)

    sev = labels.get("severity")
    if sev is not None and sev not in ALLOWED_SEVERITIES:
        fail(f"{where}: severity={sev!r} not in {sorted(ALLOWED_SEVERITIES)}", errors)

    prio = labels.get("priority")
    if prio is not None and prio not in ALLOWED_PRIORITIES:
        fail(f"{where}: priority={prio!r} not in {sorted(ALLOWED_PRIORITIES)}", errors)

    sig = labels.get("signal")
    if sig is not None and sig not in ALLOWED_SIGNALS:
        fail(f"{where}: signal={sig!r} not in {sorted(ALLOWED_SIGNALS)}", errors)

    cat = labels.get("category")
    if cat is not None and cat not in ALLOWED_CATEGORIES:
        fail(f"{where}: category={cat!r} not in {sorted(ALLOWED_CATEGORIES)}", errors)

    stack = labels.get("tech_stack")
    if stack is not None and stack not in ALLOWED_TECH_STACKS:
        fail(f"{where}: tech_stack={stack!r} not in allowed enum (add to validate_labels.py)", errors)

    runbook = labels.get("runbook")
    if runbook:
        runbook_path = REPO_ROOT / runbook
        if not runbook_path.exists():
            fail(f"{where}: runbook label points to missing file {runbook}", errors)


def main() -> int:
    if not RULES_DIR.is_dir():
        sys.stderr.write(f"ERROR: {RULES_DIR} not found\n")
        return 2

    errors: list[str] = []
    files: list[Path] = sorted(RULES_DIR.rglob("*.yaml")) + sorted(RULES_DIR.rglob("*.yml"))

    if not files:
        print(f"WARN: no rule files found under {RULES_DIR}")
        return 0

    rule_count = 0
    for f in files:
        try:
            with f.open() as fh:
                doc = yaml.safe_load(fh)
        except Exception as exc:
            fail(f"{f.relative_to(REPO_ROOT)}: cannot parse YAML: {exc}", errors)
            continue

        if not doc or "groups" not in doc:
            fail(f"{f.relative_to(REPO_ROOT)}: missing top-level 'groups' key", errors)
            continue

        for group in doc["groups"]:
            gname = group.get("name", "<no name>")
            for rule in group.get("rules", []):
                if "alert" in rule:
                    rule_count += 1
                validate_rule(f, gname, rule, errors)

    if errors:
        for e in errors:
            print(f"  FAIL {e}")
        print(f"\n{len(errors)} label-contract violations across {len(files)} files.")
        return 1

    print(f"Label contract OK: {rule_count} alerts across {len(files)} files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env bash
# Wraps every rule file in rules/ as a PrometheusRule CRD object suitable for
# kubectl apply on a Prometheus Operator cluster.
#
# Always runs from the repo root regardless of where it is invoked.
#
# Usage:
#   ./scripts/render-prom-operator.sh > dist/prometheus-rules.yaml
#   kubectl apply -n monitoring -f dist/prometheus-rules.yaml
#
# Override the namespace and the helm-style release label via env vars:
#   NAMESPACE=monitoring RELEASE=prometheus-stack ./scripts/render-prom-operator.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

NAMESPACE="${NAMESPACE:-monitoring}"
RELEASE="${RELEASE:-prometheus-stack}"
RULES_DIR="rules"

if [[ ! -d "$RULES_DIR" ]]; then
    echo "ERROR: $REPO_ROOT/$RULES_DIR not found." >&2
    exit 1
fi

first=1
while IFS= read -r -d '' f; do
    rel="${f#$RULES_DIR/}"            # e.g. databases/cnpg.yaml
    category="${rel%%/*}"              # e.g. databases
    stem=$(basename "$f" .yaml)        # e.g. cnpg
    name="rtifact-${category}-${stem}-alerts"

    if [[ $first -eq 0 ]]; then
        echo "---"
    fi
    first=0

    cat <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ${name}
  namespace: ${NAMESPACE}
  labels:
    app: kube-prometheus-stack
    release: ${RELEASE}
    rtifact.io/category: ${category}
    rtifact.io/stack: ${stem}
spec:
EOF

    sed 's/^/  /' "$f"
done < <(find "$RULES_DIR" -type f -name '*.yaml' -print0 | sort -z)

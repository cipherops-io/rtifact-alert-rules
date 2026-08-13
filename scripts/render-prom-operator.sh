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
    # Layout is rules/<source_type>/<category>/<stack>.yml, e.g.
    # rules/metrics/databases/cnpg.yml -> source_type=metrics, category=databases.
    rel="${f#$RULES_DIR/}"             # e.g. metrics/databases/cnpg.yml
    source_type="${rel%%/*}"           # e.g. metrics
    category="$(basename "$(dirname "$f")")"   # e.g. databases
    stem="$(basename "$f")"
    stem="${stem%.yml}"
    stem="${stem%.yaml}"               # e.g. cnpg
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
    rtifact.io/source-type: ${source_type}
spec:
EOF

    # awk (not sed) so a rule file with no trailing newline still ends with one —
    # otherwise the next document's "---" separator is glued onto its last line.
    awk '{ print "  " $0 }' "$f"
done < <(find "$RULES_DIR" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | sort -z)

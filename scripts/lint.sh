#!/usr/bin/env bash
# Lints every rule file in rules/ with promtool check rules.
# Optionally runs yamllint if available.
#
# Always runs from the repo root regardless of where it is invoked.
# Ignores any RULES_DIR / TESTS_DIR env vars so a stale shell var
# from another tool can't hijack the directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

RULES_DIR="rules"
RC=0

if [[ ! -d "$RULES_DIR" ]]; then
    echo "ERROR: $REPO_ROOT/$RULES_DIR not found."
    exit 1
fi

echo "==> Running promtool check rules on $RULES_DIR (cwd=$REPO_ROOT)"
files=()
while IFS= read -r -d '' f; do
    files+=("$f")
done < <(find "$RULES_DIR" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)

if [[ ${#files[@]} -eq 0 ]]; then
    echo "WARN: no rule files found under $RULES_DIR"
    exit 0
fi

for f in "${files[@]}"; do
    if promtool check rules "$f" >/dev/null 2>&1; then
        printf '  OK   %s\n' "$f"
    else
        printf '  FAIL %s\n' "$f"
        promtool check rules "$f" || true
        RC=1
    fi
done

if command -v yamllint >/dev/null 2>&1; then
    echo ""
    echo "==> Running yamllint on $RULES_DIR"
    yamllint -c .yamllint "$RULES_DIR" || RC=1
else
    echo ""
    echo "(yamllint not installed; skipping. Install via: brew install yamllint)"
fi

if [[ $RC -ne 0 ]]; then
    echo ""
    echo "Lint FAILED."
    exit $RC
fi

echo ""
echo "Lint OK (${#files[@]} files)."

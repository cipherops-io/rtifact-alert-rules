#!/usr/bin/env bash
# Runs promtool test rules on every *_test.yaml file in the tests/ directory.
# Each test file references the rule files it tests via relative paths.
#
# Always cds to the repo root regardless of where this script is invoked from.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

DIR="tests"
RC=0

if [[ ! -d "$DIR" ]]; then
    echo "ERROR: $REPO_ROOT/$DIR not found."
    exit 1
fi

echo "==> Running promtool test rules on $DIR (cwd=$REPO_ROOT)"
files=()
while IFS= read -r -d '' f; do
    files+=("$f")
done < <(find "$DIR" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)

if [[ ${#files[@]} -eq 0 ]]; then
    echo "WARN: no test files found under $DIR"
    exit 0
fi

for f in "${files[@]}"; do
    echo ""
    echo "  Testing $f"
    if promtool test rules "$f"; then
        printf '  OK   %s\n' "$f"
    else
        printf '  FAIL %s\n' "$f"
        RC=1
    fi
done

if [[ $RC -ne 0 ]]; then
    echo ""
    echo "Tests FAILED."
    exit $RC
fi

echo ""
echo "All tests passed (${#files[@]} files)."

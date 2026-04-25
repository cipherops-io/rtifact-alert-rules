# Contributing to rtifact-alert-rules

Thanks for considering a contribution. This project is opinionated about quality, so the bar is intentionally high. Please read this before opening a PR.

## What we accept

- New rules for **standard, widely-deployed** technologies (no proprietary or niche products without a strong case)
- Improvements to existing rules: better expressions, fewer false positives, more accurate `for` durations
- New runbooks or improvements to existing ones
- Test cases (always welcome — coverage is currently low)
- Bug fixes for broken expressions, deprecated metric names, etc.

## What we don't accept (yet)

- "Awesome lists"-style additions where the rule has not been tested against real metrics
- Rules without a runbook
- Rules without at least one unit test
- Application-specific rules (your-company's-checkout-service alerts) — those belong in your private repo

## The non-negotiable checklist

Every PR that adds or modifies a rule MUST:

1. **Pass the label contract.** Each alert has all six required labels (`severity`, `priority`, `tech_stack`, `signal`, `category`, `runbook`) and three required annotations (`summary`, `description`, `runbook_url`).
2. **Point at a runbook.** The `runbook` label and `runbook_url` annotation must reference a real file under `runbooks/`. CI validates this.
3. **Have at least one unit test.** Add to `tests/<category>/<stack>_test.yaml`. Cover at least:
   - One positive case (the alert SHOULD fire given input series)
   - One negative case (the alert SHOULD NOT fire given input series)
4. **Pass `make all` locally.** This runs `make lint test validate catalog`.
5. **Update the catalog.** Run `make catalog` and commit the regenerated `docs/catalog.md`.

## Workflow

```bash
# 1. Fork and clone
git clone https://github.com/<you>/rtifact-alert-rules.git
cd rtifact-alert-rules

# 2. Install tools
brew install prometheus            # provides promtool
brew install yamllint              # optional, recommended
pip3 install pyyaml                # for the validators

# 3. Make your change in rules/<category>/<stack>.yaml

# 4. Add tests in tests/<category>/<stack>_test.yaml

# 5. Add or update the runbook in runbooks/<category>/<stack>.md

# 6. Run all checks
make all

# 7. Commit and open a PR
```

## Writing good alert rules

Read [`docs/conventions/label-contract.md`](docs/conventions/label-contract.md) and [`docs/conventions/severity-tiers.md`](docs/conventions/severity-tiers.md) before authoring.

Quick reminders:

- **Symptom over cause.** Alert on what the user feels (high error rate, high latency), not internal state (high CPU). Cause alerts are useful but should usually be `warning`, not `critical`.
- **`for` durations matter.** A flap in a 30s metric should not page someone. Use `for: 5m` minimum for warnings, `for: 1m` minimum for criticals.
- **Avoid `up == 0` traps.** When the target stops being scraped, `up` doesn't exist. Prefer `absent_over_time(up{job="..."}[5m])` for "gone missing" semantics.
- **Avoid label cardinality bombs.** Don't put `pod`, `instance`, or `id` in `labels:` on the rule itself — only on the metric selector. The labels block is for routing.
- **Don't use deprecated metric names.** Check the upstream exporter's CHANGELOG.

## Reporting false positives

If a rule fires on healthy systems, please open an issue with:
- The rule name
- The expression result (`promtool query instant ...` output)
- The labels of the offending series
- Your version of the underlying exporter

We treat false positives as bugs, not feature requests.

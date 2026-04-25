.PHONY: help lint test validate catalog clean all check-tools

# Default target shows help.
help:
	@echo "rtifact-alerts — production-grade Prometheus alert rules"
	@echo ""
	@echo "Targets:"
	@echo "  make check-tools   Verify promtool, yamllint are installed"
	@echo "  make lint          Run promtool check rules + yamllint on all rule files"
	@echo "  make test          Run promtool test rules on all unit tests in tests/"
	@echo "  make validate      Run the label-contract validator on all rule files"
	@echo "  make catalog       Regenerate docs/catalog.md from rule files"
	@echo "  make all           lint + test + validate + catalog"
	@echo "  make clean         Remove generated artifacts (dist/)"

check-tools:
	@command -v promtool >/dev/null 2>&1 || { echo >&2 "ERROR: promtool not found. Install via: brew install prometheus"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo >&2 "ERROR: python3 not found"; exit 1; }
	@echo "Tools OK: $$(promtool --version 2>&1 | head -1)"

lint: check-tools
	@bash scripts/lint.sh

test: check-tools
	@bash scripts/test.sh

validate: check-tools
	@python3 scripts/validate_labels.py

catalog: check-tools
	@python3 scripts/generate_catalog.py > docs/catalog.md
	@echo "Wrote docs/catalog.md ($$(wc -l < docs/catalog.md) lines)"

clean:
	rm -rf dist/

all: lint validate test catalog
	@echo ""
	@echo "All checks passed."

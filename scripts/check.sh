#!/bin/bash
# scripts/check.sh: Run repository documentation checks, tests, and unslop scan.
# Matches .github/workflows/lint-docs.yml. Runs every step and reports status. Refs claude-kit#55.
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

failed_steps=()

echo "=== 1. lint-skill-docs"
if bash plugins/kit/scripts/lint-skill-docs.sh; then
  echo "PASS: lint-skill-docs"
else
  echo "FAIL: lint-skill-docs"
  failed_steps+=("lint-skill-docs")
fi
echo

echo "=== 2. hook tests (run-all)"
if bash plugins/kit/hooks/tests/run-all.sh; then
  echo "PASS: hook tests (run-all)"
else
  echo "FAIL: hook tests (run-all)"
  failed_steps+=("hook tests (run-all)")
fi
echo

echo "=== 3. unslop-check (report-only)"
if bash plugins/kit/scripts/unslop-check.sh; then
  echo "PASS: unslop-check"
else
  echo "FAIL: unslop-check"
  failed_steps+=("unslop-check")
fi
echo

if [ "${#failed_steps[@]}" -eq 0 ]; then
  echo "All checks passed. Note: unslop-check is report-only; hit count is information, not a gate."
  exit 0
else
  echo "Checks failed: ${failed_steps[*]}. Note: unslop-check is report-only; hit count is information, not a gate."
  exit 1
fi

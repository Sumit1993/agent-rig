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

echo "=== 4. length caps"
# Cap dotfiles/AGENTS.md at 80 and skills at 150; autofix is vendored. Refs #123
caps_failed=0

if [ -f "dotfiles/AGENTS.md" ]; then
  agents_lines=$(wc -l < "dotfiles/AGENTS.md" | tr -d ' ')
  if [ "$agents_lines" -gt 80 ]; then
    echo "dotfiles/AGENTS.md: $agents_lines lines (cap 80)"
    caps_failed=1
  fi
fi

for skill_file in plugins/kit/skills/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  case "$skill_file" in
    */autofix/SKILL.md) continue ;;
  esac
  lines=$(wc -l < "$skill_file" | tr -d ' ')
  if [ "$lines" -gt 150 ]; then
    echo "$skill_file: $lines lines (cap 150)"
    caps_failed=1
  fi
done

if [ "$caps_failed" -eq 0 ]; then
  echo "PASS: length caps"
else
  echo "FAIL: length caps"
  failed_steps+=("length caps")
fi
echo

if [ "${#failed_steps[@]}" -eq 0 ]; then
  echo "All checks passed. Note: unslop-check is report-only; hit count is information, not a gate."
  exit 0
else
  echo "Checks failed: ${failed_steps[*]}. Note: unslop-check is report-only; hit count is information, not a gate."
  exit 1
fi

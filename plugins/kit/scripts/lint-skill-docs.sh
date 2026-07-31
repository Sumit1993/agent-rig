#!/bin/bash
# lint-skill-docs.sh — skills and dotfiles docs carry present-tense facts and
# procedures only: no dates, no event narrative. Git history owns provenance.
# Exits 1 with the offending lines when a marker is found.
set -u
root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$(cd "$(dirname "$0")/../../.." && pwd)
pattern='20[0-9]{2}-[0-9]{2}-[0-9]{2}|found live|last session|we learned|earlier attempt'
hits=$(grep -rnE "$pattern" "$root"/plugins/*/skills/*/SKILL.md "$root"/dotfiles/CLAUDE.md 2>/dev/null || true)
if [ -n "$hits" ]; then
  echo "doc lint: narrative/date markers found — state the constraint, leave provenance to git history:"
  echo "$hits"
  exit 1
fi
echo "doc lint: clean"

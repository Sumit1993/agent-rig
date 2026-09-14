#!/bin/bash
# lint-skill-docs.sh — skills and dotfiles docs carry present-tense facts and
# procedures only: no dates, no event narrative. Git history owns provenance.
# Fenced code blocks are exempt: an example log row or transcript is data, not prose.
# Exits 1 with the offending lines when a marker is found.
set -u
root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$(cd "$(dirname "$0")/../../.." && pwd)
pattern='20[0-9]{2}-[0-9]{2}-[0-9]{2}|found live|last session|we learned|earlier attempt'

hits=""
for f in "$root"/plugins/*/skills/*/SKILL.md "$root"/dotfiles/AGENTS.md; do
  [ -f "$f" ] || continue
  found=$(awk '/^[[:space:]]*```/ {fence = !fence; print ""; next} {print (fence ? "" : $0)}' "$f" \
    | grep -nE "$pattern" | sed "s#^#$f:#") || true
  [ -n "$found" ] && hits="${hits}${found}"$'\n'
done

if [ -n "${hits// /}" ] && [ "$hits" != $'\n' ]; then
  echo "doc lint: narrative/date markers found — state the constraint, leave provenance to git history:"
  printf '%s' "$hits"
  exit 1
fi
echo "doc lint: clean"

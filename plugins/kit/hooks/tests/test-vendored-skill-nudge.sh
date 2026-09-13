#!/bin/bash
# Regression suite for vendored-skill-nudge.sh (PreToolUse Skill). Refs #123.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/vendored-skill-nudge.sh"
fails=0

got=$(printf 'not json' | "$HOOK" >/dev/null 2>&1; echo $?)
case "$got" in
  0|2) echo "PASS: junk stdin exits $got" ;;
  *) echo "FAIL: junk stdin rc=$got"; fails=$((fails + 1)) ;;
esac

check_match() {
  local skill=$1 out rc ctx
  out=$(jq -n --arg s "$skill" '{"tool_input":{"skill":$s}}' | "$HOOK")
  rc=$?
  ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
  if [ "$rc" -eq 0 ] && grep -q 'umbrella' <<<"$ctx"; then
    echo "PASS: $skill fires with umbrella"
  else
    echo "FAIL: $skill (rc=$rc, ctx=$ctx)"; fails=$((fails + 1))
  fi
}

check_silent() {
  local skill=$1 out rc
  out=$(jq -n --arg s "$skill" '{"tool_input":{"skill":$s}}' | "$HOOK")
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    echo "PASS: $skill silent"
  else
    echo "FAIL: $skill (rc=$rc, out=$out)"; fails=$((fails + 1))
  fi
}

check_match "mattpocock-skills:handoff"
check_match "claude-handoff"
check_match "x:to-tickets"
check_match "mattpocock-skills:research"

out=$(jq -n '{"tool_input":{"skill":"claude-api"}}' | "$HOOK"); ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -q 'shared/models.md' <<<"$ctx"; then echo "PASS: claude-api fires with models.md pointer"; else echo "FAIL: claude-api (ctx=$ctx)"; fails=$((fails + 1)); fi

check_silent "kit:farm-out"
check_silent "researcher"

[ "$fails" -eq 0 ] && echo && echo "all vendored-skill-nudge hook tests passed"
exit "$fails"

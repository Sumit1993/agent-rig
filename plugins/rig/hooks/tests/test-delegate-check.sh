#!/bin/bash
# Regression suite for delegate-check.sh (PreToolUse Agent).
# Blocks a generic subagent on mechanical work; passes everything else.
#
# Cases marked "real" come from replay-transcripts.sh against this machine's own
# transcripts, where matching the prompt instead of the description blocked 52% of
# genuine Agent calls. Keep them: they are what holds the hook to precision.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/delegate-check.sh"
fails=0

check() { # name expected_rc json
  local name=$1 want=$2 json=$3 got
  printf '%s' "$json" | "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (want rc=$want, got rc=$got)"; fails=$((fails + 1))
  fi
}

echo "-- blocked: mechanical execution, named as such"
check "write tests for the parser" 2 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"write tests for the parser","prompt":"to spec"}}'
check "run tests without 'the'" 2 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"Run tests for the parser","prompt":"go"}}'
check "run suite" 2 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"run suite and report failures","prompt":"go"}}'
check "missing subagent_type still counts as generic" 2 \
  '{"tool_input":{"description":"Collect evidence from the CI logs"}}'
check "rebase work" 2 \
  '{"tool_input":{"subagent_type":"claude","description":"Rebase onto main","prompt":"do it"}}'
check "migration work" 2 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"Migrate the fixtures to v2"}}'

echo "-- allowed: judgment, or agy already considered"
check "implementing to spec" 0 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"Implement the parser","prompt":"to spec"}}'
check "naming agy is the escape hatch" 0 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"Implement the parser","prompt":"agy quota is dry"}}'
check "antigravity also counts as considered" 0 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"Implement the parser","prompt":"antigravity was down"}}'
check "agy-runner is never blocked" 0 \
  '{"tool_input":{"subagent_type":"agy-runner","prompt":"run ~/ai-context/agy-prompts/x.md"}}'
check "purpose-built agents encode their own routing" 0 \
  '{"tool_input":{"subagent_type":"fable-planner","description":"Implement to spec"}}'
check "judgment work is not delegable" 0 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"Adjudicate two conflicting reviews"}}'
check "malformed input never blocks" 0 'not json at all'

echo "-- real: shapes that a prompt-matching version blocked wrongly"
check "mechanical verb buried in a long prompt" 0 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"Verify shipped features","prompt":"check whether the docs implement what the ADR describes and rebase if stale"}}'
check "verification reads as judgment" 0 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"Validate stale SCHEMA.md finding"}}'
check "research is not on the block list" 0 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"Competitive surface research"}}'
check "mapping a surface is not mechanical" 0 \
  '{"tool_input":{"subagent_type":"general-purpose","description":"Map full UI surface"}}'

# Guard reporting: when blocking, exits 2 even with mage absent, and stderr contains guard id
err=$(printf '{"tool_input":{"subagent_type":"general-purpose","description":"write tests for the parser"}}' \
  | PATH=/usr/bin:/bin "$HOOK" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ] && grep -q '^mage:rig/guard/delegate-check$' <<<"$err"; then
  echo "PASS: blocks with exit 2 and guard id on stderr when mage absent"
else
  echo "FAIL: guard report check failed (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo && echo "all delegate-check hook tests passed"
exit "$fails"


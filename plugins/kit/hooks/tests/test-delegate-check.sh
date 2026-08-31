#!/bin/bash
# Regression suite for delegate-check.sh (PreToolUse Agent).
# Blocks a generic subagent on delegable work; passes everything else.
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

check "generic subagent implementing to spec is blocked" 2 \
  '{"tool_input":{"subagent_type":"general-purpose","prompt":"implement the parser to spec"}}'
check "missing subagent_type still counts as generic" 2 \
  '{"tool_input":{"description":"collect evidence from the CI logs"}}'
check "rebase work is blocked" 2 \
  '{"tool_input":{"subagent_type":"claude","prompt":"rebase the branch onto main"}}'

check "naming agy is the escape hatch" 0 \
  '{"tool_input":{"subagent_type":"general-purpose","prompt":"implement to spec; agy quota is dry"}}'
check "antigravity also counts as considered" 0 \
  '{"tool_input":{"subagent_type":"general-purpose","prompt":"implement to spec, antigravity was down"}}'
check "agy-runner is never blocked" 0 \
  '{"tool_input":{"subagent_type":"agy-runner","prompt":"run ~/ai-context/agy-prompts/x.md"}}'
check "purpose-built agents encode their own routing" 0 \
  '{"tool_input":{"subagent_type":"fable-planner","prompt":"implement to spec"}}'
check "judgment work is not delegable" 0 \
  '{"tool_input":{"subagent_type":"general-purpose","prompt":"adjudicate two conflicting reviews"}}'
check "malformed input never blocks" 0 'not json at all'

[ "$fails" -eq 0 ] && echo && echo "all delegate-check hook tests passed"
exit "$fails"

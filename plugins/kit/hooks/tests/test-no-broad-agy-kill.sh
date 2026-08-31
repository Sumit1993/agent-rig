#!/bin/bash
# Regression suite for no-broad-agy-kill.sh (PreToolUse Bash).
# Blocks name-wide agy kills; leaves PID kills and run-scoped patterns alone.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/no-broad-agy-kill.sh"
fails=0

check() { # name expected_rc command
  local name=$1 want=$2 command=$3 got
  jq -n --arg c "$command" '{tool_input:{command:$c}}' | "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (want rc=$want, got rc=$got) -- $command"; fails=$((fails + 1))
  fi
}

echo "-- blocked: kills every agy on the machine"
check "pkill -9 -x agy"            2 'pkill -9 -x agy'
check "pkill -x agy"               2 'pkill -x agy'
check "killall agy"                2 'killall agy'
check "pkill -f agy"               2 'pkill -f agy'
check "pkill -f \"agy --model\""   2 'pkill -f "agy --model"'
check "bracketed generic"          2 'pkill -f "agy [-]-model"'
check "buried in a compound"       2 'echo cleaning; pkill -9 -x agy 2>/dev/null'
check "the exact line my test ran" 2 'kill -9 $BG 2>/dev/null; pkill -9 -x agy 2>/dev/null'

echo "-- allowed: scoped to one run, or not agy at all"
check "kill by PID"                0 'kill -9 "$AGY_PID"'
check "kill by captured \$!"        0 'kill -9 $BG 2>/dev/null'
check "run slug pattern"           0 'kill -9 $(pgrep -f "agy-rca-1788190000")'
check "pkill on the slug var"      0 'pkill -f "$SLUG"'
check "unrelated pkill"            0 'pkill -f my-dev-server'
check "pgrep is not a kill"        0 'pgrep -a agy'
check "no kill at all"             0 'git status --porcelain'
check "malformed input"            0 ''

[ "$fails" -eq 0 ] && echo && echo "all no-broad-agy-kill hook tests passed"
exit "$fails"

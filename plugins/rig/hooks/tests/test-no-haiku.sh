#!/bin/bash
# Regression suite for no-haiku.sh (PreToolUse Agent).
# Blocks deliberate choice of Haiku; allows other models and unstated models.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/no-haiku.sh"
fails=0

check() { # name expected_rc json [expected_stderr_lines]
  local name=$1 want=$2 json=$3 got err lines
  err=$(printf '%s' "$json" | "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL: $name (want rc=$want, got rc=$got)"; fails=$((fails + 1))
    return
  fi
  if [ $# -ge 4 ]; then
    lines=$(grep -c . <<<"$err" || true)
    if [ "$lines" -ne "$4" ]; then
      echo "FAIL: $name (want $4 stderr line(s), got $lines)"; fails=$((fails + 1))
      return
    fi
  fi
  echo "PASS: $name"
}

echo "-- blocked: deliberate haiku choices"
check "haiku blocks" 2 '{"tool_input":{"model":"haiku"}}'
check "claude-haiku-4-5-20251001 blocks" 2 '{"tool_input":{"model":"claude-haiku-4-5-20251001"}}'
check "Haiku blocks" 2 '{"tool_input":{"model":"Haiku"}}'
check "HAIKU blocks" 2 '{"tool_input":{"model":"HAIKU"}}'

echo "-- allowed: non-haiku models"
check "sonnet does not block" 0 '{"tool_input":{"model":"sonnet"}}'
check "opus does not block" 0 '{"tool_input":{"model":"opus"}}'
check "fable does not block" 0 '{"tool_input":{"model":"fable"}}'

echo "-- allowed: model absent, whatever subagent_type"
check "absent model does not block" 0 '{"tool_input":{}}'
check "absent model with claude-code-guide does not block" 0 \
  '{"tool_input":{"subagent_type":"claude-code-guide"}}'
check "absent model with general-purpose does not block" 0 \
  '{"tool_input":{"subagent_type":"general-purpose"}}'

echo "-- allowed with stderr warning: junk stdin"
check "junk stdin does not block and emits one stderr line" 0 'junk' 1

# Guard reporting: when blocking, exits 2 even with mage absent, and stderr contains guard id
err=$(printf '{"tool_input":{"model":"haiku"}}' | PATH=/usr/bin:/bin "$HOOK" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ] && grep -q '^mage:rig/guard/no-haiku$' <<<"$err"; then
  echo "PASS: blocks with exit 2 and guard id on stderr when mage absent"
else
  echo "FAIL: guard report check failed (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo && echo "all no-haiku hook tests passed"
exit "$fails"


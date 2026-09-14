#!/bin/bash
# Regression suite for scoped-cap-gate.sh (PreToolUse Agent). Refs #133.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/scoped-cap-gate.sh"
fails=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export MAGE_BIN=/nonexistent
future=$(date -u -d '+1 day' +%Y-%m-%dT%H:%M:%S.123456+00:00)
usage() { printf '{"limits":[{"kind":"weekly_all","percent":82,"severity":"warning"},{"kind":"weekly_scoped","percent":%s,"severity":"%s","resets_at":"%s","scope":{"model":{"display_name":"Fable"}}}]}' "$1" "$2" "$3" > "$T/usage.json"; }
run() { jq -n --argjson ti "$1" '{tool_name:"Agent",tool_input:$ti}' | SCOPED_CAP_USAGE="$T/usage.json" "$HOOK" >/dev/null 2>"$T/err"; echo $?; }
check() { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (rc=$2, want $3, err=$(cat "$T/err"))"; fails=$((fails+1)); fi; }

usage 100 critical "$future"
check "fable-planner blocked while Fable is critical" "$(run '{"subagent_type":"rig:fable-planner","prompt":"x"}')" 2
grep -q "until .*Z" "$T/err" && echo "PASS: block names the reset time" || { echo "FAIL: reset time ($(cat "$T/err"))"; fails=$((fails+1)); }
check "model fable blocked while Fable is critical" "$(run '{"model":"fable","prompt":"x"}')" 2
check "sonnet spawn allowed" "$(run '{"model":"sonnet","prompt":"x"}')" 0
check "no model and no planner allowed" "$(run '{"subagent_type":"general-purpose","prompt":"x"}')" 0

usage 64 normal "$future"
check "fable allowed at normal severity" "$(run '{"model":"fable","prompt":"x"}')" 0

usage 100 critical "2020-01-01T00:00:00.000000+00:00"
check "a passed reset allows" "$(run '{"model":"fable","prompt":"x"}')" 0

rm -f "$T/usage.json"
check "a missing cache allows" "$(run '{"model":"fable","prompt":"x"}')" 0

rc=$(printf 'junk' | SCOPED_CAP_USAGE="$T/usage.json" "$HOOK" >/dev/null 2>&1; echo $?)
check "junk stdin exits 0" "$rc" 0

[ "$fails" -eq 0 ] && echo "all scoped-cap-gate hook tests passed"; exit "$fails"

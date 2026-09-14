#!/bin/bash
# Verify hooks.json actually wires what the unit tests exercise.
#
# A hook can pass every unit test and still never run: wrong path, missing exec bit, a
# matcher that names a tool that does not exist. Transcripts on this machine record real
# `PreToolUse:Bash hook error: [...]` lines for a hook whose script was later deleted, so
# this failure mode is observed, not theoretical. Costs nothing.
set -u
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
JSON="$ROOT/plugins/rig/hooks/hooks.json"
fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

jq -e . "$JSON" >/dev/null 2>&1 || { echo "FAIL: hooks.json is not valid JSON"; exit 1; }
echo "PASS: hooks.json parses"

# Tools a matcher may name. A typo here means the hook silently never fires.
KNOWN='Bash|Edit|Write|NotebookEdit|Read|Agent|Glob|Grep|WebFetch|WebSearch|Monitor|Skill|Task|AskUserQuestion|EnterPlanMode|ExitPlanMode'

while IFS=$'\t' read -r event id matcher cmd; do
  path=${cmd//\"/}
  path=${path//\$\{CLAUDE_PLUGIN_ROOT\}/$ROOT/plugins/rig}
  path=${path%% *}

  if [ ! -f "$path" ]; then
    note "$id -> $path does not exist"; continue
  fi
  [ -x "$path" ] || note "$id -> $path is not executable"

  # Every matcher alternative must be a real tool name, on the events whose matcher is a tool.
  # StopFailure matches error types and Notification matches notification types.
  if [ "$matcher" != "-" ] && grep -qE '^(PreToolUse|PostToolUse|PostToolUseFailure|PermissionRequest|PermissionDenied)$' <<<"$event"; then
    while IFS= read -r m; do
      [ -z "$m" ] && continue
      grep -qE "^($KNOWN)$" <<<"$m" || note "$id -> matcher names unknown tool '$m'"
    done < <(tr '|' '\n' <<<"$matcher")
  fi

  # Some hooks act on the machine when run: reap-watchers kills watcher processes by
  # pattern, and executing it here killed this suite's own shell (exit 144) twice. Wiring
  # is checked for those; behaviour is left to their own tests.
  case "$(basename "$path")" in
    reap-watchers.sh|release-docs-gate.sh)
      echo "PASS: $id wired ($(basename "$path")), execution probe skipped (side effects)"
      continue ;;
  esac

  # A hook must survive junk on stdin without crashing; anything but 0/2 is a bug.
  printf 'not json' | timeout 10 "$path" >/dev/null 2>&1
  rc=$?
  case "$rc" in 0|2) ;; *) note "$id -> rc=$rc on malformed stdin (want 0 or 2)" ;; esac

  printf '{}' | timeout 10 "$path" >/dev/null 2>&1
  rc=$?
  case "$rc" in 0|2) ;; *) note "$id -> rc=$rc on empty payload (want 0 or 2)" ;; esac

    label=""; [ "$matcher" != "-" ] && label=", matcher $matcher"
  echo "PASS: $id wired ($(basename "$path")$label)"
done < <(jq -r '.hooks | to_entries[] | .key as $e | .value[] |
                [$e, ($e + ":" + (.hooks[0].command | sub(".*/"; "") | sub("\\.sh.*"; ""))),
                 (.matcher // "-"), .hooks[0].command] | @tsv' "$JSON")

# Every hook script in the directory should be reachable from hooks.json, or it is dead.
for f in "$ROOT"/plugins/rig/hooks/*.sh; do
  b=$(basename "$f")
  grep -q "$b" "$JSON" || note "$b exists but nothing in hooks.json references it"
done

echo
[ "$fails" -eq 0 ] && { echo "wiring clean"; exit 0; }
echo "$fails wiring problem(s)"; exit 1

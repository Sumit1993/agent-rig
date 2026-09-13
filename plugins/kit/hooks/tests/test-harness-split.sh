#!/bin/bash
# The agy plugin carries no Claude-only component. Refs #134.
set -u
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
fails=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails+1)); fi; }

bash "$ROOT/dotfiles/build-agy-plugin.sh" "$T/agy" >/dev/null
check "plugin.json at the root, valid, named" 'jq -e ".name == \"kit\"" "$T/agy/plugin.json" >/dev/null'
check "no hooks cross to agy" '[ -z "$(find "$T/agy" -name "hooks*" -o -name "*.sh" -path "*hooks*")" ]'
check "no agents cross to agy" '[ ! -e "$T/agy/agents" ]'
check "at least one skill crosses" '[ -n "$(ls "$T/agy/skills")" ]'

# A tag is a claim; a skill that names a Claude-only tool or path cannot carry it.
bad=$(grep -rlwE 'Monitor|Workflow|SendMessage|TaskStop|ScheduleWakeup|CronCreate|subagent_type|EnterWorktree|AskUserQuestion|CLAUDE_PLUGIN_ROOT' "$T/agy/skills" 2>/dev/null)
check "no agy skill names a Claude-only tool (${bad:-none})" '[ -z "$bad" ]'

untagged=$(for s in "$ROOT"/plugins/kit/skills/*/SKILL.md; do awk '/^---$/{n++; next} n==1' "$s" | grep -q 'harnesses:.*agy' || basename "$(dirname "$s")"; done | sort)
crossed=$(ls "$T/agy/skills" | sort)
check "an untagged skill stays Claude-only" '[ -z "$(comm -12 <(echo "$untagged") <(echo "$crossed"))" ]'

if command -v agy >/dev/null 2>&1; then
  out=$(timeout 30 agy plugin validate "$T/agy" 2>&1)
  check "agy plugin validate passes" 'grep -q "\[ok\]" <<<"$out" && ! grep -qi "error" <<<"$out"'
else
  echo "SKIP: agy not installed, plugin validate not run"
fi

[ "$fails" -eq 0 ] && echo "all harness-split tests passed"; exit "$fails"

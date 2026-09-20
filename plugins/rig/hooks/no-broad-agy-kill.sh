#!/bin/bash
# mage:rig/guard/no-broad-agy-kill
# PreToolUse(Bash) hook: block a kill that targets agy BY NAME rather than by run.
# `pkill -x agy` / `pkill -f "agy --model"` / `killall agy` reap every agy process on the
# machine, including other sessions' live runs, which surface there as rc=137 and read as
# quota death. farm-out says kill by PID, or by this run's --log-file slug.
set -u
in=$(cat)

_jlib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/json.sh"
[ -f "$_jlib" ] || _jlib="$(cd "$(dirname "$0")" && pwd)/lib/json.sh"
[ -f "$_jlib" ] && . "$_jlib"
type json_get >/dev/null 2>&1 || json_get() { return 1; }

_lib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/report-guard.sh"
[ -f "$_lib" ] || _lib="$(cd "$(dirname "$0")" && pwd)/lib/report-guard.sh"
[ -f "$_lib" ] && . "$_lib"
type report_guard >/dev/null 2>&1 || report_guard() { :; }

cmd=$(json_get "$in" "" .tool_input.command) || exit 0

grep -qE '\b(pkill|killall)\b' <<<"$cmd" || exit 0

# Quoted heredoc bodies are literal prose; unquoted bodies expand and stay scanned.
# Blank safe prose bodies before scanning for broad kills. Refs #35.
scan=$(awk '
in_body {
  stripped = $0
  sub(/^\t+/, "", stripped)
  if (stripped == delim) {
    in_body = 0
    print
  }
  next
}
$0 ~ /^[[:space:]]*(cat|tee)[[:space:]]/ && \
$0 !~ /[|;&`()]/ && \
match($0, /<<-?[[:space:]]*(['\''"]|\\)[A-Za-z0-9_]+/) && \
$0 ~ /[^[:space:]]+\.(md|txt)([[:space:]]|$)/ {
  m = substr($0, RSTART, RLENGTH)
  sub(/^<<-?[[:space:]]*(['\''"]|\\)/, "", m)
  delim = m
  in_body = 1
  print
  next
}
{ print }
' <<<"$cmd")

# Each pkill/killall invocation, up to the next shell separator.
while IFS= read -r inv; do
  [ -z "$inv" ] && continue
  # Drop the verb and every flag; what remains is the pattern, quotes stripped.
  pat=$(sed -E 's/^[[:space:]]*(pkill|killall)[[:space:]]*//' <<<"$inv" \
        | tr -d '"'"'"'' \
        | sed -E 's/(^|[[:space:]])-[A-Za-z0-9]+//g; s/^[[:space:]]+//; s/[[:space:]]+$//')
  [ -z "$pat" ] && continue
  # Safe: a pattern carrying a run-specific marker, e.g. the agy-<task>-<epoch> log slug.
  # Unsafe: bare `agy`, or agy followed only by flag-ish noise (`agy --model`, `agy [-]-model`).
  if [[ "$pat" == "agy" ]] || [[ "$pat" =~ ^agy[^A-Za-z0-9_-] ]]; then
    cat >&2 <<MSG
Blocked: \`$pat\` matches every agy process on this machine, not just yours.

Other sessions' runs die as rc=137 with empty output, which reads as silent quota death and
costs them their retry budget chasing a cause that was you. This repo's own test suite did
exactly that today.

Kill by PID instead (\`kill -9 "\$AGY_PID"\`, captured as \$! at launch, or the pid
run-agy-watchdog.sh prints). If the PID is lost, match this run's --log-file slug:
\`kill -9 \$(pgrep -f "\$SLUG")\`. See farm-out, "Killing a run".

To see what you would have hit: \`pgrep -a agy\`, then \`readlink /proc/<pid>/cwd\` to tell
the runs apart by worktree.

To quote the command in prose, put it in a quoted heredoc to cat or tee, for example \`cat <<'EOF' > notes.md\`.
mage:rig/guard/no-broad-agy-kill
MSG
    tool=$(json_get "$in" "Bash" .tool_name)
    report_guard "rig/guard/no-broad-agy-kill" "$tool" "$pat"
    exit 2
  fi
done < <(grep -oE '\b(pkill|killall)\b[^;&|)]*' <<<"$scan")

exit 0

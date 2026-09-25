#!/bin/bash
# Replay REAL tool calls from this machine's Claude Code transcripts through the hooks.
#
# Unit tests prove a hook does what I meant on payloads I invented. This proves it against
# payloads the harness actually produced: real command strings, real subagent prompts, real
# tool results. It costs nothing — no model, no network — and it measures the number that
# decides whether a blocking hook is tolerable, which is how often it would have fired on
# work that was fine.
#
#   ./replay-transcripts.sh            # 400 most recent calls per tool
#   REPLAY_LIMIT=0 ./replay-transcripts.sh   # everything; run-all.sh gives this a 900s cap
#   REPLAY_SHOW=1  ./replay-transcripts.sh   # print each blocked payload
#
# Sandboxed: state dirs are temporary and `gh` is stubbed, so a replayed PR URL cannot
# reach the network or seed a real watcher's seen-state.
set -u
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
PROJECTS="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
LIMIT="${REPLAY_LIMIT:-400}"
SHOW="${REPLAY_SHOW:-0}"

[ -d "$PROJECTS" ] || { echo "no transcripts at $PROJECTS — nothing to replay"; exit 0; }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export PR_WATCH_STATE_DIR="$SANDBOX/pr-seen" CR_WATCH_STATE_DIR="$SANDBOX/cr-watch"
printf '#!/bin/bash\nexit 1\n' > "$SANDBOX/gh"; chmod +x "$SANDBOX/gh"
export PATH="$SANDBOX:$PATH"

transcripts=$(find "$PROJECTS" -name '*.jsonl' -type f 2>/dev/null)
[ -z "$transcripts" ] && { echo "no .jsonl transcripts found"; exit 0; }
echo "replaying from $(wc -l <<<"$transcripts") transcript(s)"
echo

# Emit one compact JSON payload per real tool_use of the named tool.
payloads() { # tool_name
  # shellcheck disable=SC2086
  jq -c --arg t "$1" '
    select(.message.content != null)
    | .message.content[]?
    | select(.type == "tool_use" and .name == $t)
    | {tool_input: .input, tool_response: ""}
  ' $transcripts 2>/dev/null
}

replay() { # hook_file tool_name label
  local hook="$HOOKS/$1" tool=$2 label=$3
  [ -x "$hook" ] || { echo "SKIP $label (not executable)"; return 0; }
  local n=0 pass=0 blocked=0 crash=0 rc
  local blocked_samples=""
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    n=$((n + 1))
    [ "$LIMIT" -gt 0 ] && [ "$n" -gt "$LIMIT" ] && break
    printf '%s' "$p" | "$hook" >/dev/null 2>&1
    rc=$?
    case "$rc" in
      0) pass=$((pass + 1)) ;;
      2) blocked=$((blocked + 1))
         blocked_samples="${blocked_samples}$(jq -r '[.tool_input.command // .tool_input.description // .tool_input.prompt // ""] | .[0] | .[0:100]' <<<"$p" 2>/dev/null)"$'\n' ;;
      *) crash=$((crash + 1))
         echo "  CRASH rc=$rc on: $(jq -c '.tool_input' <<<"$p" 2>/dev/null | head -c 120)" ;;
    esac
  done < <(payloads "$tool")

  local checked=$((pass + blocked + crash))
  printf '%-22s %4d real %-6s calls: %4d pass, %3d blocked, %d crash\n' \
    "$label" "$checked" "$tool" "$pass" "$blocked" "$crash"
  if [ "$blocked" -gt 0 ] && [ "$SHOW" = "1" ]; then
    printf '%s' "$blocked_samples" | sed 's/^/      would block: /'
  fi
  [ "$crash" -gt 0 ] && return 1
  return 0
}

fails=0
replay no-broad-agy-kill.sh Bash  "no-broad-agy-kill"  || fails=$((fails + 1))
replay delegate-check.sh    Agent "delegate-check"     || fails=$((fails + 1))
replay no-haiku.sh          Agent "no-haiku"           || fails=$((fails + 1))
replay pr-created.sh        Bash  "pr-created"         || fails=$((fails + 1))

echo
echo "A crash is a bug. A block is a judgement call: re-run with REPLAY_SHOW=1 and read"
echo "what it caught, because every one of those is work that would have been interrupted."
[ "$fails" -eq 0 ] && { echo; echo "replay clean: no hook crashed on real input"; exit 0; }
echo; echo "$fails hook(s) crashed on real input"; exit 1

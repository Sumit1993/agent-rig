#!/bin/bash
# PostToolUse(Bash) hook: the first time a PR URL shows up in any Bash output,
# inject a reminder to arm the pr-watch monitor. Deduped per PR, so each one
# prompts once and never again.
# Silent (exit 0, no output) for every other Bash call.
#
# Matching the URL rather than the `gh pr create` command is deliberate. A PR
# raised inside a delegated lane never puts that string in the session's own
# command, so the old text match saw nothing and no watcher was ever armed
# (prismalens#495, a claude[bot] finding the session learned about from Sumit).
# Any path that surfaces a PR is a path that needs a watcher.
#
# Reviews are advisory and posted by CI; no required check waits on one, and
# nothing local has to run for a required check to go green. So this hook's whole
# job is the reminder.
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0

# a PR being merged or closed needs no watcher; it needs one torn down
case "$cmd" in
  *"gh pr merge"*|*"gh pr close"*) exit 0 ;;
esac

urls=$(jq -r '.tool_response | tostring' <<<"$in" 2>/dev/null \
  | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' | sort -u)
[ -z "$urls" ] && exit 0

# one reminder per PR, ever. The state dir is overridable so the test suite can
# run against a scratch directory instead of the real one.
state_dir=${PR_WATCH_STATE_DIR:-$HOME/ai-context/state/pr-seen}
mkdir -p "$state_dir" 2>/dev/null || exit 0

# every new PR in this output, not just the first: a batch script can raise several
fresh=""
while read -r url; do
  [ -z "$url" ] && continue
  key=$(printf '%s' "${url#https://github.com/}" | tr '/' '-')
  [ -e "$state_dir/$key" ] && continue
  : > "$state_dir/$key" 2>/dev/null || continue
  fresh="${fresh}PR #${url##*/} ($url); "
done <<< "$urls"
[ -z "$fresh" ] && exit 0

jq -n --arg fresh "${fresh%; }" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:(
      "\($fresh) — in play in this session with no watcher armed. "
      + "If you raised it or are driving its review round, arm the pr-watch monitor NOW: invoke the pr-watch skill (Phase 1: seed seen-state, arm Monitor with watch-coderabbit.sh) so review and CI feedback arrives as notifications instead of the user relaying it. "
      + "If it is merged, closed, or someone else'"'"'s round, ignore this."
   )}}'

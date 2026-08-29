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

url=$(jq -r '.tool_response | tostring' <<<"$in" 2>/dev/null \
  | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' | head -1)
[ -z "$url" ] && exit 0
pr=${url##*/}

# one reminder per PR, ever. The state dir is overridable so the test suite can
# run against a scratch directory instead of the real one.
state_dir=${PR_WATCH_STATE_DIR:-$HOME/ai-context/state/pr-seen}
key=$(printf '%s' "${url#https://github.com/}" | tr '/' '-')
mkdir -p "$state_dir" 2>/dev/null || exit 0
[ -e "$state_dir/$key" ] && exit 0
: > "$state_dir/$key" 2>/dev/null || exit 0

jq -n --arg pr "$pr" --arg url "$url" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:(
      "PR #\($pr) (\($url)) is in play in this session and has no watcher. "
      + "Standard practice: arm the pr-watch monitor NOW — invoke the pr-watch skill (Phase 1: seed seen-state, arm Monitor with watch-coderabbit.sh) so review and CI feedback arrives as notifications instead of the user relaying it. "
      + "If this PR is already merged or closed, ignore this."
   )}}'

#!/bin/bash
# PostToolUse(Bash) hook: when a `gh pr create` succeeds (PR URL in the output),
# inject a reminder to arm the pr-watch monitor.
# Silent (exit 0, no output) for every other Bash call.
#
# Review evidence is published by the repo's own `review-evidence.yml`, from the
# review the GitHub Actions lane posts. Nothing local needs to run for a required
# check to go green, so this hook's whole job is the reminder.
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
case "$cmd" in
  *"gh pr create"*) ;;
  *) exit 0 ;;
esac
url=$(jq -r '.tool_response | tostring' <<<"$in" 2>/dev/null | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' | head -1)
[ -z "$url" ] && exit 0
pr=${url##*/}

# The trigger is textual, so this also fires on a command that merely quotes
# "gh pr create" and prints an unrelated PR link. Arming a watcher for a PR that
# already exists is the right call anyway — including the case where `gh pr
# create` printed an existing PR's URL as an error — so the match stays broad.
jq -n --arg pr "$pr" --arg url "$url" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:(
      "PR #\($pr) was just raised (\($url)). "
      + "Standard practice: arm the pr-watch monitor NOW — invoke the pr-watch skill (Phase 1: seed seen-state, arm Monitor with watch-coderabbit.sh) so review and CI feedback arrives as notifications instead of the user relaying it."
   )}}'

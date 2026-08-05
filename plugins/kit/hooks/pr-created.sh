#!/bin/bash
# PostToolUse(Bash) hook: when a `gh pr create` succeeds (PR URL in the output),
#   1. publish CLI review evidence for the new PR, and
#   2. inject a reminder to arm the pr-watch monitor.
# Silent (exit 0, no output) for every other Bash call.
#
# WHY STEP 1 IS HERE
# ------------------
# `review-evidence` is a REQUIRED merge check on prismalens, sreforge and
# mage-memory, and under the CLI-first lane the marker `cr-evidence.sh` posts is
# the only thing that turns it green. But `cr-preview.sh` runs pre-push, before
# a PR exists, so its own call to `cr-evidence.sh` always no-ops — and nothing
# called it afterwards. `cr-preview.sh` claimed pr-watch did; a repo-wide grep
# said otherwise. Evidence had been landing by hand for every PR.
#
# That vacuum is not a papercut. The one time a script filled it, it called
# `cr-evidence.sh` unconditionally and posted evidence for a review that had
# aborted on a rate limit — the gate went green on a review that never ran
# (prismalens/prismalens#301 §4). So the caller belongs in code that runs on
# every PR, exactly once, rather than in a prompt that an agent may improvise.
# Soundness stays where it belongs: `cr-evidence.sh` refuses unless a completed
# CLI review exists for that exact head. This hook only removes the excuse for
# doing it by hand.
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
# The URL is the authority for both, not the session's cwd: the push may have
# come from a worktree, or from a `cd` inside the command.
path=${url#https://github.com/}
repo=${path%%/pull/*}

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Did this command actually create that PR, or merely mention one?
#
# The trigger is textual — a command containing "gh pr create" whose output
# contains a PR URL — so it also fires on a command that merely *quotes* the
# string and prints some unrelated PR link (a grep, a test, a doc edit). While
# the hook only injected a reminder that was harmless. Now that it acts, a false
# positive would aim the evidence path at a PR this session never opened.
#
# It would still fail closed: `cr-evidence.sh` demands a completion record keyed
# to that PR's own repo and branch, which an unrelated PR will not have. But it
# would report a refusal for a PR nobody touched, and a warning that cries wolf
# is a warning that gets ignored. A PR that `gh pr create` just returned is
# seconds old; a mentioned one almost never is.
#
# This gates the evidence step ONLY. The reminder still fires on a stale match —
# `gh pr create` against a branch that already has a PR prints that PR's URL as
# an error, and arming a watcher for it is right.
is_fresh () {
  local created created_epoch age
  created=$(gh pr view "$pr" --repo "$repo" --json createdAt -q .createdAt 2>/dev/null) || return 0
  [ -n "$created" ] || return 0
  created_epoch=$(date -d "$created" +%s 2>/dev/null) || return 0
  case "$created_epoch" in ''|*[!0-9]*) return 0 ;; esac
  age=$(( $(date +%s) - created_epoch ))
  [ "$age" -le "${KIT_PR_CREATED_WINDOW:-300}" ]
}

# Only repos the registry marks CodeRabbit-enabled have the gate, and only those
# get a CLI preview pre-push. Attempting evidence elsewhere would refuse every
# time and train the operator to ignore the warning.
ev_msg=""
if [ "$("$PLUGIN_ROOT/scripts/kit-meta.sh" get "$repo" coderabbit 2>/dev/null)" = "true" ] && is_fresh; then
  ev_out=$("$PLUGIN_ROOT/scripts/cr-evidence.sh" --repo "$repo" --pr "$pr" 2>&1)
  ev_rc=$?
  if [ "$ev_rc" -eq 0 ]; then
    ev_msg="CLI review evidence: ${ev_out:-nothing to post}."
  else
    # A refusal must be loud. A red required check with no stated cause is the
    # failure mode this whole track exists to remove.
    ev_msg="⚠️ CLI review evidence NOT posted (exit $ev_rc): ${ev_out:-no output}. The \`review-evidence\` required check will stay RED until a CLI review completes for this head — run \`cr-preview.sh\`, then \`cr-evidence.sh --repo $repo --pr $pr\`. Never hand-post the marker comment: it would vouch for a review that did not run."
  fi
fi

jq -n --arg pr "$pr" --arg url "$url" --arg ev "$ev_msg" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:(
      "PR #\($pr) was just raised (\($url)). "
      + (if $ev == "" then "" else $ev + " " end)
      + "Standard practice: arm the pr-watch monitor NOW — invoke the pr-watch skill (Phase 1: seed seen-state, arm Monitor with watch-coderabbit.sh) so CodeRabbit/CI feedback arrives as notifications instead of the user relaying it."
   )}}'

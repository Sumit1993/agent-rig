#!/bin/bash
# PostToolUse(Bash) hook: the first time a PR URL shows up in any Bash output,
# inject a reminder to arm the pr-watch monitor. Deduped per PR, so each one
# prompts once and never again.
# Silent (exit 0, no output) for every other Bash call.
#
# Matching the URL rather than the `gh pr create` command is deliberate. A PR
# raised inside a delegated lane never puts that string in the session's own
# command, so the old text match saw nothing and no watcher was ever armed.
# Any path that surfaces a PR is a path that needs a watcher. Story: prismalens#495.
#
# Reviews are advisory and posted by CI; no required check waits on one, and
# nothing local has to run for a required check to go green. So this hook seeds the
# watcher's seen-state (mechanical, and the step most often skipped) and reminds the
# session to arm the Monitor, which only the model can do.
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

# Seed both seen-state files so the first watcher poll does not replay every existing
# comment as NEW. Best-effort: a failure here costs replayed events, never a missed PR.
seed_seen() {
  local url=$1 repo pr cw key body
  repo=${url#https://github.com/}; repo=${repo%%/pull/*}
  pr=${url##*/}
  cw=${CR_WATCH_STATE_DIR:-$HOME/ai-context/state/cr-watch}
  mkdir -p "$cw" 2>/dev/null || return 0
  key=$(printf '%s' "$repo" | tr '/' '-')
  body=$(gh api "repos/$repo/pulls/$pr/comments?per_page=100" 2>/dev/null) || return 0
  jq -e 'type == "array"' >/dev/null 2>&1 <<<"$body" || return 0
  jq -r '.[] | select(.user.login|test("coderabbit";"i")) | .id' <<<"$body" \
    > "$cw/$key-pr$pr.seen" 2>/dev/null
  jq -r '.[] | select(.user.login|test("claude";"i")) | .id' <<<"$body" \
    > "$cw/$key-pr$pr-claude.seen" 2>/dev/null
}

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
  seed_seen "$url"
  fresh="${fresh}PR #${url##*/} ($url); "
done <<< "$urls"
[ -z "$fresh" ] && exit 0

jq -n --arg fresh "${fresh%; }" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:(
      "\($fresh) — in play in this session with no watcher armed. "
      + "If you raised it or are driving its review round, arm the pr-watch monitor NOW: seen-state is already seeded, so invoke the pr-watch skill and arm the Monitor with watch-coderabbit.sh, and review and CI feedback arrives as notifications instead of the user relaying it. "
      + "If it is merged, closed, or someone else'"'"'s round, ignore this."
   )}}'

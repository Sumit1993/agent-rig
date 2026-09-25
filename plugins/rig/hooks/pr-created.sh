#!/bin/bash
# PostToolUse(Bash) hook: the first time a PR URL shows up in any Bash output,
# inject a reminder to pick a watcher: /autofix-pr by default, the pr-babysit Monitor for a
# held round. Deduped per PR, so each one
# prompts once and never again.
# Silent (exit 0, no output) for every other Bash call.
# Rung: hook. Skipped: impossible (no harness feature auto-attaches watchers), check (the PR URL appears only in tool output).
#
# Matching the URL rather than the `gh pr create` command is deliberate. A PR
# raised inside a delegated lane never puts that string in the session's own
# command, so the old text match saw nothing and no watcher was ever armed.
# Any path that surfaces a PR is a path that needs a watcher. Story: prismalens#495.
#
# Registered on Bash AND Agent. An agy lane redirects its output to a file, so the URL
# never reaches a Bash tool_response and this hook cannot see it; it arrives later in the
# handler subagent's report, which is an Agent tool_response. That firing point also
# matters: a subagent cannot hold a Monitor (it dies with its turn), so the nudge has to
# land in the main session. Story: gh-workflows#69, reviewed and unwatched.
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

# Confirm the PR is real before spending a reminder on it. The URL match is deliberately
# loose, so a fixture URL sitting in test data or a mock fixture reaches here and reads
# exactly like a PR nobody printed. Only a definite 404 suppresses; any other failure
# (no auth, no network, rate limit) is unknown and still reminds, marked unverified,
# because a missed real PR costs more than a checked-and-wrong nudge.
# Story: gh-workflows, fictional pull/42 in a seeded usage_records row.
# 0 = exists, 1 = definitely absent, 2 = could not tell.
pr_exists() {
  local repo=$1 pr=$2 err
  err=$(gh api "repos/$repo/pulls/$pr" --jq .number 2>&1 >/dev/null) && return 0
  case "$err" in *"HTTP 404"*|*"Not Found"*) return 1 ;; esac
  return 2
}

# Seed both seen-state files so the first watcher poll does not replay every existing
# comment as NEW. Best-effort: a failure here costs replayed events, never a missed PR.
seed_seen() {
  local url=$1 repo pr cw key body origin
  repo=${url#https://github.com/}; repo=${repo%%/pull/*}
  pr=${url##*/}
  # Only seed a PR in the repo we are standing in. The URL match is deliberately loose, so
  # any file content mentioning a PR link reaches here; seeding on that spent a real API
  # call and wrote real state for repos nobody was watching. Reminding is still free and
  # still happens — seeding is the part with side effects, so it needs to be sure.
  origin=$(git remote get-url origin 2>/dev/null) || return 0
  origin=$(printf '%s' "$origin" | sed -E 's#.*github\.com[:/]##; s#\.git$##')
  [ "$origin" = "$repo" ] || return 1
  cw=${CR_WATCH_STATE_DIR:-$HOME/ai-context/state/cr-watch}
  mkdir -p "$cw" 2>/dev/null || return 1
  key=$(printf '%s' "$repo" | tr '/' '-')
  body=$(gh api "repos/$repo/pulls/$pr/comments?per_page=100" 2>/dev/null) || return 1
  jq -e 'type == "array"' >/dev/null 2>&1 <<<"$body" || return 1
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
# One API call per unseen URL, so a page listing many PR links is bounded: past the cap
# the rest are reported unverified rather than making the hook sit on the network.
checks_left=10

fresh=""; fresh_urls=""; seeded=0; unverified=0
while read -r url; do
  [ -z "$url" ] && continue
  repo=${url#https://github.com/}; repo=${repo%%/pull/*}
  num=${url##*/}
  key=$(printf '%s' "${url#https://github.com/}" | tr '/' '-')
  [ -e "$state_dir/$key" ] && continue
  # Existence is checked BEFORE the dedupe marker is written. A 404 today can be a real
  # PR tomorrow at the same number, and a marker written now would suppress it forever.
  if [ "$checks_left" -gt 0 ]; then
    checks_left=$((checks_left - 1))
    pr_exists "$repo" "$num"; seen=$?
  else
    seen=2
  fi
  [ "$seen" = "1" ] && continue
  : > "$state_dir/$key" 2>/dev/null || continue
  if seed_seen "$url"; then seeded=1; fi
  if [ "$seen" = "2" ]; then unverified=1; note=", UNVERIFIED"; else note=""; fi
  fresh="${fresh}PR #${num} ($url$note); "
  fresh_urls="${fresh_urls}${url}"$'\n'
done <<< "$urls"
[ -z "$fresh" ] && exit 0

# GitHub links only the first number after a closing keyword; "Closes #1, #2" leaves #2 open.
# Compare what the body names against closingIssuesReferences. Story: gh-workflows #140, #155.
closes_note=""
while read -r url; do
  [ -z "$url" ] && continue
  grep -qxF "$url" <<<"$fresh_urls" || continue
  repo=${url#https://github.com/}; repo=${repo%%/pull/*}; num=${url##*/}
  pv=$(gh pr view "$num" -R "$repo" --json body,closingIssuesReferences 2>/dev/null) || continue
  named=$(jq -r '[.body // "" | match("(?i)\\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\\b[^\\n]*"; "g").string | match("#[0-9]+"; "g").string] | unique | length' <<<"$pv" 2>/dev/null)
  linked=$(jq -r '.closingIssuesReferences | length' <<<"$pv" 2>/dev/null)
  [ -n "$named" ] && [ -n "$linked" ] && [ "$named" -gt "$linked" ] \
    && closes_note="${closes_note}PR #${num} body names ${named} issue(s) after a closing keyword but GitHub linked ${linked}; repeat the keyword per issue (closes #a, closes #b) and edit the body. "
done <<< "$urls"

check_note="Each PR above was confirmed to exist through the GitHub API before this fired."
[ "$unverified" = "1" ] && check_note="Each PR above was confirmed to exist through the GitHub API, except any marked UNVERIFIED: that check itself failed, so the URL could be a fixture from test data. Run gh pr view on it before arming."

overlap_note=""
cwd_origin=$(git remote get-url origin 2>/dev/null) || cwd_origin=""
cwd_origin=$(printf '%s' "$cwd_origin" | sed -E 's#.*github\.com[:/]##; s#\.git$##')
case "$cwd_origin" in
  */*) ;;
  *) cwd_origin="" ;;
esac

if [ -n "$cwd_origin" ]; then
  has_matching_fresh=0
  while read -r url; do
    [ -z "$url" ] && continue
    grep -qxF "$url" <<<"$fresh_urls" || continue
    repo=${url#https://github.com/}; repo=${repo%%/pull/*}
    if [ "$repo" = "$cwd_origin" ]; then
      has_matching_fresh=1
      break
    fi
  done <<< "$urls"

  if [ "$has_matching_fresh" = "1" ]; then
    # Two PR-file queries at most; the draft list is its own call.
    calls_left=2
    drafts_json=$(gh pr list -R "$cwd_origin" --author @me --draft --state open --json number,files 2>/dev/null) || drafts_json=""
    if jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$drafts_json"; then
      while read -r url; do
        [ -z "$url" ] && continue
        grep -qxF "$url" <<<"$fresh_urls" || continue
        repo=${url#https://github.com/}; repo=${repo%%/pull/*}; num=${url##*/}
        [ "$repo" = "$cwd_origin" ] || continue
        [ "$calls_left" -gt 0 ] || break
        pv_files=$(gh pr view "$num" -R "$cwd_origin" --json files 2>/dev/null) || pv_files=""
        calls_left=$((calls_left - 1))
        if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$pv_files"; then
          matching_draft=$(jq -n -r \
            --argjson drafts "$drafts_json" \
            --argjson fresh_num "$num" \
            --argjson fresh_view "$pv_files" '
              ($fresh_view.files // [] | map(.path // empty)) as $fresh_paths
              | [ $drafts[]
                  | select(.number != $fresh_num)
                  | select(any(.files[]?; (.path // empty) as $p | $fresh_paths | index($p)))
                ] | first | .number // empty
            ' 2>/dev/null) || matching_draft=""
          if [ -n "$matching_draft" ]; then
            overlap_note="${overlap_note}PR #${num} touches files also changed in open draft #${matching_draft}; fold the work into #${matching_draft} unless it is its own unit (compass Step 3). "
          fi
        fi
      done <<< "$urls"
    fi
  fi
fi

jq -n --arg fresh "${fresh%; }" --arg check "$check_note" --arg closes "$closes_note" --arg overlap "$overlap_note" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:(
      "\($fresh) — opened in this session. \($check) \($closes)\($overlap)"
      + "Reviews run async (Sumit1993/rig#150): keep it a draft while work continues, mark it ready once at the end, and do not arm a watcher. The hourly CodeRabbit routine summons CodeRabbit, merges the PR when its review is clean, and findings come back as review debt at the next session start in this repo. Arm the pr-babysit Monitor only when the operator asks to hold this round in this session. If it is merged, closed, or someone else'"'"'s round, ignore this."
   )}}'

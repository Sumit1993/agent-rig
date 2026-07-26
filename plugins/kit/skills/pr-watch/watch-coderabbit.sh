#!/bin/bash
# watch-coderabbit.sh [--repo owner/name] <pr#> [<pr#>...]
# Deterministic PR watcher for Claude Code's Monitor tool. Emits ONE stdout line per:
#   - new CodeRabbit review comment (thread root or reply)
#   - CodeRabbit rate-limit block (NO review ran) + the auto re-trigger once the window elapses
#   - CI check that newly turned red
#   - PR reaching MERGED/CLOSED (then dropped from the watch)
# Exits when no watched PRs remain. Seen-state persists in ~/ai-context/state/cr-watch
# keyed by owner-repo-prN, so re-arming never re-emits old comments.
# Repo defaults to the current directory's origin remote.
#
# Rate limits (found live 2026-07-26, prismalens#213): when CodeRabbit is out of quota it
# posts the notice as an ISSUE comment, not a review comment — a watcher polling only
# /pulls/N/comments sees nothing and waits forever. It also posts a check named
# "Review rate limited" that PASSES by design (so it never blocks merge on protected
# branches), so the red-check loop can't see it either. Both channels are silent; this
# script polls /issues/N/comments for the marker and treats it as a first-class event.
# Env: CR_WATCH_AUTORETRY=0 disables posting `@coderabbitai review` (detect-only).
#      CR_WATCH_MAX_RETRIES=N caps auto re-triggers per PR (default 2).
set -u
if [ "${1:-}" = "--repo" ]; then REPO="$2"; shift 2; else
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || { echo "watch-coderabbit: cannot resolve repo (pass --repo owner/name)"; exit 1; }
fi
KEY=$(echo "$REPO" | tr '/' '-')
STATE_DIR="$HOME/ai-context/state/cr-watch"
mkdir -p "$STATE_DIR"
PRS=("$@")
[ ${#PRS[@]} -eq 0 ] && { echo "watch-coderabbit: no PR numbers given"; exit 1; }
AUTORETRY=${CR_WATCH_AUTORETRY:-1}
MAX_RETRIES=${CR_WATCH_MAX_RETRIES:-2}
declare -A FAILED_SEEN
gh_fail=0

# Minutes until the next review window, parsed from the rate-limit notice
# ("Next review available in: **47 minutes**" / "**1 hour**"). Falls back to 60.
retry_seconds() {
  local parsed num unit
  parsed=$(printf '%s\n' "$1" | sed -n 's/.*[Nn]ext review available in:[^0-9]*\([0-9][0-9]*\)[^a-zA-Z]*\([a-zA-Z]*\).*/\1 \2/p' | head -1)
  num=${parsed%% *}; unit=${parsed#* }
  case "$num" in ''|*[!0-9]*) echo 3600; return;; esac
  case "$unit" in hour*|Hour*) echo $((num * 3600));; *) echo $((num * 60));; esac
}

while [ ${#PRS[@]} -gt 0 ]; do
  next=()
  for pr in "${PRS[@]}"; do
    state=$(gh pr view "$pr" --repo "$REPO" --json state --jq .state 2>/dev/null) || { gh_fail=$((gh_fail+1)); next+=("$pr"); continue; }
    gh_fail=0
    if [ "$state" != "OPEN" ]; then
      echo "PR#$pr $state — dropped from watch"
      continue
    fi
    next+=("$pr")

    seen="$STATE_DIR/$KEY-pr$pr.seen"; touch "$seen"
    gh api "repos/$REPO/pulls/$pr/comments?per_page=100" \
      --jq '.[] | select(.user.login | test("coderabbit")) | "\(.id)\t\(.path):\(.line // .original_line)\t\(.in_reply_to_id // "root")\t\(.body | gsub("[\\n\\r\\t]"; " ") | .[0:150])"' 2>/dev/null |
    while IFS=$'\t' read -r id path reply body; do
      grep -qx "$id" "$seen" 2>/dev/null && continue
      echo "$id" >> "$seen"
      kind="thread"; [ "$reply" != "root" ] && kind="reply-in-$reply"
      echo "PR#$pr NEW coderabbit $kind — id $id — $path — $body"
    done

    # --- rate-limit channel (issue comments) ---
    # CodeRabbit keeps ONE summary issue comment per PR and EDITS it, so the comment id is
    # stable across pushes — dedupe on updated_at, not id, or a second block never fires.
    rl_state="$STATE_DIR/$KEY-pr$pr.ratelimit"
    prev_ts=""; retry_at=0; used=0
    [ -f "$rl_state" ] && IFS=$'\t' read -r prev_ts retry_at used < "$rl_state"
    case "$retry_at" in ''|*[!0-9]*) retry_at=0;; esac
    case "$used" in ''|*[!0-9]*) used=0;; esac

    if rl=$(gh api "repos/$REPO/issues/$pr/comments?per_page=100" \
              --jq '[.[] | select(.user.login | test("coderabbit"))
                         | select(.body | test("rate limited by coderabbit\\.ai"))]
                    | last | "\(.updated_at)\t\(.body | gsub("[\\n\\r\\t]"; " "))"' 2>/dev/null); then
      if [ "$rl" = "null" ] || [ -z "$rl" ]; then
        # Notice gone => a real review ran and replaced it. Existing thread poll covers the findings.
        if [ -f "$rl_state" ]; then
          rm -f "$rl_state"
          echo "PR#$pr CODERABBIT RESUMED — rate-limit notice cleared, review ran"
        fi
      else
        rl_ts=${rl%%$'\t'*}; rl_body=${rl#*$'\t'}
        if [ "$rl_ts" != "$prev_ts" ]; then
          secs=$(retry_seconds "$rl_body")
          if [ "$AUTORETRY" != "1" ]; then
            armed="window $((secs / 60))m; auto-retry OFF (CR_WATCH_AUTORETRY=0) — re-trigger by hand or run the model review pass"
            retry_at=0
          elif [ "$used" -lt "$MAX_RETRIES" ]; then
            armed="auto-retry armed in $((secs / 60))m (attempt $((used + 1))/$MAX_RETRIES)"
            retry_at=$(( $(date +%s) + secs + 60 ))   # +60s slack: never re-trigger a beat early
          else
            armed="auto-retry budget spent ($MAX_RETRIES) — run the model review pass instead of waiting"
            retry_at=0
          fi
          echo "PR#$pr CODERABBIT RATE-LIMITED — no review ran; $armed"
          printf '%s\t%s\t%s\n' "$rl_ts" "$retry_at" "$used" > "$rl_state"
          prev_ts="$rl_ts"
        fi
        # Window elapsed: a blocked push consumes no quota, so re-triggering is free.
        if [ "$retry_at" -gt 0 ] && [ "$(date +%s)" -ge "$retry_at" ]; then
          if gh api "repos/$REPO/issues/$pr/comments" -f body="@coderabbitai review" >/dev/null 2>&1; then
            echo "PR#$pr CODERABBIT RE-TRIGGERED — posted @coderabbitai review (attempt $((used + 1))/$MAX_RETRIES)"
          else
            echo "PR#$pr CODERABBIT RE-TRIGGER FAILED — post '@coderabbitai review' by hand"
          fi
          printf '%s\t0\t%s\n' "$prev_ts" "$((used + 1))" > "$rl_state"
        fi
      fi
    fi

    # Read line-by-line: check names contain spaces ("Validate PR title (conventional
    # commits)"), and `for r in $reds` word-splits them into one bogus event per word
    # (found live 2026-07-26 on prismalens#218). A here-string keeps FAILED_SEEN in
    # this shell — a pipe would subshell it and every red would re-fire every cycle.
    reds=$(gh pr checks "$pr" --repo "$REPO" 2>/dev/null | awk -F'\t' '$2=="fail" {print $1}')
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      key="$pr:$r"
      [ "${FAILED_SEEN[$key]:-}" = "1" ] && continue
      FAILED_SEEN[$key]=1
      echo "PR#$pr CI FAIL — $r"
    done <<< "$reds"
  done
  # NB: not PRS=("${next[@]:-}") — empty array expands to one "" element and the exit check never fires (found live 2026-07-12)
  [ ${#next[@]} -eq 0 ] && break
  PRS=("${next[@]}")
  [ "$gh_fail" -ge 5 ] && { echo "WATCHER DEGRADED — gh failing repeatedly (auth/network?)"; gh_fail=0; }
  sleep 75
done
echo "watch-coderabbit: all watched PRs closed — exiting"

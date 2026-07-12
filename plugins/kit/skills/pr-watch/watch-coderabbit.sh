#!/bin/bash
# watch-coderabbit.sh [--repo owner/name] <pr#> [<pr#>...]
# Deterministic PR watcher for Claude Code's Monitor tool. Emits ONE stdout line per:
#   - new CodeRabbit review comment (thread root or reply)
#   - CI check that newly turned red
#   - PR reaching MERGED/CLOSED (then dropped from the watch)
# Exits when no watched PRs remain. Seen-state persists in ~/ai-context/state/cr-watch
# keyed by owner-repo-prN, so re-arming never re-emits old comments.
# Repo defaults to the current directory's origin remote.
set -u
if [ "${1:-}" = "--repo" ]; then REPO="$2"; shift 2; else
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || { echo "watch-coderabbit: cannot resolve repo (pass --repo owner/name)"; exit 1; }
fi
KEY=$(echo "$REPO" | tr '/' '-')
STATE_DIR="$HOME/ai-context/state/cr-watch"
mkdir -p "$STATE_DIR"
PRS=("$@")
[ ${#PRS[@]} -eq 0 ] && { echo "watch-coderabbit: no PR numbers given"; exit 1; }
declare -A FAILED_SEEN
gh_fail=0

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

    reds=$(gh pr checks "$pr" --repo "$REPO" 2>/dev/null | awk -F'\t' '$2=="fail" {print $1}')
    for r in $reds; do
      key="$pr:$r"
      [ "${FAILED_SEEN[$key]:-}" = "1" ] && continue
      FAILED_SEEN[$key]=1
      echo "PR#$pr CI FAIL — $r"
    done
  done
  # NB: not PRS=("${next[@]:-}") — empty array expands to one "" element and the exit check never fires (found live 2026-07-12)
  [ ${#next[@]} -eq 0 ] && break
  PRS=("${next[@]}")
  [ "$gh_fail" -ge 5 ] && { echo "WATCHER DEGRADED — gh failing repeatedly (auth/network?)"; gh_fail=0; }
  sleep 75
done
echo "watch-coderabbit: all watched PRs closed — exiting"

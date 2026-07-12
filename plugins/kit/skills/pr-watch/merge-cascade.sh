#!/bin/bash
# merge-cascade.sh [--repo owner/name] <pr#> [<pr#>...]
# Shepherds a set of auto-merge-armed PRs to completion: GitHub auto-merge never
# updates BEHIND branches, so each merge strands the rest — this loop runs
# `gh pr update-branch` on anything BEHIND until every PR is merged/closed.
# Emits one line per state change; exits when done (~45 min safety timeout).
# Arm auto-merge yourself first: gh pr merge <n> --auto --squash
set -u
if [ "${1:-}" = "--repo" ]; then REPO="$2"; shift 2; else
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || { echo "merge-cascade: cannot resolve repo"; exit 1; }
fi
PRS=("$@")
[ ${#PRS[@]} -eq 0 ] && { echo "merge-cascade: no PR numbers given"; exit 1; }
end=$(( $(date +%s) + 2700 ))

while [ "$(date +%s)" -lt "$end" ]; do
  next=()
  for pr in "${PRS[@]}"; do
    state=$(gh pr view "$pr" --repo "$REPO" --json state --jq .state 2>/dev/null || echo UNKNOWN)
    if [ "$state" = "MERGED" ] || [ "$state" = "CLOSED" ]; then
      echo "PR#$pr $state"
      continue
    fi
    next+=("$pr")
    mss=$(gh pr view "$pr" --repo "$REPO" --json mergeStateStatus --jq .mergeStateStatus 2>/dev/null || echo UNKNOWN)
    if [ "$mss" = "BEHIND" ]; then
      gh pr update-branch "$pr" --repo "$REPO" >/dev/null 2>&1 && echo "PR#$pr was BEHIND — branch updated, CI rerunning"
    fi
  done
  # NB: not PRS=("${next[@]:-}") — empty array expands to one "" element (see watch-coderabbit.sh)
  [ ${#next[@]} -eq 0 ] && { echo "merge-cascade: all merged"; exit 0; }
  PRS=("${next[@]}")
  sleep 90
done
echo "merge-cascade: TIMEOUT with open PRs: ${PRS[*]} — check thread resolution / required reviews"
exit 1

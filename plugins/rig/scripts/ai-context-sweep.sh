#!/bin/bash
# ai-context-sweep.sh [--delete]: dry-run lister or pruner for closed ai-context issue material.
# Refs #123.
set -u

delete="no"
for arg in "$@"; do
  case "$arg" in
    --delete) delete="yes" ;;
    *) ;;
  esac
done

root="${AI_CONTEXT_ROOT:-$HOME/ai-context}"
if [ ! -d "$root" ]; then
  echo "0 closed candidates, 0 open, 0 empty dirs, 0 loose files at the top level"
  exit 0
fi

meta_file="${RIG_REPO_META:-$(cd "$(dirname "$0")/.." && pwd)/data/repo-meta.json}"
# An unreadable registry would classify every repo directory as unknown, so it is an error.
command -v jq >/dev/null 2>&1 || { echo "ai-context-sweep: jq is required" >&2; exit 1; }
keys=$(jq -er 'keys[]' "$meta_file" 2>/dev/null) || { echo "ai-context-sweep: cannot read the registry at $meta_file" >&2; exit 1; }
registry_repos=()
while IFS= read -r r; do
  [ -n "$r" ] && registry_repos+=("$r")
done <<<"$keys"

# Prints every registry repo whose name is this basename; the caller decides what two mean.
get_repos_by_base() {
  local base="$1" r
  for r in "${registry_repos[@]}"; do
    [ "${r##*/}" = "$base" ] && echo "$r"
  done
}

query_gh_item() {
  local num="$1" target_repo="$2"
  local json
  json=$(gh issue view "$num" -R "$target_repo" --json state,closedAt 2>/dev/null) || json=""
  if [ -n "$json" ]; then
    printf '%s' "$json"
    return 0
  fi
  json=$(gh pr view "$num" -R "$target_repo" --json state,closedAt 2>/dev/null) || json=""
  if [ -n "$json" ]; then
    printf '%s' "$json"
    return 0
  fi
  return 1
}

shopt -s nullglob
loose_files=0
candidate_paths=()
candidate_issues=()
candidate_repos=()
empty_dirs=()

for entry in "$root"/*; do
  base=$(basename "$entry")
  case "$base" in
    state|telemetry|backups|vendor|agy-*) continue ;;
  esac

  if [ -f "$entry" ]; then
    loose_files=$((loose_files + 1))
    continue
  fi

  [ -d "$entry" ] || continue

  matches=$(get_repos_by_base "$base")
  if [ -n "$matches" ]; then
    matched_repo="$matches"
    [ "$(wc -l <<<"$matches")" -gt 1 ] && matched_repo="SKIP:AMBIGUOUS"
    # Type 1: <root>/<repo>/<n>-<slug>/
    subdirs=("$entry"/*)
    if [ "${#subdirs[@]}" -eq 0 ]; then
      empty_dirs+=("$entry")
    else
      for sub in "${subdirs[@]}"; do
        sbase=$(basename "$sub")
        if [ -d "$sub" ]; then
          if [[ "$sbase" =~ ^([0-9]+)- ]]; then
            candidate_paths+=("$sub")
            candidate_issues+=("${BASH_REMATCH[1]}")
            candidate_repos+=("$matched_repo")
          elif [ -z "$(ls -A "$sub" 2>/dev/null)" ]; then
            empty_dirs+=("$sub")
          fi
        fi
      done
    fi
  elif [[ "$base" =~ ^([0-9]+)- ]]; then
    # Type 2: <root>/<n>-<slug>/
    num="${BASH_REMATCH[1]}"
    hits=()
    hit_json=()
    for r in "${registry_repos[@]}"; do
      res=$(query_gh_item "$num" "$r")
      if [ $? -eq 0 ] && [ -n "$res" ]; then
        hits+=("$r")
        hit_json+=("$res")
      fi
    done

    if [ "${#hits[@]}" -eq 1 ]; then
      candidate_paths+=("$entry")
      candidate_issues+=("$num")
      candidate_repos+=("${hits[0]}")
    elif [ "${#hits[@]}" -eq 0 ]; then
      candidate_paths+=("$entry")
      candidate_issues+=("$num")
      candidate_repos+=("SKIP:404")
    else
      candidate_paths+=("$entry")
      candidate_issues+=("$num")
      candidate_repos+=("SKIP:AMBIGUOUS")
    fi
  else
    if [ -z "$(ls -A "$entry" 2>/dev/null)" ]; then
      empty_dirs+=("$entry")
    else
      while IFS= read -r ed; do
        [ -n "$ed" ] && empty_dirs+=("$ed")
      done < <(find "$entry" -type d -empty 2>/dev/null || true)
    fi
  fi
done

n_closed=0
n_open=0
failed=0
lines=()

for ((i = 0; i < ${#candidate_paths[@]}; i++)); do
  cand="${candidate_paths[i]}"
  num="${candidate_issues[i]}"
  target_repo="${candidate_repos[i]}"

  case "$target_repo" in
    SKIP:*)
      reason="${target_repo#SKIP:}"
      lines+=("SKIP $reason $cand")
      continue ;;
  esac

  res=$(query_gh_item "$num" "$target_repo")
  if [ $? -ne 0 ] || [ -z "$res" ]; then
    lines+=("SKIP 404 $cand")
    continue
  fi

  state=$(jq -r '.state // ""' <<<"$res" 2>/dev/null)
  closedAt=$(jq -r '.closedAt // ""' <<<"$res" 2>/dev/null)

  if [ "$state" = "CLOSED" ] || [ "$state" = "MERGED" ]; then
    n_closed=$((n_closed + 1))
    size=$(du -sh "$cand" 2>/dev/null | awk '{print $1}')
    [ -n "$closedAt" ] || closedAt="unknown"
    if [ "$delete" = "yes" ]; then
      if rm -rf "$cand"; then
        lines+=("DELETED $cand")
      else
        lines+=("FAILED $cand")
        failed=1
      fi
    else
      lines+=("CLOSED $closedAt $size $cand")
    fi
  elif [ "$state" = "OPEN" ]; then
    n_open=$((n_open + 1))
    lines+=("OPEN $cand")
  else
    lines+=("SKIP $state $cand")
  fi
done

n_empty=${#empty_dirs[@]}
for ed in "${empty_dirs[@]}"; do
  if [ "$delete" = "yes" ]; then
    # Only rmdir: a directory that gained content since the scan is skipped, never removed.
    if rmdir "$ed" 2>/dev/null; then
      lines+=("DELETED $ed")
    else
      lines+=("SKIP NOT-EMPTY $ed")
    fi
  else
    lines+=("EMPTY $ed")
  fi
done

for line in "${lines[@]}"; do
  echo "$line"
done

printf '%d closed candidates, %d open, %d empty dirs, %d loose files at the top level\n' \
  "$n_closed" "$n_open" "$n_empty" "$loose_files"
exit "$failed"

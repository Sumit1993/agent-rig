#!/bin/bash
# resolve-verified.sh <pr-number> [--repo owner/name]
# Batch-resolve review threads verified by the claude review lane.
# Spec: s3-finding-envelope.md Section 6.3 and Section 8.3.
#
# Usage:
#   resolve-verified.sh <pr>
#   resolve-verified.sh <pr> --repo owner/name
#
# Requires: gh (GitHub CLI, authenticated) with graphql capability.
set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
pr="${1:?usage: resolve-verified.sh <pr-number> [--repo owner/name]}"
shift

repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:?--repo requires owner/name}"; shift 2 ;;
    *) echo "resolve-verified: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$repo" ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi

echo "resolve-verified: repo=$repo pr=$pr"

# ---------------------------------------------------------------------------
# Helpers: lineage and run provenance validation
# ---------------------------------------------------------------------------
declare -A lineage_cache
declare -A run_cache_valid
declare -A run_cache_reason

# Check if sha is an ancestor of pr_head locally or via GitHub API.
# Spec: s3-finding-envelope.md Section 6.3.
is_ancestor_commit() {
  local sha="$1"
  local head="$2"
  local cache_key="${sha}:${head}"

  if [[ -n "${lineage_cache[$cache_key]:-}" ]]; then
    return "${lineage_cache[$cache_key]}"
  fi

  if git cat-file -e "${sha}^{commit}" 2>/dev/null && git cat-file -e "${head}^{commit}" 2>/dev/null; then
    if git merge-base --is-ancestor "$sha" "$head" 2>/dev/null; then
      lineage_cache["$cache_key"]=0
      return 0
    else
      lineage_cache["$cache_key"]=1
      return 1
    fi
  fi

  local status
  status=$(gh api "repos/$repo/compare/$sha...$head" --jq '.status' 2>/dev/null || echo "error")
  if [[ "$status" == "ahead" || "$status" == "identical" ]]; then
    lineage_cache["$cache_key"]=0
    return 0
  else
    lineage_cache["$cache_key"]=1
    return 1
  fi
}

# Validate run workflow path and head SHA lineage.
# Spec: s3-finding-envelope.md Section 6.2.
validate_run() {
  local run_id="$1"
  local pr_head="$2"

  if [[ -n "${run_cache_valid[$run_id]:-}" ]]; then
    return "${run_cache_valid[$run_id]}"
  fi

  local run_json
  run_json=$(gh api "repos/$repo/actions/runs/$run_id" 2>/dev/null || echo "null")
  if [[ -z "$run_json" || "$run_json" == "null" ]]; then
    run_cache_valid["$run_id"]=1
    run_cache_reason["$run_id"]="run $run_id not found or API error"
    return 1
  fi

  local run_path run_head_sha
  run_path=$(printf '%s' "$run_json" | jq -r '.path // empty')
  run_head_sha=$(printf '%s' "$run_json" | jq -r '.head_sha // empty')

  if [[ "$run_path" != ".github/workflows/claude-code-review.yml"* ]]; then
    run_cache_valid["$run_id"]=1
    run_cache_reason["$run_id"]="run $run_id workflow is '$run_path', expected .github/workflows/claude-code-review.yml"
    return 1
  fi

  if [[ -z "$run_head_sha" ]]; then
    run_cache_valid["$run_id"]=1
    run_cache_reason["$run_id"]="run $run_id head SHA is empty"
    return 1
  fi

  if ! is_ancestor_commit "$run_head_sha" "$pr_head"; then
    run_cache_valid["$run_id"]=1
    run_cache_reason["$run_id"]="run $run_id head SHA ($run_head_sha) is not in PR lineage"
    return 1
  fi

  run_cache_valid["$run_id"]=0
  run_cache_reason["$run_id"]=""
  return 0
}

# ---------------------------------------------------------------------------
# 1. GraphQL: fetch all review threads for this PR
#    Keep unresolved threads whose root author matches ^claude(\[bot\])?$
# ---------------------------------------------------------------------------
echo "Fetching review threads …"

threads_json="[]"
cursor="null"
pr_head=""

while true; do
  page=$(gh api graphql -f query='
    query($owner:String!,$name:String!,$pr:Int!,$cursor:String) {
      repository(owner:$owner,name:$name) {
        pullRequest(number:$pr) {
          headRefOid
          reviewThreads(first:100,after:$cursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              isResolved
              path
              comments(first:100) {
                nodes {
                  databaseId
                  body
                  createdAt
                  author { login }
                }
              }
            }
          }
        }
      }
    }' \
    -f owner="${repo%%/*}" \
    -f name="${repo##*/}" \
    -F pr="$pr" \
    -f cursor="$cursor" \
    --jq '.data.repository.pullRequest')

  if [[ -z "$page" || "$page" == "null" ]]; then
    echo "resolve-verified: unable to fetch review threads for PR #$pr." >&2
    exit 1
  fi

  if [[ -z "$pr_head" ]]; then
    pr_head=$(printf '%s' "$page" | jq -r '.headRefOid // empty')
  fi

  nodes=$(printf '%s' "$page" | jq '.reviewThreads.nodes // []')
  threads_json=$(printf '%s\n%s' "$threads_json" "$nodes" | jq -s 'add')

  has_next=$(printf '%s' "$page" | jq -r '.reviewThreads.pageInfo.hasNextPage')
  [[ "$has_next" == "true" ]] || break
  cursor=$(printf '%s' "$page" | jq -r '.reviewThreads.pageInfo.endCursor')
done

if [[ -z "$pr_head" ]]; then
  pr_head=$(gh api "repos/$repo/pulls/$pr" --jq '.head.sha' 2>/dev/null || echo "")
fi

if [[ -z "$pr_head" ]]; then
  echo "resolve-verified: unable to determine head SHA for PR #$pr." >&2
  exit 1
fi

# Filter: unresolved, root author matches ^claude(\[bot\])?$
claude_threads=$(printf '%s' "$threads_json" | jq -c '
  [.[] | select(
    .isResolved == false
    and (.comments.nodes | length > 0)
    and (.comments.nodes[0].author.login | test("^claude(\\[bot\\])?$"))
  ) | {
    id: .id,
    path: (.path // .comments.nodes[0].path // "(no path)"),
    comments: .comments.nodes
  }]')

thread_count=$(printf '%s' "$claude_threads" | jq 'length')
echo "  Unresolved claude[bot] threads: $thread_count"

if [[ "$thread_count" -eq 0 ]]; then
  echo "Nothing to do: no unresolved claude[bot] threads on PR #$pr."
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Per-thread marker scanning and validation
# ---------------------------------------------------------------------------
verified_ids=()
other_ids=()

marker_regex='<!--[[:space:]]*claude-finding-addressed[[:space:]]+sha=([0-9a-fA-F]{7,40})[[:space:]]+run=([0-9]+)[[:space:]]*-->'

while IFS= read -r t; do
  tid=$(printf '%s' "$t" | jq -r '.id')
  path=$(printf '%s' "$t" | jq -r '.path')

  found_marker=0
  marker_sha=""
  run_id=""
  reply_author=""

  num_comments=$(printf '%s' "$t" | jq '.comments | length')
  for ((i=1; i<num_comments; i++)); do
    c_body=$(printf '%s' "$t" | jq -r ".comments[$i].body // empty")
    c_author=$(printf '%s' "$t" | jq -r ".comments[$i].author.login // empty")

    if [[ "$c_body" =~ $marker_regex ]]; then
      found_marker=1
      marker_sha="${BASH_REMATCH[1]}"
      run_id="${BASH_REMATCH[2]}"
      reply_author="$c_author"
    fi
  done

  if [[ "$found_marker" -eq 0 ]]; then
    other_ids+=("$tid")
    printf "  OTHER      %s  |  (no marker)\n" "$path"
    continue
  fi

  reject_reason=""
  if [[ ! "$reply_author" =~ ^claude(\[bot\])?$ ]]; then
    reject_reason="marker author '$reply_author' is not claude[bot]"
  elif ! validate_run "$run_id" "$pr_head"; then
    reject_reason="${run_cache_reason[$run_id]}"
  elif ! is_ancestor_commit "$marker_sha" "$pr_head"; then
    reject_reason="marker SHA ($marker_sha) is not in PR lineage"
  fi

  if [[ -n "$reject_reason" ]]; then
    other_ids+=("$tid")
    printf "  OTHER      %s  |  rejected marker: %s\n" "$path" "$reject_reason"
  else
    verified_ids+=("$tid")
    printf "  VERIFIED   %s  |  marker sha=%s run=%s\n" "$path" "$marker_sha" "$run_id"
  fi
done < <(printf '%s' "$claude_threads" | jq -c '.[]')

# ---------------------------------------------------------------------------
# 3. Summary and confirm
# ---------------------------------------------------------------------------
echo ""
echo "Summary: ${#verified_ids[@]} VERIFIED thread(s) to resolve, ${#other_ids[@]} OTHER (untouched)."

if [[ ${#verified_ids[@]} -eq 0 ]]; then
  echo "Nothing to resolve: no threads with a valid verification marker."
  exit 0
fi

printf "Resolve %d verified thread(s)? [y/N] " "${#verified_ids[@]}"
read -r answer < /dev/tty 2>/dev/null || read -r answer || answer="n"
if [[ "${answer,,}" != "y" && "${answer,,}" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Resolve each VERIFIED thread via GraphQL mutation
# ---------------------------------------------------------------------------
failures=0
for tid in "${verified_ids[@]}"; do
  result=$(gh api graphql -f query='
    mutation($threadId:ID!) {
      resolveReviewThread(input:{threadId:$threadId}) {
        thread { id isResolved }
      }
    }' \
    -f threadId="$tid" \
    --jq '.data.resolveReviewThread.thread.isResolved' 2>&1) || true

  if [[ "$result" == "true" ]]; then
    echo "  resolved: $tid"
  else
    echo "  FAILED to resolve: $tid (got: $result)" >&2
    failures=$((failures + 1))
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "resolve-verified: $failures mutation(s) failed." >&2
  exit 1
fi

echo "Done: ${#verified_ids[@]} thread(s) resolved."

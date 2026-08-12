#!/bin/bash
# resolve-verified.sh <pr-number> [--repo owner/name]
# Consume the newest "Code review — verification round" comment posted by the
# claude review lane and batch-resolve every thread the reviewer marked
# "verified fixed".  Threads marked "not addressed" (or with no verdict) are
# printed for operator judgment but are never touched.
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
# 1. GraphQL — fetch all review threads for this PR
#    Keep unresolved threads whose root author matches ^claude(\[bot\])?$
# ---------------------------------------------------------------------------
echo "Fetching review threads …"

# We paginate via endCursor; GitHub caps at 100 nodes per page.
threads_json="[]"
cursor="null"
while true; do
  page=$(gh api graphql -f query='
    query($owner:String!,$name:String!,$pr:Int!,$cursor:String) {
      repository(owner:$owner,name:$name) {
        pullRequest(number:$pr) {
          reviewThreads(first:100,after:$cursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              isResolved
              comments(first:1) {
                nodes {
                  databaseId
                  author { login }
                  path
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
    --jq '.data.repository.pullRequest.reviewThreads')

  nodes=$(printf '%s' "$page" | jq '.nodes')
  threads_json=$(printf '%s\n%s' "$threads_json" "$nodes" | jq -s 'add')

  has_next=$(printf '%s' "$page" | jq -r '.pageInfo.hasNextPage')
  [[ "$has_next" == "true" ]] || break
  cursor=$(printf '%s' "$page" | jq -r '.pageInfo.endCursor')
done

# Filter: unresolved, root author matches ^claude(\[bot\])?$
claude_threads=$(printf '%s' "$threads_json" | jq -c '
  [.[] | select(
    .isResolved == false
    and (.comments.nodes[0].author.login | test("^claude(\\[bot\\])?$"))
  ) | {
    id: .id,
    databaseId: (.comments.nodes[0].databaseId | tostring),
    path: (.comments.nodes[0].path // "(no path)")
  }]')

thread_count=$(printf '%s' "$claude_threads" | jq 'length')
echo "  Unresolved claude[bot] threads: $thread_count"

if [[ "$thread_count" -eq 0 ]]; then
  echo "Nothing to do — no unresolved claude[bot] threads on PR #$pr."
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. REST — fetch issue comments, find newest verification-round comment
# ---------------------------------------------------------------------------
echo "Fetching issue comments …"

verification_comment=$(gh api "repos/$repo/issues/$pr/comments?per_page=100" \
  --paginate \
  --jq '[.[] | select(.body | startswith("## Code review — verification round"))] | last')

if [[ -z "$verification_comment" || "$verification_comment" == "null" ]]; then
  echo "resolve-verified: no verification-round comment found on PR #$pr." >&2
  echo "Run the verification lane first, then re-run this script."
  exit 1
fi

comment_body=$(printf '%s' "$verification_comment" | jq -r '.body')

# ---------------------------------------------------------------------------
# 3. Parse verdict table: extract discussion_r<id> → verdict cell
#    Table rows look like:
#    | https://…/pull/N#discussion_r<id> | verified fixed in <sha> |
# ---------------------------------------------------------------------------
declare -A verdicts  # databaseId -> verdict string

while IFS= read -r line; do
  # Skip lines that don't start with | and contain a discussion_r anchor
  if [[ "$line" != *"discussion_r"* ]]; then
    continue
  fi
  # Extract comment id
  if [[ "$line" =~ discussion_r([0-9]+) ]]; then
    db_id="${BASH_REMATCH[1]}"
  else
    continue
  fi
  # Extract verdict cell: everything after the second | up to the third |
  # Row format: | url | verdict |
  # Split on | and take field 3 (0-indexed: fields[2])
  IFS='|' read -ra fields <<< "$line"
  if [[ ${#fields[@]} -lt 3 ]]; then
    continue
  fi
  verdict=$(printf '%s' "${fields[2]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  verdicts["$db_id"]="$verdict"
done <<< "$comment_body"

# ---------------------------------------------------------------------------
# 4. Partition threads into VERIFIED / OTHER
# ---------------------------------------------------------------------------
verified_ids=()
other_ids=()

while IFS= read -r t; do
  tid=$(printf '%s' "$t" | jq -r '.id')
  dbid=$(printf '%s' "$t" | jq -r '.databaseId')
  path=$(printf '%s' "$t" | jq -r '.path')
  verdict="${verdicts[$dbid]:-}"

  if [[ "${verdict,,}" == verified\ fixed* ]]; then
    verified_ids+=("$tid")
    printf "  VERIFIED   %s  |  %s\n" "$path" "$verdict"
  else
    other_ids+=("$tid")
    if [[ -n "$verdict" ]]; then
      printf "  OTHER      %s  |  %s\n" "$path" "$verdict"
    else
      printf "  OTHER      %s  |  (no verdict)\n" "$path"
    fi
  fi
done < <(printf '%s' "$claude_threads" | jq -c '.[]')

# ---------------------------------------------------------------------------
# 5. Summary and confirm
# ---------------------------------------------------------------------------
echo ""
echo "Summary: ${#verified_ids[@]} VERIFIED thread(s) to resolve, ${#other_ids[@]} OTHER (untouched)."

if [[ ${#verified_ids[@]} -eq 0 ]]; then
  echo "Nothing to resolve — no threads with a 'verified fixed' verdict."
  exit 0
fi

printf "Resolve %d verified thread(s)? [y/N] " "${#verified_ids[@]}"
read -r answer < /dev/tty
if [[ "${answer,,}" != "y" && "${answer,,}" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# ---------------------------------------------------------------------------
# 6. Resolve each VERIFIED thread via GraphQL mutation
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

echo "Done — ${#verified_ids[@]} thread(s) resolved."

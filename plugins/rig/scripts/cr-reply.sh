#!/bin/bash
# cr-reply.sh <pr> <root-comment-id> <message...> — in-thread reply to a
# CodeRabbit review thread. Always reply in-thread, never only a top-level PR
# comment: threads must resolve or required_review_thread_resolution rulesets
# block merge. Never self-resolve threads via the GraphQL mutation — that
# bypasses the review gate.
set -eu
pr="${1:?usage: cr-reply.sh <pr> <root-comment-id> <message...>}"
id="${2:?missing root comment id}"
shift 2
[ $# -gt 0 ] || { echo "cr-reply: empty message" >&2; exit 2; }
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
gh api "repos/$repo/pulls/$pr/comments/$id/replies" -f body="$*" --jq '.html_url'

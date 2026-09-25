# CodeRabbit routine

Each hourly run merges the operator's pull requests whose review came back clean and asks CodeRabbit to review at most one more. CodeRabbit gives the operator one review per hour across every repo. The rules below came over from the Actions queue that was removed in prismalens/gh-workflows#217. That queue matched CodeRabbit's wording in code (prismalens/gh-workflows#216), so here the model reads CodeRabbit's replies instead.

Never edit code, push, sleep, wait or send notifications. Post nothing except the merges and the single summon described below.

## 1. Read the digest

`digest.json` from `digest.py` lists every open pull request in the six repos. Pull requests marked `excluded` (Dependabot, release-please, other authors, drafts) are never merged or summoned. Only open a PR with the GitHub tools when a rule below says to.

## 2. Merge

Merge a pull request only when all of these hold:

- `hold_label` is null.
- `mergeable_state` is `clean`, `unstable` or `has_hooks`. `blocked` means a required check or rule is still unmet.
- `threads.all_read` is true, `threads.unresolved` is 0 and `threads.resolved_by_non_reviewer` is empty. If `threads` says `unavailable`, get the threads with the GitHub MCP `pull_request_read` tool and apply the same rules.
- The pull request is either `docs_only`, or it meets both of these:
  - CodeRabbit finished a clean review of `head`. That means either a review object with `is_head: true` that reports zero actionable comments, or a CodeRabbit comment that says the review of the head found nothing actionable. A rate-limit notice, a "review skipped" or "paused" note, or an acknowledgement is not a review.
  - When `claude_lane.required` is true and `skip_label` is false, `latest_liveness` says it reviewed a SHA that `head` starts with.

To merge, run `gh pr merge <n> -R <repo> --squash --match-head-commit <head>`. When `merge_queue` is true, enqueue the pull request instead: `gh api graphql -f query='mutation($p:ID!,$h:GitObjectID!){enqueuePullRequest(input:{pullRequestId:$p,expectedHeadOid:$h}){mergeQueueEntry{state}}}' -f p=<node id> -f h=<head>`, getting the node id from `gh pr view <n> -R <repo> --json id`. If a merge fails, report the error and move on.

## 3. Summon one

Skip this step if a CodeRabbit comment across the digest, read by its `updated_at`, is a rate-limit notice whose stated wait has not yet passed. Also skip it if `operator_last_summon.age_min` is under 57.

A pull request that is not merged is a candidate when all of these hold:

- It is not `docs_only`.
- CodeRabbit has not reviewed `head`.
- `head_age_min` is at least 20.
- No summon is pending. A summon is pending when `last_summon.after_head` is true and `first_coderabbit_reply_after_summon` is null, or is anything other than a rate-limit notice, a misparse ("initiate chat"), or a refusal to re-review already reviewed commits.

A candidate is a **re-review** if CodeRabbit reviewed an earlier commit. It qualifies only when `threads.coderabbit_unresolved_without_operator_reply` is 0; otherwise its fixes are still pending. Any other candidate is **new**.

Pick re-reviews first, ordered by the oldest `head_committed_at`. Then pick new ones, ordered by the oldest `created_at`. Post exactly one top-level comment on the pick: `@coderabbitai review`, or `@coderabbitai full review` if its last reply refused to re-review already reviewed commits. Use `gh pr comment <n> -R <repo> --body '<body>'`.

## 4. Report

Report in under 12 lines:
- what the previous summon got
- each merge, or why nothing merged
- the summon posted, or why none
- how many pull requests are waiting, per repo

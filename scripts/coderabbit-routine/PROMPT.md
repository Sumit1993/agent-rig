# CodeRabbit routine

Each hourly run merges the operator's pull requests whose review came back clean and asks CodeRabbit to review at most one more. CodeRabbit gives the operator one review per hour across every repo. The rules below came over from the Actions queue that was removed in prismalens/gh-workflows#217. That queue matched CodeRabbit's wording in code (prismalens/gh-workflows#216), so here the model reads CodeRabbit's replies instead.

Never edit code, push, sleep, wait or send notifications. Post nothing except the merges and the single summon described below.

## 1. Read the digest

`python3 digest.py > /tmp/digest.json` (run from this directory) lists every open pull request in the six repos. Pull requests marked `excluded` (Dependabot, release-please, other authors, drafts) are never merged or summoned. Only open a PR with the GitHub tools when a rule below says to.

## 2. Merge

Merge a pull request only when all of these hold:

- `hold_label` is null.
- `mergeable_state` is `clean`, `unstable` or `has_hooks`. `blocked` means a required check or rule is still unmet.
- Its review threads are clean: none unresolved, and each resolved thread was resolved by the reviewer that opened it (a `claude` thread may be resolved by `github-actions`). Cloud sessions cannot reach GitHub GraphQL, so `threads` usually says `unavailable`; check the threads only for PRs that pass every other rule, with the GitHub MCP `pull_request_read` tool (`get_review_comments`). If neither source answers, do not merge.
- The pull request is either `docs_only`, or it meets both of these:
  - CodeRabbit finished a clean review of `head`. That means either a review object with `is_head: true` that reports zero actionable comments, or a CodeRabbit comment that says the review of the head found nothing actionable. A rate-limit notice, a "review skipped" or "paused" note, or an acknowledgement is not a review.
  - When `claude_lane.required` is true and `skip_label` is false, `latest_liveness` says it reviewed a SHA that `head` starts with.

To merge, run `python3 act.py merge <repo> <n> <head>`. When `merge_queue` is true, GraphQL is needed to enqueue and the session cannot reach it: list the PR as ready to enqueue in the report instead. If a merge fails, report the error and move on.

## 3. Summon one

Skip this step if a CodeRabbit comment across the digest, read by its `updated_at`, is a rate-limit notice whose stated wait has not yet passed. Also skip it if `operator_last_summon.age_min` is under 57.

A pull request that is not merged is a candidate when all of these hold:

- It is not `docs_only`.
- CodeRabbit has not reviewed `head`.
- `head_age_min` is at least 20.
- No summon is pending. A summon is pending when `last_summon.after_head` is true and `first_coderabbit_reply_after_summon` is null, or is anything other than a rate-limit notice or a misparse ("initiate chat"). Every reply to a summon ends with the note that CodeRabbit "does not re-review already reviewed commits". That note is boilerplate, not a refusal.

A candidate is a **re-review** if CodeRabbit reviewed an earlier commit. It qualifies only when `threads.coderabbit_unresolved_without_operator_reply` is 0; otherwise its fixes are still pending. Any other candidate is **new**.

Pick re-reviews first, ordered by the oldest `head_committed_at`. Then pick new ones, ordered by the oldest `created_at`. Post exactly one summon on the pick with `python3 act.py comment <repo> <n> '@coderabbitai review'`. `act.py` adds the hidden `summoned-by` marker. Never post `full review`: it spends the same slot to re-read commits that were already reviewed.

## 4. Report

Report in under 12 lines:
- what the previous summon got, and who posted it (`last_summon.by`)
- each merge, or why nothing merged
- the summon posted, or why none
- how many pull requests are waiting, per repo

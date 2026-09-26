# CodeRabbit routine

Each hourly run asks CodeRabbit to review at most one of the operator's pull requests. CodeRabbit gives the operator one review per hour across every repo. The routine never merges: merging belongs to a local session, when the operator asks for it (`compass`). The rules came over from the Actions queue that was removed in prismalens/gh-workflows#217. That queue matched CodeRabbit's wording in code (prismalens/gh-workflows#216), so here the model reads CodeRabbit's replies instead.

Never edit code, push, merge, sleep, wait or send notifications. Post nothing except the single summon described below. If `digest.py` or `act.py` fails, report the error and stop; the scripts are fixed in a local session, never in this run.

## 1. Read the digest

Run `python3 digest.py > /tmp/digest.json` from this directory. It lists every open pull request in the six repos. Pull requests marked `excluded` (Dependabot, release-please, other authors, drafts) are never summoned.

## 2. Budget

Post nothing this run in either of these cases:
- A CodeRabbit comment anywhere in the digest, read by its `updated_at`, is a rate-limit notice whose stated wait has not yet passed.
- `coderabbit_last_review.age_min` is under 57. CodeRabbit's hourly window runs from the last review it accepted.
- `operator_last_summon.age_min` is under 57 and that summon has no CodeRabbit reply yet.

## 3. Pick one

A pull request is a candidate when all of these hold:

- It is not `docs_only`.
- CodeRabbit has not reviewed `head`. `coderabbit_reviewed_head: true` counts. So does a CodeRabbit comment saying it finished a review that covers `head`. A rate-limit notice, a "review skipped" or "paused" note, or an acknowledgement does not.
- `head_age_min` is at least 20.
- No summon is pending. A summon is pending when `last_summon.after_head` is true and `first_coderabbit_reply_after_summon` is null, or is anything other than a rate-limit notice or a misparse ("initiate chat"). Every reply to a summon ends with the note that CodeRabbit "does not re-review already reviewed commits". That note is boilerplate, not a refusal.

A candidate is a **re-review** if CodeRabbit reviewed an earlier commit. It qualifies only when `coderabbit_threads_without_operator_reply` is 0; otherwise its fixes are still pending. Any other candidate is **new**.

A re-review also has to buy something. Every review of a fix commit finds a smaller nit in the fix, so summoning on each fix loops forever (prismalens/gh-workflows#222). Read `since_coderabbit_review` against `coderabbit_threads` and judge whether the commits after the last review carry work CodeRabbit has not seen. A commit that answers a thread (`operator_reply` names it) and that CodeRabbit confirmed in `coderabbit_after_reply` is already verified: skip the PR if that is all there is. Summon when a commit adds anything beyond those fixes, such as a new feature, a refactor, or files that no thread touches, or when CodeRabbit disputed a fix or has not replied to one. A small diff confined to the threaded files leans toward skip. When unsure, summon. Name each skipped PR and its reason in the report.

Pick re-reviews first, ordered by the oldest `head_committed_at`. Then pick new ones, ordered by the oldest `created_at`. Summon the pick with `python3 act.py <repo> <n> '@coderabbitai review'`. `act.py` adds the hidden `summoned-by` marker. Never post `full review`: it spends the same slot to re-read commits that were already reviewed.

## 4. Report

Report in under 10 lines:
- what the previous summon got, and who posted it (`last_summon.by`)
- the summon posted, or why none
- how many pull requests are waiting, per repo

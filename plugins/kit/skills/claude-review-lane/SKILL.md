---
name: claude-review-lane
description: "How our Claude review lane (`claude[bot]`) behaves on any PR of any age: reading the liveness comment's verdicts, the ways the lane stays quiet (skipped author, auto-pause, fork head, self-skip), the summon grammar (`@claude review`, `@claude full review`, the per-run `--model` override), verification rounds, and who may resolve a `claude[bot]` thread. Load when a `claude[bot]` thread or a liveness comment is in front of you, when the lane has gone quiet or a review is missing, when deciding whether to summon or re-summon, and when judging whether a head has actually been reviewed before it merges. Arming a watcher on a PR this session raised is `pr-watch` instead."
metadata:
  version: "3.0.0"
---

# The Claude review lane

The lane is `claude-code-review.yml` in `prismalens/gh-workflows`, called by a thin stub in each consumer repo. This skill is how an operator works with it on any open PR: reading what it said, knowing when it said nothing, summoning it. `AGENTS.md` decides which reviewer a PR gets. `pr-watch` covers watching a PR this session raised, the CodeRabbit lane, the merge mechanics, and the upkeep of `claude-kit/docs/pr-review-process.html`. Stories are in `docs/incidents.md`.

Callee truth is the workflow file, never a local checkout:

```bash
gh api repos/prismalens/gh-workflows/contents/.github/workflows/claude-code-review.yml --jq .content | base64 -d
gh api repos/prismalens/gh-workflows/contents/README.md --jq .content | base64 -d
```

## 1. Two standing rules

- Silence is never approval. No posted findings means no machine review on record for this head. Treat it exactly as a rate-limited one.
- A green job is not evidence. The lane publishes no commit status and gates nothing. A run can finish `success` having posted zero comments, and a self-skip reports nothing. Read for posted output, never a check's colour.

The liveness comment is the only thing that certifies a review happened, and it certifies only what was posted.

## 2. The liveness comment

Every run that reaches the reviewer upserts one comment by `github-actions[bot]`:

```
<!-- claude-review-liveness rounds=N sha=<40-hex> -->
**Claude review lane** — [run](...): <verdict>
```

Match the prefix `<!-- claude-review-liveness`, never the whole marker. `rounds=` counts automatic rounds that reviewed. `sha=` is the last head on which the lane published output; it advances on posted evidence only, never on a job result, and is omitted when there is no baseline. Nothing consumes `sha=` yet.

Eight verdicts. Only the first two mean the head was reviewed:

| Verdict text | Reviewed? | What to do |
|---|---|---|
| `reviewed <sha> and posted N inline / M summary comment(s)` | Yes | Work the threads |
| `reviewed <sha> (incremental from <base>) and posted N inline / M summary comment(s)` | Yes | Work the threads |
| `finished on <sha> (job result: ...) but posted **nothing**` | No | Read the run log for tool denials, then `@claude full review`. If that also comes back empty, escalate to `coderabbit_review` or a model pass |
| `re-checked open threads at <sha>: N resolved / M left open` | No, threads only | Not review evidence for this head; `8/8 resolved` is not clean |
| `ran a verification round on <sha> (mutate result: ...) but posted **nothing**` | No | Same escalation as the silent full review |
| `auto-paused after N automatic rounds at <sha>` | No | `@claude review`, or hand the pause back to whoever owns the PR; never wait for the next push |
| `did not run at <sha>: no CLAUDE_CODE_OAUTH_TOKEN reached this lane` | No | The stub failed to map the secret across the owner boundary. Fix the stub; `secrets: inherit` does not cross owners, so the mapping must be explicit |
| `no new commits since <sha> was last reviewed; nothing to re-review` | No | Nothing; the prior review stands |

No liveness comment at all is its own signal, and the costliest trap: the comment is upserted only when the review job ran, so a PR the lane never admitted has nothing to read and a watcher waiting for one waits forever.

## 3. Admission, and every way the lane stays quiet

Automatic rounds fire on `pull_request` for same-repo heads. A summon or an in-thread reply also needs write access to the repository, checked live against the collaborators API by the `admit` action, plus an explicit verb for summons and an open PR.

Admission is not `author_association`. That field is repo-scoped and payload-dependent, so a webhook and the REST API can disagree on the same comment. Never diagnose a refusal from it (`author-association-misdiagnosis`).

Five ways a PR gets no review. The first four leave no liveness comment:

1. Skipped author. An author in `skip_authors` (default `dependabot[bot]`) gets no automatic round: no review, no verify, no liveness comment. Matching is exact-login on a delimiter-wrapped list, so `bot` never collides with `dependabot[bot]`. A summon bypasses the list.
2. Draft PR. Automatic rounds skip drafts on both the stub and the callee. A summon reaches a draft anyway.
3. Fork head. Never machine-reviewed: GitHub withholds secrets from fork code and the lane avoids `pull_request_target`. A `fork-notice` job upserts a comment marked `<!-- claude-review-fork-notice -->` pointing at the `coderabbit_review` label. A summon does not override this in v1. When the fork run holds a read-only `GITHUB_TOKEN` (the default unless the repository enables "Send write tokens to workflows from fork pull requests") the comment is denied and the job falls back to a workflow warning annotation carrying the same text, easy to miss.
4. Self-skip on the workflow itself. A PR that edits `.github/workflows/claude-code-review.yml` is never reviewed: `claude-code-action` self-skips on workflow-validation mismatch. A security control, and the one case a summon cannot fix; label the PR `coderabbit_review`. A self-skip leaves the action's conclusion empty, identical to a tool denial that aborted midway, except a denial may have posted findings first. The liveness comment says which, the run log says why.
5. Auto-paused. After `auto_pause_rounds` automatic rounds (default 5) the lane posts the auto-paused verdict instead of reviewing. This one does leave a comment. A paused PR is not reviewed on push, so a wait keyed on the next push has no end (`auto-pause-wait-forever`). A summon resets the counter and resumes the lane, but only when the round posts review output; a green summon that posted nothing leaves the count untouched.

### Refusal versus cancellation

A run that concluded `cancelled` with zero jobs executed nothing and says nothing about admission; it was evicted from its concurrency group before any `if:` ran. A run that concluded `skipped` reached the gate and was refused. Only the second is evidence (`cancelled-vs-skipped-confusion`). Bot-authored comments now route to a per-run throwaway group; a `cancelled` review-comment run with zero jobs means that repo's stub predates the fix (`verify-round-reply-eviction`).

## 4. Summon grammar

Bare PR comments, org members only. The body is read only by workflow `contains()` expressions and never reaches a prompt, so a summon carries no instructions. Put context in the PR body.

| Comment | Effect |
|---|---|
| `@claude review` | Incremental. The lane picks its mode: a verify round when unresolved `claude[bot]` threads exist, else a normal review. The only resume for an auto-paused PR |
| `@claude full review` | From scratch, dedup disabled for that run. The fix for a round that finished green having published nothing, which is what dedup silently causes (`dedup-silent-empty-review`). Also the only way past a verify round: it short-circuits ahead of the unresolved-thread check |
| `@claude review --model opus` | Incremental on `claude-opus-5` for that run only. `@claude review --model sonnet` picks `claude-sonnet-5` back |

`default_model` is `claude-sonnet-5` on purpose: review is the highest-volume Claude spend across the consumer repos, so escalation is per run. Which model IDs resolve at all is set by the repo's `CLAUDE_CODE_OAUTH_TOKEN` tier, not the input.

- The override is an allowlist of two fixed phrases, matched whole. `@claude full review --model opus` does not switch models; `@claude review --model opus` is not a substring of it, so the run uses `default_model`. No phrase combines a full review with a model override. Pick one.
- Anything else after `--model`, `haiku` included, is ignored rather than rejected, and the run uses `default_model`.
- One summon per round; each mention is a full agent run. Batch every fix, push, then summon once. A summon never cancels an in-flight automatic round, it queues behind it. A push supersedes anything queued, summons included.

## 5. Verification rounds

A verify round re-judges the unresolved `claude[bot]` threads instead of re-reviewing. A push never produces one. A push lands on incremental or review. Only a non-bot reply in a thread, or a summon on a PR holding unresolved threads, asks for a re-check. This explains most "why is this still blocked" confusion: you push the fix, the liveness comment reports a review, the thread stays open. A push is a claim about code, a reply is a claim about a specific finding, and only the second names which threads to re-check.

### The five modes

One run resolves to one mode, named in the run log. A `pull_request` event reaches only the first three.

| Mode | Reached by | What it does |
|---|---|---|
| `skip` | any trigger | Nothing reviewed. Reason is one of `no-token`, `skipped-author`, `paused`, `no-new-commits` |
| `review` | any trigger | Full review from scratch. Also the fallback when an incremental range cannot be trusted: `no-baseline`, `baseline-gone`, `diverged`, `range-too-large`, `identical-summon` |
| `incremental` | push, or `@claude review` | Reviews only the `baseline..head` range off the liveness marker |
| `review-full` | `@claude full review` only | From scratch with dedup disabled |
| `verify` | non-bot in-thread reply, or `@claude review` on a PR with unresolved threads | Re-judges those threads |

How to read a verify round:

- Each unresolved thread gets exactly one of `fixed`, `still_applies`, `cannot_verify`, with the sha and a one-sentence evidence string. `fixed` resolves the thread. The other two post a templated reply citing sha and evidence and leave it open. The verdict judges the code at current head, not what the reply claimed.
- Delta-only review: new findings post as inline comments, a finding an existing thread covers is not re-posted.
- A mandatory summary comment whose first line is exactly `## Code review — verification round`, with a table of thread URL against verdict. Posted even when everything is fixed and nothing is new; its absence means the round did not complete.

## 6. Who resolves a `claude[bot]` thread

The reviewer resolves what it verifies as fixed. A human rules on anything disputed, declined or deferred.

1. Reviewer posts a finding as an inline review thread.
2. A non-bot replies in-thread, asserting fixed in a commit or disputing. The reply is the trigger; a push alone resolves nothing. The lane excludes GitHub App identities so its own reply cannot retrigger it, so an agent replying through a member's credential is admitted.
3. Reviewer re-evaluates against current head.
4. `fixed`: resolved, citing the commit SHA and what was checked.
5. `still_applies` or `cannot_verify`: templated reply citing SHA and evidence, thread stays open.

The model never writes to GitHub. The verify job holds a read-only `GITHUB_TOKEN` and no `id-token: write`, so it cannot resolve, reply, comment, submit a review or merge; it emits schema-validated verdicts only. A separate `mutate` job does every post from its own templates and re-fetches the live threads rather than trusting the verdict artifact. Resolution needs no App credential: `GITHUB_TOKEN` at `contents: write` carries it.

Disputed, declined or deferred findings are resolved by a human and nobody else. Post the disposition in-thread first, then resolve via GraphQL `resolveReviewThread` or the UI. Judgement and scope stay with the operator.

## 7. Before a merge

One question: has posted review output landed on the head about to merge? Only a `reviewed <sha> ...` verdict answers yes. Auto-paused, posted-nothing, a fork notice and no comment at all are the same answer: unreviewed. Summon and wait, or make a deliberate risk decision to merge without one. `pr-watch` owns the merge and queue mechanics.

## 8. Finding labels and parse contract

Every finding opens with a header line of three fields:

```
_<Category>_ | _<Severity>_ | _<Effort>_
```

Example: `_🎯 Functional Correctness_ | _🟠 Major_ | _⚡ Quick win_`

Ten labels across three dimensions:

| Dimension | Labels |
|---|---|
| Category | `Functional Correctness`, `Security & Privacy`, `Maintainability & Guidelines`, `Data Integrity & Integration`, `Stability & Availability` |
| Severity | `Critical`, `Major`, `Minor` |
| Effort | `Quick win`, `Heavy lift` |

- Field grammar `_[<emoji> ]<label>_`, fields separated by ` | `.
- Emoji are presentation only. Strip leading non-ASCII bytes, trim, exact-match the ASCII label. Never compare emoji bytes: two of the ten carry a U+FE0F variant selector and one is text-default.
- Unrecognised label: route to the fallback class `Major / Heavy lift` and log a parse notice. A finding is never dropped.
- Missing header (legacy comments): `Category: Functional Correctness`, `Severity: Major`, `Effort: Heavy lift`.

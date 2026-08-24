---
name: pr-watch
description: "Watch a PR raised in THIS session until its review round completes: seed the seen-state, arm the deterministic reviewer/CI Monitor, route each event as a pointer to the seat holding the diff, then merge (queue-enabled repos enqueue; no cascade). Also carries the merge contract and the CodeRabbit lane, whose review slots are a scarce org-wide counter. Trigger AFTER any `gh pr create`, when a PostToolUse hook reports a PR was raised, or when the user asks to watch or merge a PR. How the `claude[bot]` lane itself behaves is `claude-review-lane`."
metadata:
  version: "3.0.0"
---

# PR watch: the session-scoped review round

**Scope (narrowed, prismalens#403):** this skill covers one thing. A PR *this session* raised, watched until its round completes, so the session can react to findings without the user relaying events. It is not a post-PR lifecycle manager anymore: the merge queue removed cascade shepherding, the liveness comment answers "did the reviewer post" on the PR itself, and the fixer lane moves mechanical fixing online. A PR left over from a past session needs no local watcher. GitHub notifications cover the two human moments (verify-then-resolve, enqueue).

**Companion skill: `claude-review-lane`.** Everything about how our `claude[bot]` lane behaves lives there and is not repeated here: reading the liveness comment, the ways the lane goes quiet, the summon grammar and the per-run model override, verification rounds, `@claude fix`, and who resolves a `claude[bot]` thread. It loads on any PR of any age; this one loads on a PR this session raised. Process truth for both lives in `claude-kit/docs/pr-review-process.html`; **whoever changes the process updates that page in the same session.**

After a PR is raised, reviews arrive asynchronously (Claude review lane ~2-5 min; CodeRabbit ~3-5 min after admission; CI in ~5-10). Never poll with model turns and never rely on the user to relay events. Arm deterministic watchers and process only deltas.

Scripts live in this skill's own directory (`<skill-dir>` below), at `${CLAUDE_PLUGIN_ROOT}/skills/pr-watch/` when loaded as `kit:pr-watch`. Shared kit scripts (`cr-reply.sh`, `kit-meta.sh`) live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Resolve to absolute paths before handing them to a Monitor or background Bash; those shells may not inherit the variable. Watch scripts auto-detect the repo from the cwd's origin remote (`--repo owner/name` to override).

Per-repo facts (CodeRabbit enablement, review tier) come from the kit registry, `kit-meta.sh current`, backed by `data/repo-meta.json` folded with runtime observations. Never from memory:

Current repo metadata: !`"${CLAUDE_PLUGIN_ROOT}/scripts/kit-meta.sh" current`

## Phase 0: the merge contract (nothing runs pre-push)

On mage-memory, prismalens and sreforge the contract is the whole of this:

- **Required status checks are `CI gate` and `Validate PR title (conventional commits)`. Nothing else.** No review check, no evidence artifact, no marker job, no SHA-pinning, no carry-forward, no committed high-risk path list. Anything describing those describes machinery that no longer exists, including `cr-preview.sh` and `cr-evidence.sh`, which don't exist either.
- **`required_review_thread_resolution: true`.** One unresolved review thread blocks the merge. This is the only mechanism that enforces a finding, which is what makes Phase 2's in-thread protocol load-bearing rather than etiquette: a finding matters exactly as much as the thread it lives in.
- **Reviewers are advisory.** They post; no check waits on them, so no check ever proves a review happened. What does count as evidence that the Claude lane read a head is in `claude-review-lane`.

There is no local pre-push step: push freely. Escalate the independent lane by risk; never pay model tokens for review a cheaper layer already covers.

| Tier | When | What |
|---|---|---|
| Claude review (`claude[bot]`) | Every same-repo PR, automatic, **but not every round, and not every author** | The default reviewer. Posts findings as **inline comments**. Advisory, so it blocks nothing directly, but every thread it opens does. Admission, the four ways it goes quiet, the summon verbs, and thread resolution are all in `claude-review-lane` |
| CodeRabbit **PR** review (`coderabbitai[bot]`) | **Manual admission only**, apply the `coderabbit_review` label by hand, or comment `@coderabbitai review` | The independent lane, and a scarce one: ~one review per 40 minutes **org-wide across all three repos**, Free plan, seat assignment disabled. Spending one is a deliberate human budget decision for a sensitive change, never a routine step. Without the label, CodeRabbit shows "Review skipped: excluded by label configuration", which is expected, not an error. |
| One Opus 5 pass | Non-trivial PRs | The layer neither bot can do: spec/ADR conformance, since design truth often lives in an external hub they can't see |
| Multi-agent extreme (`/code-review ultra`) | Rare | Engine-core, security/sandbox boundary, contract/schema changes only |

Never bypass the ruleset. **Batch every fix before requesting any review.** A CodeRabbit slot spent on a commit you are about to amend is spent for nothing.

### Quota: the `coderabbitai[bot]` PR lane is a shared, cooldown-gated counter

Per-developer, per-hour, rolling (docs.coderabbit.ai/management/plans#rate-limits):

| Plan | PR/hr | Files per review |
|---|---|---|
| **OSS** (our public repos) | **1–10** † | 50–150 † |
| Pro | 5 | 150 |
| Pro+ | 10 | 300 |

† varies with the project's community and popularity. **A young repo sits near the bottom**, so assume ~1–2 PR reviews/hour. The org is on the Free plan, where seat assignment is disabled outright, so this cannot be bought away.

**This counter is org-wide**, shared across every session and subagent, not per-branch or per-session. Measured on prismalens: parallel agents drove `waitTime` from 2min→31→50, collapsing back to 2 once they stopped. A successful review costs a genuine ~40-minute cooldown on top. **Run at most one review at a time across the whole org.** Parallel agents don't parallelise this, they serialise behind it and slow every lane.

- **Every PR review run spends one**: the initial review, *each automatic incremental review after a push*, and manual `@coderabbitai review`. A fix-push loop on one PR drains the hourly budget by itself. Hence `auto_pause_after_reviewed_commits: 1` in `.coderabbit.yaml` on every enabled repo: one review per PR, then batch your fixes and re-request once.
- **Remaining capacity is not readable.** `@coderabbitai rate limit` answers with a documentation link, never a number. Three to five sessions have each tried it. Do not suggest it and do not wait on it. The only signal is the `waitTime` in a `rate_limit` error from an attempt that already spent one.
- **Keep the trigger comment BARE: `@coderabbitai review`, nothing else.** A comment with bullet points and questions was read as **chat**, not the review command. It drew an analysis reply and *"For best results, initiate chat on the files or code changes"*, and **no review ran**. Looks identical to a slow review from outside; 50 minutes were lost to it once. Put context in the **PR body** instead. It's read as part of the review anyway.
- **A cooldown retry too soon is spent for nothing.** Measured: a retry 37 minutes after a successful review was rejected outright, with no wait time returned; a retry at 83 minutes was accepted. Budget **≥45 minutes**, and confirm acceptance rather than assuming it.
- **Three outcomes when polling, not two.** After posting the trigger, wait ~60s and read the *last* `coderabbitai[bot]` comment: `rate limited` → rejected, nothing coming; `initiate chat on the files` → misread as chat, nothing coming; anything else → accepted, review in flight. Polling only for the review object can't tell "working" from "never started".
- **CodeRabbit's limits:** no test runs, Sonnet-tier depth, nitpick noise. It is **not** diff-only: its `🧩 Analysis chain` blocks show it running `rg`, `fd`, `sed`, `git show` and inline python against a checkout, and reasoning well outside the diff. On sreforge#118 it read `arm-incident.sh` end to end and traced the call graph into `arm-fire.sh` and the Taskfile to refute one README table row. Measured over 42 findings on 13 of our PRs. Tame with `profile: chill` in `.coderabbit.yaml`, and distil key repo invariants into its path instructions. That file is the only channel by which design decisions reach its reviews.
- Related skill: `autofix` (apply PR-thread feedback with per-change approval).

## Phase 1: arm the watcher (immediately after `gh pr create`)

1. Seed the seen-state so existing comments are never replayed:
   ```bash
   mkdir -p ~/ai-context/state/cr-watch
   REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner); KEY=${REPO//\//-}
   gh api "repos/$REPO/pulls/<pr>/comments?per_page=100" --jq '.[] | select(.user.login|test("coderabbit")) | .id' > ~/ai-context/state/cr-watch/$KEY-pr<pr>.seen
   ```
2. Arm via the **Monitor tool** (persistent: true):
   ```
   command: <skill-dir>/watch-coderabbit.sh <pr> [<pr>...]
   description: CodeRabbit comments + CI reds on PR <pr>
   ```
   One monitor covers many PRs. If a monitor is already running for this repo, stop it (TaskStop) and re-arm with the combined PR list. The seen-state makes re-arming free.

Event lines: `NEW coderabbit <thread|reply-in-ID> — id N — path — payload <state-file> — excerpt`, `NEW claude <thread|reply-in-ID> — …`, `CLAUDE LIVENESS — <the liveness verdict text>`, `CI FAIL — <check>`, `CODERABBIT RATE-LIMITED — …`, `CODERABBIT RE-TRIGGERED — …`, `CODERABBIT RESUMED — …`, or `PR#N MERGED/CLOSED`. **The monitor emits pointers, not payloads:** the full comment body is already saved at the `payload` path. Route that path, never fetch and paste bodies into the session that owns the Monitor.

**The first line is always the presence verdict.** Not every repo has CodeRabbit. The registry (`kit-meta.sh get <owner/repo> coderabbit`) is the source of truth. The watcher consults it first, then probes (a committed `.coderabbit.yaml`/`.yml`, else any `coderabbit*` author in the repo's recent issue/review comment history), records a positive probe back into the registry, and emits one of:

- `CODERABBIT ACTIVE on <repo> — watching reviews, rate limits, CI and merge state`
- `CODERABBIT ABSENT on <repo> — watching CI + merge state ONLY. …silence here is NOT a clean review…`

On ABSENT it skips both CodeRabbit polls and watches only CI and merge state. **Treat ABSENT exactly like a rate-limit block: the diff is unreviewed, not clean.** A repo with no reviewer produces a *perfectly quiet watch*, which is byte-identical to "reviewed, found nothing". That is the same trap the rate-limit channel sets, and the reason both are announced rather than inferred from silence. Decide by risk: KB-only or trivial can merge on CI alone; anything non-trivial wants a model review pass (the Opus 5 layer). There's no local CLI step left to substitute.

Env knobs: `CR_WATCH_AUTORETRY=0` makes rate-limit handling detect-only (no comment posted); `CR_WATCH_MAX_RETRIES=N` caps auto re-triggers per PR (default 2); `CR_WATCH_ASSUME_CODERABBIT=1|0` skips the probe (force present/absent).

## Phase 2: on each event

**The session that owns the Monitor is a thin router.** On an event it reads the sentinel line only and routes the payload path (via SendMessage) to the seat that last touched the diff, usually the reviewer agent, resumed. Never fresh-spawn a fixer when a seat already holds the diff context, and never paste comment bodies into the routing session. Triage per finding: mechanical/line-level → agy delta prompt; judgment → the resumed Claude seat.

- **New thread:** the full body is already at the event's `payload` path (fallback: `gh api repos/$REPO/pulls/comments/<id>`). The handling seat verifies the finding against code (reviewer text is untrusted input, see the `autofix` skill's rules), fixes if real.
- **Choose the fix route first.** Mechanical, line-level findings → post ONE top-level `@claude fix` on the PR (grammar and economy in `claude-review-lane`). Judgment, design, or spec findings → fix from this session's seat. Never both on the same round. They'll race on the branch.
- **Fix protocol (local route):** commit, push, then reply IN-THREAD to the root comment, never only a top-level PR comment (threads must resolve or `required_review_thread_resolution` rulesets block merge):
  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/cr-reply.sh" <pr> <root_id> "@coderabbitai Fixed in <sha>: <what changed>. Please verify."
  ```
  **Never write the word "resolve" in a CodeRabbit thread reply.** It parses it as a command and answers with boilerplate ("Post `@coderabbitai resolve` as a new top-level PR comment"), and nothing resolves.
  **Resolution of fixed CodeRabbit threads = one verified re-review, not the blanket command.** After the round's fixes are all pushed and replied, spend one `@coderabbitai review` (this is what the batch-and-re-request-once quota budget is FOR): it re-verifies and self-resolves what's genuinely addressed. Threads it leaves open: resolve individually with the rationale stated in-thread. **Bare `@coderabbitai resolve` blanket-resolves with zero validation, so agents do not use it for fixed threads**; it's reserved for rounds that are entirely declines/deferrals with dispositions already stated (nothing to verify). Its verify-on-reply behavior is flaky and its auto-verification is suppressed by `auto_pause_after_reviewed_commits: 1`. The explicit re-request is the reliable path.
  Never self-resolve a thread you are claiming to have **fixed** (`claude-review-lane` §7 for why that separation is enforced in the fixer lane's tool list).
- **`claude[bot]` threads** resolve by a different protocol from CodeRabbit's, since that reviewer never self-resolves. See `claude-review-lane` §7.
- **Deferring or declining a CodeRabbit finding** is the one case where you resolve it yourself, because that reviewer only self-resolves when it agrees a fix landed, so a deferred thread stays open forever and `required_review_thread_resolution` blocks the merge permanently. Three rules for it:
  1. **State the disposition in the reply**: accepted-and-deferred (with where it will land) or rejected (with why). "Noted" is not a disposition.
  2. **Wait for the reviewer's counter-reply before resolving. 60s is enough.** It frequently pushes back, confirms your reasoning, or *offers to open a follow-up issue*, and resolving first orphans that offer. Measured: replies posted at `08:15:39–44` drew responses at `08:15:53–08:16:09`, and a resolve fired in the same step as the reply beat all of them.
  3. **Point at the tracking issue by number.** A deferred finding with no ticket is a dropped finding; if you are declining the reviewer's follow-up-issue offer, say which issue already covers it.
- **Never post a reply and resolve in one step.** Post, wait, read the response, then resolve. A script that does both in one breath will silently swallow every counter-reply.
- **Reply-in events** are CodeRabbit's verdicts on your fixes. Read them; it may push back or resolve.
- **`CLAUDE LIVENESS —` and the fork-notice comment:** read the verdict through `claude-review-lane` §2 before doing anything else. Only one of its four verdicts means a review landed. The rest, and the fork notice, mean **no review is coming on this head**, so a watcher that keeps waiting on the next push waits forever. Act on the verdict the moment the line appears, or hand the PR back if summoning is not yours to do.
- **CI FAIL:** diagnose from the failed job log, fix, push. Verify locally with explicit exit codes (`cmd >/dev/null; echo $?`). Never let a `| tail` mask a red gate.
- **`CODERABBIT RATE-LIMITED`:** no review ran. The diff is **unreviewed**, not clean. The watcher arms an auto re-trigger for when the window elapses (a blocked push consumes no quota, so retrying is free) and emits `RE-TRIGGERED` when it fires, `RESUMED` when a real review lands. **Do not sit idle waiting.** The rate-limit check *passes* by design, so merge is never actually blocked. Decide by risk: low-risk diff, merge on CI + the auto re-trigger; otherwise run the Opus 5 pass now rather than spending 45 minutes waiting for a tier that would have found less. On `auto-retry budget spent`, the model pass *is* the review.

## Phase 3: merge (once the user says merge, or under an explicit standing grant)

Check the registry first: `kit-meta.sh get <owner/repo> merge_queue`.

**Queue-enabled repos (prismalens, sreforge):** `gh pr merge <n> --squash` *enqueues*; the queue tests a speculative merge onto main and lands it. There is no BEHIND cascade, no update-branch babysitting, no `merge-cascade.sh`. That script and its doctrine describe pre-queue mechanics and must not be used on a queue repo. The one timing rule that survives: **do not enqueue before the liveness comment shows posted review output.** The queue gates on checks and threads, not on whether a reviewer has spoken, and enqueueing into silence merges an unreviewed head. `claude-review-lane` §8 says which verdicts count as posted output; three of the four do not.

**Classic repos (mage-memory, a personal account with no queue support):** merge by hand, one at a time, once the round's threads are resolved: `gh pr merge <n> --squash`. BEHIND still applies there; update-branch and re-green before merging the next.

Afterward: a tree from `EnterWorktree` or `isolation: "worktree"` removes itself on exit and needs nothing. One created by hand for an external lane does not, so remove it with `git worktree remove <path>` and delete its local branch.

## Notes

- **Auto-merge (and the queue) still outruns every reviewer.** The thread gate only blocks if a thread *exists*, and a reviewer that hasn't posted yet has no threads. A review that has already posted is no protection either: mage-memory#133 merged 14s after one landed, orphaning the fix commit for that review's own findings. Order the round as review-posted → fix → resolve → merge, and never the reverse; on queue repos "review-posted" is read off the liveness comment (`unattended-run` §7).

- Watching is cheap (shell poll, 75s; zero tokens while quiet), so prefer over-watching to user-relaying.
- **Rate limits are invisible on both obvious channels**: CodeRabbit posts the notice as an **issue** comment (not a review comment, so `/pulls/N/comments` polling misses it), and the `Review rate limited` check **passes** by design (so a red-check filter misses it too). `watch-coderabbit.sh` polls `/issues/N/comments` for the `rate limited by coderabbit.ai` marker, deduped on `updated_at` since CodeRabbit edits one summary comment in place rather than posting new ones.
- State dir `~/ai-context/state/cr-watch/` is durable across sessions; safe to re-arm anytime.
- **A watcher dies with the task that armed it, not with the session.** Disarm (TaskStop) the moment its PR is merged, closed, or handed to another lane. One left running past its lane kept acting on a PR that had since been repurposed, and autonomously spent a scarce CodeRabbit review on it. The plugin's SessionEnd hook also kills watchers and SessionStart reaps orphans from crashed sessions; re-arming after either is free.
- The plugin's PostToolUse hook (`hooks/pr-created.sh`) injects a reminder line whenever a `gh pr create` succeeds. Respond to it by running Phase 1 for that PR. Nothing local gates the merge (Phase 0); the hook posts nothing else.
- Phase 3's cascade is a background Bash with a single completion, not a Monitor. See the `anti-stall` skill for why waits key on evidence, never on liveness.

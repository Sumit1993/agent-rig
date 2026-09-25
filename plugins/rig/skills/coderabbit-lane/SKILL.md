---
name: coderabbit-lane
description: "CodeRabbit review lane mechanics: the hourly CodeRabbit routine that admits PRs to review, the per-developer hourly slot shared across repos, when a hand summon is worth it, trigger syntax, in-thread replies with cr-reply.sh, thread resolution. Load when requesting or answering CodeRabbit."
metadata:
  version: "4.0.0"
---

# The CodeRabbit review lane

`coderabbitai[bot]` is the independent automated reviewer. `AGENTS.md` decides reviewer routing. `pr-babysit` covers watching a PR this session raised, watcher lifecycles and merge mechanics. `claude-review-lane` covers `claude[bot]`. `autofix` applies PR-thread feedback with per-change approval. Process truth is `rig/docs/pr-review-process.html`.

## 1. Admission

The hourly CodeRabbit routine (`scripts/coderabbit-routine/` in Sumit1993/rig, `Sumit1993/rig#150`) is the admission mechanism, in every repo. `auto_review` is off everywhere, so opening a PR or marking it ready spends nothing by itself. Each hour the routine summons CodeRabbit on at most one PR: first a re-review, a PR whose head moved past its last review and whose CodeRabbit threads all carry a reply, then new PRs oldest first. A head commit must be 20 minutes old; a draft is never summoned.

The routine never merges. Merging is a local session's job when the operator asks for it (`compass` Step 0, `pr-babysit` Phase 3). Each run's report, in the routine's run history at claude.ai/code/routines, lists what was summoned and what waits. Its summons carry a hidden `<!-- summoned-by: coderabbit-routine -->` line, so a summon without it came from a session or by hand. Its off switch is pausing the routine.

## 2. When to summon by hand

Rarely. A hand summon spends the same slot the routine schedules and makes its budget check wait. Two cases justify one: the operator wants a PR reviewed ahead of the routine, or a held round (`pr-babysit`) needs the review inside this session. Post it bare (§4). The routine sees it as pending and does not repeat it.

`.coderabbit.yaml` path instructions still shape review quality and the Claude lane cannot see them, so they stay worth writing.

## 3. The per-developer counter

The lane runs on the Free/OSS plan, seat assignment disabled:

| Plan | PR/hr | Files per review |
|---|---|---|
| Free | 1 | 150 |
| OSS (our public repos) | 1 to 10, typically 1 or 2 | 100 to 300 |
| Team | 8 | 300 |

Essentials was formerly called Pro, and Team was formerly called Pro+.

- **With `auto_review` off, nothing fires on its own.** Before #150 a repo carrying `auto_review: true` was reviewed 8 to 93 seconds after `gh pr create` whatever its star count (`prismalens/gh-workflows` `#158`, `#155`, `#142`). A repo with no `.coderabbit.yaml` gets CodeRabbit's default, which is on; every repo in the routine carries one with `enabled: false`.
- **A draft is never reviewed.** The routine skips drafts, and CodeRabbit posts `Draft PR not reviewed` on a draft summon (`prismalens/gh-workflows#161`). Open the draft first, push as often as the work wants, and mark ready once at the end.
- **Do not read the plan off the bot.** CodeRabbit's run configuration reports a feature tier, and it printed "Plan: Team" on a repo that is rate-limited as Free, because open-source projects receive Team features without a subscription. The name the bot prints is not the row of the rate-limit table that applies.
- The counter is per developer, not per repo, branch, session or subagent. Every repo in the routine draws one pool. Run at most one review at a time across every repo you touch; parallel runs serialise and delay every lane.
- Every run spends a slot: initial reviews, incremental reviews, manual `@coderabbitai review`. The CLI's `coderabbit review --agent` posts to the PR regardless of labels (marker `coderabbit-cli-agent-hint`, recorded on `#123`). Repos set `auto_pause_after_reviewed_commits: 1` in `.coderabbit.yaml`: one review per PR, then batch fixes before the routine re-requests.
- Auto-pause is recoverable. A push past the limit pauses the lane on that PR and nothing arrives on its own. A bare `@coderabbitai resume` restarts it, and what follows is a real review of the final head that posts `Review completed`, so a PR paused by its own fix commits can still meet a merge condition requiring one. Resume deliberately; it spends a slot.
- Batch fixes before requesting. Never spend a slot on a commit you are about to amend.
- Remaining capacity is not readable. `@coderabbitai rate limit` returns documentation links.
- The notice's stated wait is accurate. Obey it, because it is the same one-review-per-developer-per-hour Free limit measured directly, not a guess. It is the per-developer window anchored to the last accepted review, measured exact to within fifteen seconds. A flat 60 minutes from the refusal has the wrong anchor and lands about 21 minutes late. `watch-coderabbit.sh` arms on the parsed figure and falls back to `CR_WATCH_COOLDOWN_SECONDS` (default 3600, a coincidental match to the hourly limit since this is the unparseable-notice fallback, not the limit itself) only when nothing parses; the event line names which it used. CodeRabbit has used at least three wordings, and the pattern once matched only the first:
  - `Next review available in: **47 minutes**`
  - `**Next included review available in 30 minutes.**`
  - `Your next included review will be available in 23 minutes.`
- The documented limit is one review per developer per hour on Free, rolling. The observed interval between an accepted review and the next runs about 55 to 57 minutes.
- `review full` is not a way past the limit. Both forms draw the same budget. A success shortly after a refusal is the window rolling over. `review full` is for the different refusal, "does not re-review already reviewed commits"; the clock is for the limit.
- CodeRabbit edits its reply in place, so a first read can show the opposite of the settled outcome. Read `updated_at`, wait for it to stop changing, classify on the settled body, and re-read before acting, not only before classifying.

## 4. Triggers and polling

- Two triggers, both bare. `@coderabbitai review` is incremental and the default. `@coderabbit review full` re-reads the whole diff and is the fallback when the incremental form is refused as "an incremental review system" that "does not re-review already reviewed commits"; a push that only moves documentation can be declined off cooldown.
- Post exactly the trigger and nothing else. Extra questions or bullets are parsed as chat, return "For best results, initiate chat on the files or code changes", and run no review. Context goes in the PR description, which the review reads.
- Poll after every trigger. A trigger posting is not a review starting. Wait about 60 seconds, inspect the latest `coderabbitai[bot]` comment, then report. `rate limited`: rejected, nothing ran, wait out the window. `initiate chat on the files`: misparsed, re-trigger bare. Anything else: accepted.
- CodeRabbit is not diff-only. It runs `rg`, `fd`, `sed`, `git show` and inline Python against the checkout to reason across files. It does not run test suites.

## 5. In-thread replies

Replies go in-thread, to satisfy `required_review_thread_resolution`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/cr-reply.sh" <pr> <root_id> "@coderabbitai Fixed in <sha>: <what changed>. Please verify."
```

- Never write the word "resolve" in a reply. CodeRabbit parses it as a command and returns boilerplate ("Post `@coderabbitai resolve` as a new top-level PR comment"), resolving nothing.
- Reply-in events are CodeRabbit's verdicts on your fixes. Read them.

## 6. Thread resolution

- Fixed threads resolve through one verified re-review, never a blanket command. After every fix for the round is committed, pushed and replied to in-thread, stop: the routine re-reviews a PR whose CodeRabbit threads all carry a reply. Summon it yourself only in the §2 cases. CodeRabbit resolves the threads it considers addressed; anything left open is reviewed and resolved individually with rationale in-thread.
- Bare top-level `@coderabbitai resolve` blanket-resolves every thread with zero validation. The operator's call only, for rounds made entirely of declined or deferred findings whose dispositions are already recorded.
- A PR merges only with every review thread resolved by the reviewer that opened it. The session never resolves a CodeRabbit thread to clear a merge.
- Declining or deferring: CodeRabbit self-resolves only when code changed, so a declined or deferred finding goes to the operator, who resolves it under three rules. State the disposition (accepted-and-deferred with landing target, or rejected with reasons; "noted" is not a disposition). Wait about 60 seconds for the counter-reply so follow-up issue offers are not dropped. Reference tracking issues by number.
- Never reply and resolve in one step.

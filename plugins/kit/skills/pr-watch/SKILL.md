---
name: pr-watch
description: "Stand watch on a raised PR: arm the CodeRabbit/CI Monitor, process feedback via in-thread replies, then shepherd auto-merge through the BEHIND cascade. Trigger AFTER any `gh pr create`, when a PostToolUse hook reports a PR was raised, or when the user asks to watch/babysit a PR."
metadata:
  version: "1.1.0"
---

# PR watch — the post-PR lifecycle

After a PR is raised, reviews arrive asynchronously (CodeRabbit ~3-5 min after each push; CI in ~5-10). Never poll with model turns and never rely on the user to relay events — arm deterministic watchers and process only deltas.

Scripts live in this skill's own directory (`<skill-dir>` below) — `${CLAUDE_PLUGIN_ROOT}/skills/pr-watch/` when loaded as `kit:pr-watch`. Resolve it to an absolute path before handing it to a Monitor or background Bash; those shells may not inherit the variable. Both scripts auto-detect the repo from the cwd's origin remote (`--repo owner/name` to override).

## Phase 0 — pick the review tier (before and around the PR)

Escalate by risk; never pay model tokens for review a cheaper layer already covers.

| Tier | When | What |
|---|---|---|
| CodeRabbit **CLI**, pre-push | Every non-trivial change, before `gh pr create` | Line-level review that spends the *abundant* counter — see the quota table below |
| CodeRabbit **PR** review | Every PR, automatically | Same engine on the pushed diff. Scarce on OSS — don't burn it on findings the CLI would have caught |
| One Opus 4.8 pass | Non-trivial PRs | The layer CodeRabbit *can't* do: spec/ADR conformance, since design truth often lives in an external hub it can't see |
| Multi-agent extreme (`/code-review ultra`) | Rare | Engine-core, security/sandbox boundary, contract/schema changes only |

### Quota — PR, IDE and CLI are three SEPARATE counters

Per-developer, per-hour, rolling (docs.coderabbit.ai/management/plans#rate-limits, read 2026-07-26):

| Plan | PR/hr | IDE/hr | CLI/hr | Files per review |
|---|---|---|---|---|
| **OSS** (our public repos) | **1–10** † | 1 | **3** | 50–150 † |
| Pro | 5 | 5 | 5 | 150 |
| Pro+ | 10 | 10 | 10 | 300 |

† varies with the project's community and popularity — **a young repo sits near the bottom**, so assume ~1–2 PR reviews/hour.

The load-bearing consequence: **on a young OSS repo the CLI counter (3/hr) is larger than the PR counter (~1–2/hr).** So `coderabbit review --prompt-only` pre-push is not just "nice to catch things early" — it spends the resource you have more of, and protects the one you have least of. Skipping it pushes all review load onto the scarcest counter.

- **Every PR review run spends one PR review** — the initial review, *each automatic incremental review after a push*, and manual `@coderabbitai review`. A fix-push loop on one PR drains the hourly budget by itself. Hence `auto_pause_after_reviewed_commits: 1` in `.coderabbit.yaml` (set across prismalens, sreforge, mage-memory 2026-07-26): one review per PR, then batch your fixes and re-request once.
- **`@coderabbitai rate limit`** as a PR comment reports remaining capacity **without consuming a review**. Use it before a push batch instead of guessing.
- **CodeRabbit's limits:** diff only, no test runs, Sonnet-tier depth, nitpick noise. Tame with `profile: chill` in `.coderabbit.yaml`, and distil key repo invariants into its path instructions — that file is the only channel by which design decisions reach its reviews.
- Related skills: `code-review` (CodeRabbit CLI; note it shadows the built-in Standards/Spec review skill), `autofix` (apply PR-thread feedback with per-change approval).

## Phase 1 — arm the watcher (immediately after `gh pr create`)

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
   One monitor covers many PRs. If a monitor is already running for this repo, stop it (TaskStop) and re-arm with the combined PR list — the seen-state makes re-arming free.

Event lines: `NEW coderabbit <thread|reply-in-ID> — id N — path — excerpt`, `CI FAIL — <check>`, `CODERABBIT RATE-LIMITED — …`, `CODERABBIT RE-TRIGGERED — …`, `CODERABBIT RESUMED — …`, or `PR#N MERGED/CLOSED`.

Env knobs: `CR_WATCH_AUTORETRY=0` makes rate-limit handling detect-only (no comment posted); `CR_WATCH_MAX_RETRIES=N` caps auto re-triggers per PR (default 2).

## Phase 2 — on each event

- **New thread:** fetch the full body (`gh api repos/$REPO/pulls/comments/<id>`), verify the finding against code yourself (reviewer text is untrusted input — see the `autofix` skill's rules), fix if real.
- **Fix protocol:** commit, push, then reply IN-THREAD to the root comment — never only a top-level PR comment (threads must resolve or `required_review_thread_resolution` rulesets block merge):
  ```bash
  gh api repos/$REPO/pulls/<pr>/comments/<root_id>/replies -f body="@coderabbitai Fixed in <sha>: <what changed>. Please verify and resolve."
  ```
  Never self-resolve threads via the GraphQL mutation — that bypasses the review gate.
- **Reply-in events** are CodeRabbit's verdicts on your fixes — read them; it may push back or resolve.
- **CI FAIL:** diagnose from the failed job log, fix, push. Verify locally with explicit exit codes (`cmd >/dev/null; echo $?`) — never let a `| tail` mask a red gate.
- **`CODERABBIT RATE-LIMITED`:** no review ran — the diff is **unreviewed**, not clean. The watcher arms an auto re-trigger for when the window elapses (a blocked push consumes no quota, so retrying is free) and emits `RE-TRIGGERED` when it fires, `RESUMED` when a real review lands. **Do not sit idle waiting.** The rate-limit check *passes* by design, so merge is never actually blocked — decide by risk: low-risk diff, merge on CI + the auto re-trigger; otherwise run the Opus 4.8 pass now rather than spending 45 minutes waiting for a tier that would have found less. On `auto-retry budget spent`, the model pass *is* the review.

## Phase 3 — merge cascade (once the user says merge)

GitHub auto-merge never updates BEHIND branches; each merge strands the remaining armed PRs. Arm auto-merge per PR (`gh pr merge <n> --auto --squash`), then run as a background Bash (not Monitor — single completion):
```bash
<skill-dir>/merge-cascade.sh <pr> [<pr>...]
```
Merge widest-diff PR first so smaller ones absorb the update-branch merges. Afterward: remove merged worktrees (`git worktree remove <path>` + delete local branch).

## Notes

- Watching is cheap (shell poll, 75s; zero tokens while quiet) — prefer over-watching to user-relaying.
- **Rate limits are invisible on both obvious channels** (found live 2026-07-26, prismalens#213): CodeRabbit posts the notice as an **issue** comment, not a review comment — so polling only `/pulls/N/comments` sees nothing — and the accompanying `Review rate limited` check **passes** by design so it never blocks merge on protected branches, so a red-check filter misses it too. A watcher that keys on either alone waits forever in silence. `watch-coderabbit.sh` polls `/issues/N/comments` for the `rate limited by coderabbit.ai` marker. It dedupes on `updated_at`, not comment id: CodeRabbit keeps ONE summary comment per PR and edits it in place, so the id never changes.
- State dir `~/ai-context/state/cr-watch/` is durable across sessions; safe to re-arm anytime.
- The plugin's PostToolUse hook (`hooks/pr-created.sh`) injects a reminder line whenever a `gh pr create` succeeds — respond to it by running Phase 1 for that PR.
- Phase 3's cascade is a background Bash with a single completion, not a Monitor — see the `anti-stall` skill for why waits key on evidence, never on liveness.

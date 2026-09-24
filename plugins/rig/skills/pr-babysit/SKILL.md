---
name: pr-babysit
description: "What happens to a PR after it is raised: by default nothing in this session, because the hourly review queue reviews and merges it async. When the operator asks to hold a round here: seed seen-state, arm the reviewer and CI Monitor, route each event, then merge. Load after any gh pr create or when asked to watch or merge a PR."
metadata:
  version: "5.0.0"
---

# PR watch: the session-scoped review round

The default is async (`Sumit1993/rig#150`). Keep the PR a draft while work continues, mark it ready once at the end, and leave it. The hourly review queue (`review-queue.yml` in prismalens/gh-workflows) summons CodeRabbit on it, merges it when the review comes back clean, and findings come back as review debt at the next session start in that repo (`compass` Step 0). Phases 1 and 2 run only when the operator asks to hold a round in this session; Phase 3 also runs when the operator asks to merge.

A held round is one PR, whichever session raised it, watched until its round ends, so the session reacts to findings without the user relaying them. Not a lifecycle manager: the merge queue removed cascade shepherding, and a PR left over from an earlier session needs no local watcher because GitHub notifications cover verify-then-resolve and enqueue.

Reviewer behaviour lives elsewhere. `claude-review-lane` owns `claude[bot]`, `coderabbit-lane` owns `coderabbitai[bot]`, and both load on a PR of any age. Load the owning skill before acting on that reviewer. The trigger syntax and `cr-reply.sh` appear below so a router recognises them; the preconditions (cooldown arithmetic, budget, the post-trigger poll) live only there, and acting on the fragments produces confidently wrong reports.

Process truth is `rig/docs/pr-review-process.html`. Whoever changes the process updates that page in the same session.

Reviews arrive on their own schedule: the Claude lane in 2 to 5 minutes, CodeRabbit within the hour the queue summons it (median 3.5 hours after a burst of PRs), CI in 5 to 10. Never poll with model turns. Never wait for the user to relay an event. Arm a deterministic watcher and process deltas.

Scripts sit in `${CLAUDE_PLUGIN_ROOT}/skills/pr-babysit/` when loaded as `rig:pr-babysit`; shared ones (`cr-reply.sh`, `rig-meta.sh`) in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Resolve both to absolute paths before handing them to a Monitor or a background Bash, which may not inherit the variable. Watch scripts read the repo off the cwd's origin remote; `--repo owner/name` overrides.

Per-repo facts come from the registry, never from memory. `rig-meta.sh current` reads `data/repo-meta.json` folded with runtime observations:

Current repo metadata: !`"${CLAUDE_PLUGIN_ROOT}/scripts/rig-meta.sh" current`

## Phase 0: the merge contract

Whether anything is enforced is a per-repo fact. `rig-meta.sh get <owner/repo> enforced` answers without a network call. `false` means we checked and nothing is enforced, so holding the PR for the operator is the only gate. "No such key" means we never looked. Read enforcement off `rulesets`; a 404 from `branches/<b>/protection` proves nothing, because a repo on rulesets returns 404 there either way.

Where a repo enforces, the contract is three facts:

- Two required checks, `CI gate` and `Validate PR title (conventional commits)`. Nothing else. No review check, evidence artifact, marker job, SHA pinning, carry-forward or committed high-risk path list. `cr-preview.sh` and `cr-evidence.sh` do not exist.
- `required_review_thread_resolution: true`. One unresolved thread blocks the merge. The merge condition is stricter than the ruleset: every review thread resolved by the reviewer that opened it. GitHub cannot tell who resolved a thread, so check it: a thread this session resolved does not count. This is the only thing that enforces a finding, which is what makes Phase 2's in-thread protocol load-bearing.
- Reviewers are advisory. No check waits on them, so no check proves a review happened. What counts as evidence is in `claude-review-lane`.

Push freely; nothing runs pre-push. Escalate by risk, and never pay model tokens for review a cheaper layer already covers:

| Tier | When | What |
|---|---|---|
| Claude review (`claude[bot]`) | Where `rig-meta.sh get <repo> claude_lane` says the lane runs: every same-repo PR, automatic, but not every round and not every author | The default. Inline findings. Advisory, but every thread it opens blocks. See `claude-review-lane` |
| CodeRabbit (`coderabbitai[bot]`) | Every ready PR, summoned by the hourly review queue; `auto_review` is off everywhere | The independent lane, drawing a scarce per-developer counter. See `coderabbit-lane` |
| One Opus 5 pass | Non-trivial PRs | Spec and ADR conformance, which the bots cannot see |
| `/code-review ultra` | Rare | Engine core, security boundary, contract or schema changes |

A PR body that closes several issues repeats the keyword per issue, `closes #a, closes #b`; GitHub links only the first number after one keyword. `pr-created.sh` reads `closingIssuesReferences` and says when the body names more than GitHub linked (gh-workflows #140 claimed seven, linked one).

Never bypass the ruleset. Batch every fix before you push: the queue summons a PR once its head commit is 20 minutes old, so a push right after a fix batch lands spends a slot on a commit you are about to amend.

## Phase 1: arm the watcher, only for a held round

The trigger is the operator asking to hold this PR's round in this session. A PR merely existing is not one; the queue has it.

Seed the seen-state first, both files, so existing comments never replay as `NEW`:

```bash
mkdir -p ~/ai-context/state/cr-watch
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner); KEY=${REPO//\//-}
C=$(mktemp); trap 'rm -f "$C"' EXIT
gh api "repos/$REPO/pulls/<pr>/comments?per_page=100" > "$C"
jq -r '.[] | select(.user.login|test("coderabbit")) | .id' "$C" \
  > ~/ai-context/state/cr-watch/$KEY-pr<pr>.seen
jq -r '.[] | select(.user.login|test("claude";"i")) | .id' "$C" \
  > ~/ai-context/state/cr-watch/$KEY-pr<pr>-claude.seen
```

Then arm the Monitor tool with `persistent: true`:

```
command: <skill-dir>/watch-coderabbit.sh <pr> [<pr>...]
description: CodeRabbit comments + CI reds on PR <pr>
```

One monitor covers many PRs. If one is already running for this repo, TaskStop it and re-arm with the combined list; seen-state makes that free.

Event lines and what each one asks for are in `references/events.md` beside this file; read it when the first line arrives, not before.

The first line is the presence verdict, `CODERABBIT ACTIVE on <repo> — watching reviews, rate limits, CI and merge state` or `CODERABBIT ABSENT on <repo> — watching CI + merge state ONLY`. `rig-meta.sh get <owner/repo> coderabbit` is the source of truth; the watcher checks it, then probes for a committed `.coderabbit.yaml` or `.yml`, then for a `coderabbit*` author in recent comments, and writes a positive probe back to the registry. ABSENT skips the CodeRabbit polls and means unreviewed, exactly like a rate limit: a repo with no reviewer produces a quiet watch that is byte-identical to "reviewed, found nothing". Decide by risk: trivial or knowledge-base-only merges on CI alone, anything else wants the Opus 5 pass, and no local CLI step substitutes.

Env knobs: `CR_WATCH_AUTORETRY=0` makes rate-limit handling detect-only, posting no comment. `CR_WATCH_MAX_RETRIES=N` caps auto re-triggers per PR, default 2. `CR_WATCH_ASSUME_CODERABBIT=1|0` skips the probe.

## Phase 2: on each event

The session that owns the Monitor is a thin router. Read the sentinel line, then SendMessage the payload path to the seat that last touched the diff, usually the reviewer agent, resumed. Never fresh-spawn a fixer when a seat already holds the diff. Never paste a comment body into the routing session. Triage per finding: line-level goes to an agy delta prompt, judgement to the resumed Claude seat.

Per-event handling is in `references/events.md`.

## Phase 3: merge, once the user says so or under an explicit standing grant

The review queue merges a PR whose review came back clean on its own; that is the one standing grant. Everything else waits for `MERGE_OK`.

Check `rig-meta.sh get <owner/repo> merge_queue` first.

- Queue repos (`merge_queue` true): `gh pr merge <n> --squash` enqueues, and the queue tests a speculative merge onto main before landing it. No BEHIND cascade, no update-branch babysitting. Do not enqueue before the liveness comment shows posted review output (`claude-review-lane` §2). The queue gates on checks and threads, not on whether a reviewer spoke, so enqueueing into silence merges an unreviewed head.
- Classic repos (`merge_queue` false): merge by hand once CI is green and every review thread resolved by the reviewer that opened it, `gh pr merge <n> --squash`. BEHIND still applies, so update the branch and re-green before merging the next.

Afterward remove the lane's worktree and delete its local branch (`AGENTS.md` §Worktrees). `git worktree unlock` first if git refuses because the tree is locked.

## Notes

- Auto-merge and the queue both outrun every reviewer. The thread gate only blocks once a thread exists, and auto-merge can fire between a review landing and its fix commit. Order the round as review posted, then fix, then resolve, then merge, never the reverse. On queue repos "review posted" is read off the liveness comment.
- Never wait on `mergeStateStatus`. An unresolved thread pins it at `BLOCKED`. Key on `reviewThreads` and comment IDs (`no-doze` §3).
- Watching is cheap: a shell poll every 75 seconds, zero tokens while quiet. Prefer over-watching to relaying.
- Rate limits are invisible on both obvious channels. CodeRabbit posts the notice as an issue comment, so `/pulls/N/comments` misses it, and the `Review rate limited` check passes by design. `watch-coderabbit.sh` polls `/issues/N/comments` for the `rate limited by coderabbit.ai` marker, deduped on `updated_at` because CodeRabbit edits one summary comment in place.
- `~/ai-context/state/cr-watch/` is durable across sessions. Re-arming is always safe.
- A `git checkout` under a running watcher kills it. Bash reads a script incrementally, so switching branches rewrites `watch-coderabbit.sh` beneath the running shell, usually exit 144, with no event. Re-arm after any branch change, or run the watcher from a path that is not moving.
- A watcher dies with its task, not the session. TaskStop it the moment its PR is merged, closed or handed off. The SessionEnd hook also kills watchers and SessionStart reaps orphans; re-arming after either is free.
- `hooks/pr-created.sh` injects a reminder whenever a PR URL appears in a Bash or Agent tool result, seeds the seen-state, and says when the new PR touches files an open draft already changes. It reminds the session that reviews run async; run Phase 1 only for a held round. It also runs on `Agent`, because an agy lane's PR URL arrives in the handler's report, not a Bash result.
- Phase 3's cascade is a background Bash with a single completion, not a Monitor.

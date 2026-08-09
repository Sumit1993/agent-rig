---
name: nightly-run
description: "Rules for holding an unattended multi-hour run — organizer discipline, lane count from the scarce resource, stall detection, evidence-not-green, verify-every-claim, park-don't-decide. Load BEFORE starting any session where the operator is away for hours, at the first wake-up of a cron-driven organizer, and whenever a dispatched lane reports \"standing by\"."
metadata:
  version: "1.0.0"
---

# Nightly run — holding an unattended session

One seat holds the goal across many wake-ups; every other seat is disposable. Everything below is a failure that has already cost hours of an unattended window, stated as the mechanism rather than the prohibition — prose alone demonstrably does not prevent the stall (§4).

Companion skills, assumed and not repeated: **`anti-stall`** (how a wait is built), **`agy-delegate`** (how a cheap executor is driven), **`pr-watch`** (per-PR lifecycle).

## 0. The plan file is the session's memory

One file, `~/ai-context/<repo>-<task>-plan.md`, is the source of truth. It survives compaction, cron wake-ups, and the operator's return; chat scrollback survives none of those. It carries: standing rules, a lane table with live state, decisions waiting on the operator, verified environment facts, and a running log. Detail goes there, not into the terminal (§11).

At hand-off, before the operator leaves, record: what is scarce, which repos and worktrees exist, what is frozen, and what must never be merged.

**If the file does not exist yet, building it is the whole first tick and nothing is dispatched until it does:** enumerate the queue read-only, group it into waves by what blocks what, name the scarce resource (§2), and probe the environment rather than assuming it (which stacks are up, which worktrees exist, which repo owns which name). Then write the standing rules down, including the ones the operator gave verbally.

**Respect the window.** Never start a lane that cannot both finish *and* be verified inside the time remaining; as the boundary approaches, only take work to a state that is safe to leave — pushed, commented, parked — never mid-merge or mid-rebase.

## 1. The organizer never edits repo files

Dispatch and judge. Editing a file means the seat that holds the whole goal spent its turn on work a cheap lane could have done — and stopped tracking every other lane while it did. The organizer's only outputs are dispatches, verdicts on returned claims, plan-file updates, and merges.

Lanes work in worktrees (`~/worktrees/<repo>/<branch-slug>`), never in the main checkout — the main checkout and the stack it serves are the organizer's, and a lane that "restores" its branch takes the whole run down with it. The organizer creates or reuses the worktree; the lane is handed an absolute path and told to stop and report if it is missing.

**Every dispatch prompt carries, explicitly:** the absolute worktree path · the exact verify commands and the expectation that the lane runs them itself · the report format (findings, evidence, SHAs, blockers — no prose) · the stop conditions ("abort and report rather than improvise" on any conflict, any frozen path, any gate still red after N minutes) · what the lane may **not** do (merge, close, bypass, edit a frozen path) · the stall rule (§4).

## 2. Lane count is a function of the scarce resource, not a constant

There is no correct number of lanes. Each run names its own limit from whatever is actually scarce and writes it in the plan file. Two kinds recur:

- **A shared external counter.** One org-wide review counter with a cooldown means one review in flight across the whole org; parallel lanes do not parallelise it, they serialise behind it and slow every lane.
- **A serialising invariant.** Merges to one branch re-BEHIND every other PR (§7), so merging is one-at-a-time regardless of how many lanes exist.

Everything not contending on a named scarce resource may run wide.

**Workflows and subagents may be used freely. Cost is the only constraint.** Do not ration agents to save money, and do not do work by hand to avoid spawning one — that trades the expensive seat's attention for the cheap resource. Ration only against a named scarcity.

## 3. Delegate-then-verify

Route bulk reading, log triage, rebases, evidence collection and repetitive per-PR procedure to the cheap executor. **Never let its claims reach an artifact unverified.** A drafting pass on PR bodies fabricated a UI button label and attributed a screenshot to the wrong route; both were plausible, neither was detectable from the draft, and both were caught only by cross-checking component source at the head SHA. Cheap models gather and draft; the verification pass belongs to the organizer or a Claude handler, always against source at the exact SHA.

Judgment-heavy work — security/crypto, design surface, product semantics — skips the cheap lane entirely.

## 4. The stall rule — a wait must hold the turn

**An agent that returns saying "standing by", "waiting for", or "will be notified" has stalled. It is not waiting.**

The mechanism: a completion notification fires only when an agent has **no live background children**. So the moment an agent launches something in the background and returns control, the notification it is counting on can never arrive — by returning, it guaranteed nothing is watching. This shape recurs across independent lanes inside a single window, in skills that already document it in prose, which makes it a designed-in hazard rather than an agent-quality problem.

- A wait is valid **only while the agent is still executing inside its own turn** — a foreground `until` loop keyed on durable evidence, loop length as the deadline (`anti-stall` §2).
- A background launch followed by a return of control is a stall, always.

**Resume action, immediately, without acknowledging the report:** `SendMessage` to that agent — "go read <the concrete artifact: log path, PR check, SHA> now; then wait in the foreground with a deadline; do not return until the evidence resolves or the deadline expires." Never accept two consecutive "waiting" reports; read the artifact yourself instead.

Every dispatch prompt carries this rule. Assume the lane will otherwise walk into it.

## 5. A green job is never evidence — only a posted artifact is

A workflow can report success having posted nothing, and does.

- Check the **producing** job, not the wrapper check. A green review step means the lane ran; only the artifact it was supposed to post counts.
- A green gate whose description names a **retired producer** is a stale artifact, not a pass. It flips red the instant anything re-evaluates it, and a status-only read cannot see that coming.
- Independent triage lanes read exactly that stale green as real and called the PR "clean, ready to merge" — two of them, separately. Hence §8.

## 6. Rebase before push is a precondition, not hygiene

A branch that predates the reviewing workflow **cannot mint evidence at all**, so pushing it unrebased burns a full CI cycle and guarantees a red gate.

The mechanism, because it is not guessable — the review workflow runs from the **base** ref, so it fires on every PR, but the action no-ops when the PR head's own copy of that workflow differs from the default branch's, and it no-ops by **exiting success having posted nothing**:

```
stale branch (workflow file absent at head)
  → review job: runs from base, detects head drift, posts nothing, exits SUCCESS  ✅
  → marker job: "did the reviewer post an artifact at this SHA?" → no → refuses to mint  ❌
  → gate: red, with a green producing job sitting right above it
```

A branch cut before the workflow existed does not contain the file at all, which is maximal drift — so it can never earn evidence, no matter how many times it is pushed.

The order is always **rebase → push → let the lane mint evidence → verify the artifact**. Corollary: a green review check on its own means nothing; only the minted artifact counts (§5).

Batch every fix before requesting any review — evidence keys to the head SHA, so one spent on a commit about to be amended is spent for nothing.

## 7. One merge in flight; cascade by hand

Every merge re-BEHINDs every other open PR, and auto-merge never updates a BEHIND branch.

- Serial merges only, one at a time, verifying the gate after each.
- Cascade manually: after each merge, update the next branch, re-earn its evidence (§6), then merge.
- When PRs contend on one shared file (a lockfile, a generated artifact), land the smallest delta first; each landing forces a regenerate on the rest.
- With no scheduled sweeper, a PR that merely goes BEHIND fires **nothing** — its status sits stale indefinitely. Staleness is silent; go look.
- Rebase the PRs you are deliberately parking at the **end** of the drain. Rebasing them early only re-BEHINDs them behind every subsequent merge.

## 8. Verify every delegate claim against live state

A returned report is a hypothesis. Before it changes a decision, confirm it against the thing itself: the head SHA, the check's description string, the job log, the file at that SHA. A diff claimed as one line gets read. Two independent lanes agreeing raises no confidence — they can share one stale input, and did.

## 9. Never bypass a ruleset or a gate

When a gate blocks the only available fix, **escalate; do not override.** Waiting out a cooldown inside an eight-hour window is cheap; a bypass is unrecoverable.

The reasoning that makes this bite: the PR that *repairs* the gate is the **worst** candidate in the repo for skipping review. The repo's own committed high-risk path list — the one the gate reads to decide who needs an independent reviewer — records that every independent-reviewer catch on that track landed in exactly that territory — **including ones the adjudicating model had already ruled acceptable.** A gate change reviewed only by the model that wrote it is precisely the failure the list exists to prevent.

- A **conditional** pre-authorization ("this might need a bypass") is a reserve, not an instruction. Write down the exact condition that would spend it, and do not spend it for mere slowness.
- Never reach for a skip flag, an `--admin` merge, a `--no-verify` push, or a ruleset edit. If a lane already used one, record it and stop that lane; do not quietly bank the result.
- Dilemma → consult the planner seat: a fresh agent on the strongest planning model, given the decision, the constraints, and the options — not the whole run. If the last consult is more than an hour old, start a new one rather than resuming it; a stale consult reasons from premises the run has since disproved. Its ruling is binding for that decision, and its explicit deferrals stay deferred.

## 10. Park anything needing operator sign-off

- Work that changes what the operator sees or owns — UX shape, exported API, architecture naming, scope — goes **to green and stops**. Never merge it.
- Diverged, superseded or obsolete PRs get a **comment** stating the state, and stay open. Never close one. "Obsolete" is a judgement the operator makes, not you: a PR qualifies for the comment-and-leave treatment when its own body reclassifies it out of the current scope, when it carries an unresolved question only the operator can settle, or when its diff no longer applies to the current base for reasons other than a mechanical rebase. Age alone is not divergence.
- An honest gap beats a fabricated claim: where the evidence for a parked item is incomplete, say so in the artifact itself.
- Every parked item lands in the plan file's decisions list as a specific question with options — not "needs review".

## 11. Terse output — the operator reads a terminal

Findings, decisions, evidence, SHAs, blockers. No restating the plan, no narrating what is about to happen, no re-summarising work already logged. Every dispatched agent gets the same instruction. **A tick with no dispatch is a valid tick** — one line, with the reason.

## Wake-up checklist (each cron tick)

1. Read the plan file first — it, not memory, holds the state.
2. Confirm every lane is **alive** by enumerating agents; never assume. Any lane reporting "standing by" → §4 resume, before anything else.
3. Check real state, not reports: default-branch SHA, each PR's head SHA, each gate's description string.
4. Re-verify the scarce resource's availability (§2) before spending it.
5. Dispatch only work whose prerequisites are final — starting a lane that depends on an in-flight template means writing it twice.
6. Append findings and decisions to the plan file; one or two lines to the terminal.

Hand back on a hard blocker or the natural end of all work, not on a timer: land any end-of-session deliverable the operator asked for, then leave the plan file's decisions list as the first thing they read — each entry a question, its options, and what it blocks.

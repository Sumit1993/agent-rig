---
name: unattended-run
description: "Rules for holding a long unattended run: arm the wake-up first, keep the organizer out of the files, catch stalls, treat a green check as nothing, verify every delegate claim, park what needs a human. Load BEFORE any session where the operator is away and the work will outlast their attention: an overnight run, a multi-hour delegation, a cron-driven organizer's first wake-up. Also load whenever a lane reports \"standing by\"."
metadata:
  version: "3.1.0"
---

# Unattended run: holding a long autonomous session

One seat holds the goal across every wake-up. Every other seat is disposable. Each rule here came from a failure that cost hours of a real unattended window; the stories are in `docs/incidents.md`. Assumed and not repeated: `anti-stall` for how a wait is built, `agy-delegate` for the cheap executor, `pr-watch` for one PR's lifecycle.

## 0. The first tick: arm the wake-up, then write the plan file

### Arm the wake-up

Nothing is dispatched until both exist. With no scheduled wake-up the run is one turn long.

1. `CronCreate` is a deferred tool. Fetch it first: `ToolSearch("select:CronCreate,CronList,CronDelete")`. Nothing prompts you to, which is why this gets skipped.
2. 30 minutes, off the :00 and :30 marks where every scheduled job lands: `7,37 * * * *`. Longer when the thing you wait on moves slower.
3. The prompt fires into this session, so ask for current state: "tick: read the plan file, check lane and PR state, then dispatch or report."
4. `CronList` after, to confirm. A cron that failed to arm looks like a quiet run.
5. Record the job ID in the plan file beside the condition that ends it (§3).

Three facts shape the plan. Jobs live in this session's memory only; end the session and the cron goes with it, leaving a plan file that still reads healthy. Jobs fire only while the REPL is idle, so a foreground wait (`anti-stall` §2) stays shorter than one interval. Recurring jobs expire after 7 days. `ScheduleWakeup` paces `/loop` and is not this; use `CronCreate`.

### Write the plan file

`~/ai-context/<repo>-<task>-plan.md` is the source of truth. It holds standing rules, the lane table, decisions waiting on the operator, verified environment facts, and a running log. Detail goes here, not the terminal (§11). If it does not exist, building it is the rest of the first tick: read the queue without touching anything, group into waves by blockers, probe stacks and worktrees, and record standing rules and frozen paths.

Respect the window. Never start a lane that cannot finish and be verified in the time left. Near the end, take work only to a state that is safe to leave: pushed, commented or parked. Never mid-merge or mid-rebase.

## 1. The organizer never edits repo files

Dispatch and judge. Editing a file means the seat holding the goal spent its turn on work a cheap lane could have done, and stopped watching every other lane. The organizer produces dispatches, verdicts on returned claims, plan file updates, and merges. Nothing else.

Lanes work in worktrees, never the main checkout. `AGENTS.md` sets which mechanism; a Claude subagent lane and an agy lane do not get the same one. The main checkout and its stack belong to the organizer. A lane that "restores" its branch takes the run down. The organizer creates or reuses the worktree and hands the lane an absolute path, with instructions to stop and report if it is missing.

The organizer does not draft the spec either. `agy-delegate` §Dispatch sends that to a `fable-planner`: you supply the issue, the constraints and the worktree path, and you judge what comes back. Drafting is work, and this seat does not do work.

Every dispatch prompt says, in as many words:

- The absolute worktree path.
- The exact verify commands, and that the lane runs them itself.
- The report format: findings, evidence, SHAs, blockers, no prose.
- The stop conditions. "Abort and report rather than improvise" on any conflict, any frozen path, any gate still red after N minutes.
- What the lane may not do: merge, close, bypass, edit a frozen path.
- The stall rule (§3).

Never override a lane's brief with reasoning you invented on the spot. If you contradict a brief, cite what supersedes it. With no source, the brief wins, and a lane that refuses an unsourced order is behaving correctly (`unsourced-order-refused`).

Workflows, subagents and todos are free to use; cost is the only limit. Do not ration agents to save money and do not do work by hand to avoid spawning one. This grant is about model choice and does not exempt bounded mechanical work from the delegation rule in `AGENTS.md`, which still sends that work to agy.

## 2. Delegate, then verify

Send bulk reading, log triage, rebases, evidence gathering and repetitive work to the cheap executor (`invented-button-label`). Verification runs once per umbrella against the build, not once per unit. The seat does not re-run a gate the umbrella already proved; re-run only on a gap. Judgement skips the cheap lane: security, crypto, user-facing work, product semantics.

## 3. The stall rule: a wait has to hold the turn

A lane that returns saying "standing by", "waiting for" or "will be notified" has stalled. It is not waiting.

A completion notification fires only when an agent has no live background children. The moment an agent launches something in the background and hands control back, that notification can never arrive. This keeps happening in lanes that were handed the rule, so treat it as a trap built into the tooling.

- A wait is real only while the agent is still running inside its own turn: a foreground `until` loop keyed on durable evidence, loop length as the deadline (`anti-stall` §2).
- A background launch followed by handing control back is a stall, every time.

Fix it at once and skip the acknowledgement. `SendMessage` the lane: "go read <the concrete artifact: log path, PR check, SHA> now. Then wait in the foreground with a deadline. Do not return until the evidence resolves or the deadline expires." Never accept two "waiting" reports in a row; read the artifact yourself. Put this rule in every dispatch prompt.

Some evidence has no shell poll. If the only way to read it is an MCP tool call, a cron tick into this session is the watch and its latency is the tick interval. Record it as a tick, never a monitor (`anti-stall` §2).

The reverse failure is a watch that outlives its job. A monitor, a poller, a cron tick: anything armed to watch one piece of work is torn down the moment that work ends, whether merged, closed, moved or abandoned (`watcher-outlived-repurposed-pr`). Arming something durable creates a teardown obligation. Record it in the plan file's lane table beside the thing it watches, and disarm it when closing the lane.

## 4. A green job proves nothing. Only a posted artifact does

A workflow can report `success` having posted nothing, and does (`green-review-posted-nothing`).

- Read the job that produces the artifact, not the wrapper check. A green review step means the lane ran; only the thing it was supposed to post counts.
- A green gate whose description names a retired producer is a leftover, not a pass. It flips red the moment anything re-evaluates it, and a status-only read cannot see that coming.

## 5. Check every delegate claim against live state

Check reports once per umbrella: verify provenance (worktree, SHA, raw output) and diff against the spec. The seat does not re-run a gate the umbrella proved, re-running only on a gap. Two lanes agreeing raises no confidence, because they can share one stale input (`two-lanes-shared-stale-green`).

A PR body claiming what the PR does not do gets checked against the file list (`body-contradicted-its-diff`). Checking is cheap. A body that contradicts its diff is invisible afterwards.

## 6. Ask the planner seat when the call is a judgement

Architecture, security and crypto, product semantics, and any dilemma where two rules point opposite ways are not yours to improvise. Spawn `fable-planner`, a fresh agent on the strongest planning model, with the decision, the constraints and the options. Not the whole run.

- Frame the consult around the subsystem, not the hole in front of you (§7).
- One consult per decision. Past an hour, start a new one; a stale consult reasons from premises the run has since disproved.
- Routine dispatch specs come from this same seat (`agy-delegate` §Dispatch), and from the same agent while it is inside that hour. The planner is not reserved for hard calls: it is where every spec is written.
- Its ruling binds that decision, and what it explicitly deferred stays deferred.
- A ruling you disagree with is still the ruling. Record the disagreement in the plan file and park it (§10).

## 7. Gates and rulesets: flip the setting, do not build the machine

A broken gate blocks every PR in the repo, including the PR that fixes it (`six-prs-through-their-own-gate`).

- Ask whether the gate should exist at all before asking how to fix it. Decide per subsystem, not per hole (`four-rulings-one-gate`).
- Prefer a setting to a workflow. Rulesets are editable through the API, atomically, with no PR. One hand-built gate duplicated `required_review_thread_resolution`, already on in the same ruleset.
- Never write a check that parses a vendor's text: comment bodies, review states, marker strings. None is a documented contract and anyone who can comment can trigger it. If you need a control, take the tool away from the agent instead.
- Never ship a change whose own merge depends on the thing it is changing. Flip the setting first, then land the code. Nothing joins `required_status_checks` until one live PR has passed through it, watched. Product PRs never queue behind gate PRs.
- Fail-closed is for security decisions, not plumbing (`unreadable-policy-blocked-repo`).

## 8. Merging: take it to green and leave it

Mechanics are `pr-watch` Phase 3. Specific to unattended:

- Never arm auto-merge. Reviewers cannot block a merge, so it fires the moment CI goes green, before the reviewer has finished, and `required_review_thread_resolution` has nothing left to block on (`prismalens-388-auto-merge`).
- An organizer that cannot merge with the operator present does not merge at all. Take the PR to green, report it ready, leave it (§10).
- With a standing grant on a classic repo: one at a time, checking the gate after each. Every merge puts the other open PRs behind the base, auto-merge never updates a branch in that state, and nothing tells you. Go and look. Rebase the PRs you are parking at the end of the drain, not the start.

## 9. Never bypass a ruleset or a gate

When a gate blocks the only fix available, escalate. Waiting out a cooldown inside an eight hour window is cheap. A bypass cannot be undone.

Tell a gate that is failing, where retrying is right, from one that cannot be satisfied, where retrying burns the run (`gate-demanded-impossible-evidence`). The tell: the same action gives the same empty result twice with no error. On the second, stop and escalate.

The PR that repairs a gate is the worst candidate in the repo for skipping review. A gate change reviewed only by the model that wrote it is the failure independent review exists to catch (§7).

- A conditional pre-authorisation ("this might need a bypass") is a reserve, not an instruction. Write down the exact condition that would spend it.
- Never reach for a skip flag, an `--admin` merge, a `--no-verify` push, or a ruleset edit. If a lane already used one, record it and stop that lane. Do not keep the result.
- A real dilemma goes to the planner seat (§6).

## 10. Park anything that needs the operator to sign off

- Work that changes what the operator sees or owns goes to green and stops: interface shape, exported API, architecture naming, scope. Never merge it.
- PRs that have diverged, been superseded or gone obsolete get a comment stating the state and stay open. Never close one. A PR earns the comment on three grounds: its body puts it outside current scope, it carries an open question only the operator can answer, or its diff no longer applies for some reason other than a mechanical rebase. Age alone is not divergence.
- An honest gap beats an invented claim. Say where the evidence for a parked item is incomplete.
- Every parked item goes in the plan file's decision list as a specific question with options, never "needs review".

## 11. Short output, and near-silence once the operator is away

Findings, decisions, evidence, SHAs, blockers. Do not restate the plan, narrate intent, or re-summarise logged work. Every dispatched agent gets the same instruction. A tick with no dispatch is a valid tick, one line with the reason.

While the operator is away, the terminal has no reader, and the plan file is the record and the report. A tick that dispatched, verified and logged reports one line, or nothing at all. Spend the words on the plan file and issue comments rather than scrollback. Full reporting resumes for the handback. Plain sentences, identifiers and commands exact; compress the words, never the meaning.

Lead with what landed, and the SHAs of anything merged or pushed, before anything pending (`merge-reported-as-waiting`). Saying nothing about a finished step reads as "it did not happen" and costs a verification round. A lane that refused an unsourced order goes in the report as correct, not as a failed dispatch.

## Wake-up checklist (each tick)

1. Read the plan file first. It holds the state, not your memory.
2. Confirm the cron is still armed (`CronList`). If the session restarted, it is gone (§0).
3. Confirm every lane is alive by listing agents. Any lane saying "standing by" gets the §3 fix first.
4. Check real state, not reports: default branch SHA, each PR's head SHA, each gate's description string.
5. Dispatch only work whose prerequisites are final. A lane that depends on an in-flight template gets written twice.
6. Append findings and decisions to the plan file. One or two lines to the terminal.

Hand back on a hard blocker or when the work is genuinely done, not on a timer. Land the end-of-session deliverable the operator asked for, tear down the cron and every other watch (§3), and leave the plan file's decision list as the first thing they read: each entry a question, its options, and what it blocks.

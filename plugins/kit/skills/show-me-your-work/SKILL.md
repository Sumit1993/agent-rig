---
name: show-me-your-work
description: "Keep a reviewable decision trail for long-running or unattended work: a TSV log with one row per decision (what, why, evidence, result). Local by default; commit it when a reviewer needs the trail to trust the result. Use for /show-me-your-work, autonomous or multi-phase runs, or work a human reviews after stepping away."
metadata:
  version: "1.0.0"
  upstream: "cursor/plugins pstack/skills/show-me-your-work"
---

# Show me your work

For work a human reviews after the fact, a decision trail lets them reconstruct what was decided, why, and on what evidence, without rerunning the work or reading the whole transcript. Keep one canonical log so the trail is consistent and a future agent can find it.

This is the artifact the **unattended-run** skill's verify-every-claim rule needs. That skill says
a delegate's claim is worthless without evidence; this one is where the evidence pointer gets
written down at the moment the decision is made, instead of reconstructed from a transcript later.

## The format

A single TSV file, one row per decision. TSV because GitHub renders it as a sortable table, `column -s$'\t' -t` and spreadsheets read it, and a row appends with one command. Cells stay single-line. Evidence is a pointer, not prose.

Copy `references/decision-log-template.tsv` (the header row) to start a clean log. Columns:

- **ts.** ISO8601 timestamp. The timeline axis.
- **phase.** The phase or workstream.
- **decision.** What was chosen or done, one line.
- **why.** The reason in plain words. If a principle drove it, say it plainly (`explored options first, this was a one-way door`), not as a jargon tag.
- **evidence.** A link or path that proves it: commit SHA, PR number, `file:line`, or an artifact, trace, or screenshot path. Never a paragraph.
- **result.** The outcome or predicate state: `tests green`, `reverted`, `pixel-diff 0`, `INCONCLUSIVE`, `open`.

An example, plain-spoken so a reviewer reads it at a glance. This is illustration only; don't copy these rows into a real log.

```
ts	phase	decision	why	evidence	result
2026-05-24T09:02:00Z	frame	counted the work first, about 100 components and roughly 75 hours	wanted to know the size before starting a long run	commit 3a9f1c2	found 5 things to sort out before starting
2026-05-24T09:40:00Z	harness	took screenshots of the old version before changing anything	so we can compare old against new and catch any visual change	scripts/snapshot.sh, baseline/	saved 120 reference screenshots
2026-05-24T11:15:00Z	widget	moved the widget styles over without changing how it looks	keep the change small and the result identical	commit 7c21e0a, pixel-diff 0	looks identical, tests pass
2026-05-24T12:30:00Z	widget	threw out a helper's work because its screenshots were blank	checked the real files instead of trusting its summary	worktree reset	reverted, tightened the instructions for next time
```

## Logging a row

Write each entry the way you'd tell a teammate what you did. Plain words, concrete actions, no AI speak or abstract jargon. The Language & Communication Style rules in `AGENTS.md` apply to log text too. A reviewer should understand each row without decoding it.

Use the helper so rows stay well-formed: `scripts/log.sh <logfile> <phase> <decision> <why> <evidence> <result>`. It stamps `ts`, writes the header on first use, strips stray tabs/newlines, and prefixes any cell starting with `=`, `+`, `-`, or `@` with a single quote so a reviewer opening the log in a spreadsheet doesn't trigger formula execution. A bare `printf` appending a row works too, but mind those same bytes if cells come from generated or user-supplied text.

Log decision points and checkpoints, not every action: a fork chosen, a unit completed with its verification result, a pivot or revert with its trigger, a blocker surfaced, a gate fixed. For loop runs, one row per iteration. Skip the trivial and self-evident.

## Where it lives

By default the log is a working artifact, not committed. Keep it at `decisions.tsv` in the work dir, or `.audit/<task-slug>.tsv` when several efforts run at once, and leave it out of git. Most work doesn't need a committed trail; the local log still keeps the run honest and can be discarded after.

Agents work in a worktree, so the log lives in the worktree that produced it. When several lanes
run at once, one log per lane, named for the lane.

Commit it only when the work is ambitious enough that a reviewer needs the trail to trust the result: a large cross-language port, a multi-week migration, anything where confidence has to be shown rather than assumed. A committed log renders as a table in the PR. This repo is public, so a committed log carries no keys, tokens, real payloads, personal names, or emails.

## Rules

- One row is one decision or checkpoint. If it doesn't fit on one line, the decision isn't crisp yet.
- Append-only. A wrong call gets a new row that supersedes it. Never edit or delete history.
- Prefer evidence produced by committed scripts over hand-made one-offs, so a reviewer can rerun it. A rule you have written down twice belongs in a script or a lint, not in a third paragraph.

## Audit the log against the transcript

At the end of the run, before handing back, check the log told the truth. This session's transcript
lives under `~/.claude/projects/<escaped-cwd>/`, one `.jsonl` per session; read this session's file.
Don't glob across the other project directories, which reads unrelated private chats. Walk the log
against what actually happened:

- Every row maps to a real action. Cut invented or aspirational entries.
- Each row's evidence resolves and shows what the row claims.
- A fork, pivot, or abandoned approach that shaped the work but isn't logged is a gap. Add it.
- Drop padding. If nobody would audit a row, it doesn't earn its place.

Fix the log, not the story. If the work diverged from what a row claims, the row is wrong.

## Cross-model review of the trail

Before handing back, spawn a reviewer on a different model family from the one that did the work.
Self-review is not a substitute; the point is fresh eyes you cannot bring yourself. Route it
through the **agy-delegate** skill (Gemini 3.7 Flash is the cheap different family) or, staying in
the Claude family, a tier you did not run the work on. The reviewer reads the audit trail and the
run's transcript, then flags what the user should pay attention to. Not a redo of the work, a scan
for what's suboptimal or risky.

- Decisions logged with weak or absent evidence.
- Verification steps skipped or claimed without proof in the transcript.
- Choices that look risky in hindsight (premature, scope-creeping, papering over a symptom).
- Gaps the user would otherwise miss on a casual skim.

Every reply for a run that produced a trail ends with an "Attention" section. Lead with the reviewer's model on its own line (`reviewed by <model>`), then list each flag pointing to specific rows or moments. "No flags" is a valid value; the model name is not. The self-audit asks if the log told the truth; this asks what the user should still scrutinize even when it did.

## Reviewing the trail

Read top to bottom, follow the evidence pointers, spot-check. GitHub renders a committed TSV as a table; `column -s$'\t' -t decisions.tsv` renders it in a terminal. A row whose evidence doesn't resolve, or whose result is unverified, is the audit catching a gap.

## Composing this skill

Other skills route their audit trail here instead of inventing one. Reference it by name and let it own the format; don't restate the columns. The **unattended-run** and **anti-stall** skills are the
main callers: a lane that reports "standing by" with no new row since its last checkpoint is a
stalled lane, and the log is where you see that without reading the transcript.

## Patched from upstream

Upstream is `cursor/plugins` `pstack/skills/show-me-your-work`, written for Cursor. Changes here:

- The transcript path moves from Cursor's `agent-transcripts/` to Claude Code's
  `~/.claude/projects/<escaped-cwd>/*.jsonl`.
- "Spawn a subagent on a different model family" names the actual route: **agy-delegate**, or a
  different Claude tier, per the routing table in `AGENTS.md`.
- The `unslop` and `encode-lessons-in-structure` references become the `AGENTS.md` writing rules
  and one plain sentence, since those pstack skills are not vendored.
- Added the worktree rule, the public-repo scrub, and the composition note tying it to
  **unattended-run** and **anti-stall**.

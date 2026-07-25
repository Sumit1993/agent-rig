---
name: anti-stall
description: "Doctrine for waiting on long-running work without dozing — sentinel-first launches, evidence-keyed background waits, batch scripts over agent-per-step. Load BEFORE launching any delegation, build, campaign, CI run, or command expected to outlive one turn, and whenever a wait has gone quiet longer than expected."
metadata:
  version: "1.0.0"
---

# Anti-stall — waiting on long work

Root cause of every observed stall: the wait was keyed on **process liveness or a timer** (a Monitor asking "is it alive", a warmup countdown, "did setup exit"). Every wait keyed on **durable evidence** — a sentinel line, an artifact file, a commit — worked. That is the whole doctrine.

## 1. Sentinel-first
Every long command logs to a file and appends its own exit fact:

```bash
(<cmd> > "$LOG" 2>&1; echo "DONE rc=$?" >> "$LOG")
```

Without a sentinel the completion signal is transient and a missed wake loses it. With one, the fact is still in the log on the next check.

## 2. Wait = background until-loop on evidence
Right after launch, start a **background Bash** that blocks on the durable fact. Its completion fires exactly one notification — that is the wake signal.

```bash
for i in $(seq 1 N); do grep -q DONE "$LOG" && exit 0; sleep 15; done; echo WATCH_TIMEOUT
```

Size `N` as the deadline: `expected_minutes * 4 + 40`. The loop length **is** the timeout — `WATCH_TIMEOUT` in the log means stop waiting and go salvage.

**The Monitor tool is banned for this.** Monitors gated on `pgrep`/timers slept through six-plus wakes in a single session. Monitor is fine for genuinely open-ended watching (new PR comments, a file that may change), never for "did this finish".

## 3. Check before waiting
On **any** wake — the expected notification, an unrelated one, a user message — check the sentinel and the expected artifacts **first**, then decide. A turn that ends "waiting" without a fresh check is the single most common stall.

## 4. Orchestrator watches evidence, not reports
Treat a handler subagent saying "waiting" as suspect. Never acknowledge two consecutive "waiting" reports without reading the log or worktree yourself. Resume it with "check evidence now, continue foreground" instead.

## 5. Deadline fallback
At expected duration + 10 min of silence, read the logs yourself and salvage. **Work often landed despite a silent handler** — check artifacts before re-running anything, or you redo finished work.

## 6. Batch mechanical sequences — don't babysit them
If the remaining work is a known list of steps (N campaign runs, M migrations), write it as **one unattended script** with a per-step sentinel and a final marker, failures logged-and-continued:

```bash
for id in "${STEPS[@]}"; do
  <run "$id"> >> "$LOG" 2>&1; echo "STEPDONE $id rc=$?" >> "$LOG"
done
echo BATCH_COMPLETE >> "$LOG"
```

Wake once, at the end. Agent-per-step is where dozing lives; a script cannot doze.

## Killing safely
Any `pgrep -f` / `pkill -f` whose pattern appears in your own shell's command line kills **your own shell** (exit 144). Always use a self-unmatchable bracket pattern, and make it specific enough to hit only your run:

```bash
kill -9 $(pgrep -f "issue39[-]rca")
```

Self-test at arm time: run the pattern once — it must match exactly one live PID.

---
name: no-comments
description: "Enforce the comment budget on a diff: spawn the comment-sicko agent, act on accepted findings, offer a check in place of prose. Use for /no-comments or before merging a diff whose comments narrate."
metadata:
  version: "1.0.0"
  upstream: "cursor/plugins pstack/skills/no-comments"
---

# No comments

Spawn the comment sicko. Act on accepted findings.

Authoring agents defend comments. Defer to the sicko's fresh perspective.

The standard it enforces is the comment budget in `AGENTS.md`: a comment states the one
non-obvious constraint in three lines or fewer, plus a pointer (issue number, doc path) for the
story. Everything else belongs in the issue, PR, or living doc that pointer names.

## Scope

Use the caller's files or diff. Otherwise use the current diff against the base branch, default `main`, including the working tree.

Run this against a worktree, never a repo's main checkout.

A repo whose existing comments are essays does not get swept by this skill. New code in the diff
gets the budget; slimming the legacy essays is a separate, deliberate task.

## Steps

1. Spawn the `Agent` tool with `subagent_type: "comment-sicko"`. Pass the scope, including the
   worktree path, anchored so every command it runs lands there. Do not restate its rules.
2. Inspect its report and diff. Reject application-code edits, scope escapes, exception-protected deletions, misstated `MUST KILL` reasons, and flags that treat kept intentional code as guilty. Reshape flags on our-code surprises stay actionable. Do not restore those comments. A keep survives only with proof it is about something we cannot change. Audit missed scoped lint and TypeScript suppressions. Correctness or safety suppressions stay actionable `MUST KILL`s. Restore deletions only with exact exceptions and scoped proof. Before accepting thin `IMPORTANT` or `do not remove` kills or keeps, hunt the history for their symbol: `git log -S<symbol>`, the commit that introduced it, the PR and issue it links. If a kill is ambiguous, do not restore. If a keep is refuted or still ambiguous, delete it. Revert and rerun one rejected report with the failure named. Reject a second, report it open, and fail `/no-comments`.
3. Fix trivial accepted flags directly by deleting a dead path, dropping a parameter, or using the real API. If any fix needs a shape, spawn the `fable-planner` agent once for the accepted set and surrounding code. Stop at the sketch. The planner shapes. Step 4 implements.
4. Implement the smallest root-cause fix in scope. Remove every named workaround. If the root cause is out of scope, land the smallest in-scope fix and report the rest open. Intent, not licence: fix real causes, redesign as if the requirement had always existed, never bolt a symptom guard onto a bug. Neither widens the fence nor authorizes fixing instances outside it.
5. Constraint comments say `do not remove`, `do not change wording`, or `talk to X before changing`. Leave keeps about things we cannot change. Offer the cheapest in-scope type, runtime, test, or CI lint that makes the comment unnecessary. Wait for interactive approval. Unattended runs and evals require caller pre-approval. If approved, encode then delete. Otherwise delete, report the constraint open, and sketch the out-of-scope work.
6. Report the deletion count, restored comments, reruns, planner sketch, fixes, encoding offers, encodings, unenforced constraints, and other open work.

## Patched from upstream

Upstream is `cursor/plugins` `pstack/skills/no-comments`, written for Cursor. Changes here:

- `Task` / `subagent_type: "Comment Sicko"` becomes the `Agent` tool with
  `subagent_type: "comment-sicko"`, matching the vendored agent in `agents/comment-sicko.md`.
- `/how` and `/why` (pstack skills, not vendored) become the concrete history hunt they stand
  for: `git log -S`, the introducing commit, the PR and issue.
- `/architect` becomes the `fable-planner` agent, per the routing table in `AGENTS.md`.
- The `principle-fix-root-causes` and `principle-redesign-from-first-principles` references
  become the one sentence of intent they carried, since those skills are not vendored.
- Added the comment budget as the named standard, the worktree rule, and the
  do-not-sweep-legacy-essays carve-out.

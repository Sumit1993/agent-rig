---
name: docs-governance
description: "Audit and fix docs drift, then install prevention nets — the four-phase docs-governance playbook. Trigger: before merging a release PR on a repo whose registry entry has a `docs` block (the release gate points here), when the user asks for a docs audit/refresh, or when docs drift is suspected."
metadata:
  version: "1.0.0"
---

# Docs governance — audit → fix → retrofit → nets

The problem: features ship and PR descriptions describe them, but docs — CLI references, guides, READMEs, `--help` strings, task-runner `desc:` lines — silently drift. Operators rely on docs, not PR archaeology.

Per-repo parameters come from the kit registry: `kit-meta.sh get <owner/repo> docs` (docs-site dir, surface list, code globs for nets). Verify the surface list against the working tree before using it, and generate audit/fix prompts fresh each run — never reuse a stored prompt file; stored prompts rot.

## Illustration standard

**Complex concepts must be shown, not only described.** A passage that requires the reader to hold **three or more moving parts** in their head at once — a resolution order, a mode/topology, a state machine, a pipeline, a precedence rule, or a side-by-side comparison — must carry at least one concrete artifact alongside the prose. Prose-only in that situation is a documentation gap, reviewable as one. Same "3+ moving parts" test already used elsewhere in this toolchain — one threshold, not a second competing definition.

Accepted artifacts, in preference order:

1. **Worked example** — real or realistically simulated input mapped to its actual output. Cheapest to write, easiest to verify against the code, rots loudly (a wrong example contradicts a test).
2. **Terminal transcript** — for anything a CLI prints. Greppable, diffable, reviewable in a PR, no binary in git.
3. **Diagram** — for topologies, orderings, and state. Use the repo's established diagram idiom; no new build dependency to render one. Where that idiom is a fenced diagram source rendered client-side, declare no colors — the renderer picks a palette per theme, and a hand-picked one breaks in whichever theme it wasn't written for. Hand-authored SVG is a last resort among diagrams, and must take its colors from theme tokens (`currentColor` or the site's CSS custom properties), never hex literals.
4. **Screenshot** — last resort, only when the subject is genuinely graphical (a rendered graph view, a web UI). Must name what invalidates it. Ranked last on purpose: docs governance exists to fight silent prose drift, and a screenshot drifts *more* silently — no grep, test, or build ever contradicts it. For CLI-shaped repos a transcript does the same job and stays reviewable in a diff.

**Name the passage and the form.** "`<file>:<line>` — the `<name>` resolution order is a five-step precedence chain in prose; needs a flowchart or a worked example per input shape" is a finding. "Add a diagram" is not.

**Below the threshold, don't decorate.** A visual restating a two-step sequence is noise; adding one is reviewable too.

## Phase 1 — audit (read-only, parallel)

Three agents, merged into ONE ranked queue (the first two overlap — both will flag the CLI reference):

1. **Feature-docs gap review**: for recent major features, survey EVERY doc surface — the registry's `docs.surfaces` list plus anything it missed: docs-site pages, all READMEs (root and per-package; a package whose siblings have READMEs and it doesn't is a gap), CONTRIBUTING, CLI `usage()`/`--help` strings, task-runner `desc:` lines, and header comments that describe file layouts (docs readable by agents count). Per gap: file:line · what it says now (one line) · what it should say (one line) · priority (high = actively wrong, medium = incomplete, low = nice-to-have).
2. **Merged-PR docs-miss sweep**: `gh pr list --state merged --limit 20`, skip docs-only/dependabot, and for each PR determine what operator-facing surface changed and whether any doc surface mentions it.
3. **Illustration-gap review**: same doc surfaces, judged against the [illustration standard](#illustration-standard) — give the agent the three-or-more-moving-parts threshold and the four accepted forms. Per gap: same `file:line · what it says now · what it should say · priority` shape as above, but "what it should say" names the form (worked example / transcript / diagram / screenshot). The agent must also list the pages it considered and rejected as below-threshold, so the queue doesn't inflate with decoration findings.

On completion record the marker that opens the release gate:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/kit-meta.sh" observe <owner/repo> docs_audit_at "$(date +%s)"
```

## Phase 2 — fix (one docs-refresh PR)

One branch (`wt.sh create docs-refresh`), one delegated coding run, one PR. Non-negotiable spec rules:

- **Prune, don't append**: rewrite each stale sentence to be currently-true; never "but now also…". Delete false claims.
- **Verify every claim against code before writing it** (verb lists ↔ dispatcher source, record fields ↔ serializer, defaults ↔ task runner). The coding agent skips-with-reason rather than invents.
- **Verification gate**: docs-site build passes; the diff contains ONLY docs/comment/usage-string changes — check every non-markdown file in the diff file-by-file (delegates smuggle behavior changes into "docs-only" diffs).
- CLI pre-review before push: `scripts/cr-preview.sh` — the `review-evidence` required check is what holds the merge, so run it when you want the diff read before the PR exists.

## Phase 3 — retrofit the open backlog

Sweep open issues; append a docs acceptance criterion to each issue that ships operator/agent-facing surface:

- Format: `- [ ] Docs: <specific surfaces, comma-separated> updated (or explicitly noted why none apply)` — **name real files/sections, never a generic "update docs"** (generic lines get checkbox-ticked without thought).
- Ground surface choices in the actual docs structure — read the pages first.
- Skip: issues closed by in-flight PRs, umbrella/research issues, pure-internal refactors.
- Edit safely: fetch the fresh body, append, `gh issue edit N --body-file` — never lose existing content.

## Phase 4 — prevention nets (what makes it stick)

Three layers, in effectiveness order; keep nets in their own PR, separate from the docs-refresh:

1. **`.coderabbit.yaml` path instructions** — the strongest net: the PR diff is where a docs gap is objectively visible. Schema constraint: `reviews.path_instructions[].path` takes a SINGLE glob string — one entry per glob from the registry's `docs.code_globs`, duplicated instruction text. Wording constraint: phrase as "must update the RELEVANT surface, and name the specific stale surface" — "must touch docs/" is satisfiable by any unrelated docs edit. While in there, distill the repo's key invariants into path instructions — this is the only channel by which external-hub design decisions reach CodeRabbit's reviews. Append the [illustration standard](#illustration-standard) too, verbatim, as its own paragraph in every path entry (same one-glob-per-entry duplication as above):

   ```
   When a PR adds or substantially rewrites documentation that explains a resolution order, a mode/topology, a state machine, a pipeline, a precedence rule, or a side-by-side comparison — anything with three or more interacting parts — flag it as a documentation gap if the passage is prose-only. Such a passage must carry a worked example (real or realistically simulated input mapped to its output), a terminal transcript, a diagram (inline SVG or fenced diagram source — never a new build dependency added just to render one), or, only when the subject is genuinely graphical, a screenshot that names what invalidates it. Name the specific passage and which form fits; "add a diagram" is not an actionable finding. Do not flag prose that is below this threshold — a visual restating a two-step sequence is noise.
   ```

2. **Issue template**: required "Docs impact" textarea on the feature template ("which doc surfaces will this touch — 'none' must be justified").
3. **PR template**: a `## Docs` checklist ("docs updated for every changed surface, or none affected — explain").

Process-side layer: every implementation spec handed to a coding agent gets a "Docs surfaces" deliverable section naming specific files, or an explicit "none affected because…" — replicate in the repo's AGENTS.md. Where a named surface explains three or more interacting parts (per the [illustration standard](#illustration-standard)), the spec must also say which artifact will carry it — prose-only for that kind of surface is an incomplete spec.

## Sequencing

Audit (parallel, read-only) → docs-refresh PR → issue retrofit + nets PR (parallel) → merge docs last if code PRs are in flight (it absorbs their wording fallout). Trap: a docs-refresh written while a feature PR is open cannot document that feature, and the feature PR ships docs-blind if the CodeRabbit net merges after it. After merging everything, run one final "does every verb/flag that landed appear in the reference?" sweep before declaring done. CodeRabbit reviews the docs PR itself and catches semantic drift in the NEW text — treat those findings as real.

## Release gate — the recurrence trigger

The kit hook `release-docs-gate.sh` blocks `gh pr merge` of a release PR (title matching `release`) on any registry repo with a `docs` block unless `docs_audit_at` is within 14 days. Phase 1 records the marker. `DOCS_GATE=skip` in the merge command overrides (user-approved only).

Reference implementations to copy from: sreforge PRs #59 (docs-refresh) + #61 (nets); prismalens PRs #205 (docs-refresh) + #204 (nets). Rollout evidence lives in the prismalens and sreforge hub notes (`docs-governance-playbook-*`, `build-specs-must-name-docs-surfaces`).

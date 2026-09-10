---
name: docs-governance
description: "Audit and fix docs drift, then install prevention nets. Load before merging a release PR on a repo whose registry entry has a docs block, or when docs drift is suspected."
metadata:
  version: "2.0.0"
---

# Docs governance: audit, fix, retrofit, nets

Features ship, PR descriptions describe them, and the docs drift: CLI references, guides, READMEs, `--help` strings, task-runner `desc:` lines. Operators read docs, not PR history.

Per-repo parameters come from the registry: `kit-meta.sh get <owner/repo> docs` (docs-site dir, surface list, code globs for nets). Verify the surface list against the working tree before using it. Generate audit and fix prompts fresh each run; a stored prompt file rots.

## Illustration standard

A passage that makes the reader hold three or more moving parts at once (a resolution order, a mode or topology, a state machine, a pipeline, a precedence rule, a side-by-side comparison) must carry one concrete artifact alongside the prose. Prose-only there is a documentation gap, reviewable as one. Same threshold the rest of the toolchain uses; do not invent a second.

Accepted artifacts, in preference order:

1. Worked example. Real or realistically simulated input mapped to its actual output. Cheapest to write, easiest to verify, rots loudly.
2. Terminal transcript. For anything a CLI prints. Greppable, diffable, no binary in git.
3. Diagram. For topologies, orderings and state. The repo's established idiom, no new build dependency. A fenced source rendered client-side declares no colors, since the renderer picks a palette per theme. Hand-authored SVG is the last diagram choice and takes colors from theme tokens (`currentColor` or the site's CSS custom properties), never hex literals.
4. Screenshot. Only when the subject is genuinely graphical (a rendered graph view, a web UI), and it must name what invalidates it. Last because nothing ever contradicts a stale screenshot; for a CLI, a transcript does the job and stays diffable.

Name the passage and the form. "`<file>:<line>`: the `<name>` resolution order is a five-step precedence chain in prose; needs a flowchart or a worked example per input shape" is a finding. "Add a diagram" is not. Below the threshold, do not decorate: a visual restating a two-step sequence is noise, and adding one is reviewable too.

## Phase 1: audit (read-only, parallel)

Three agents, merged into one ranked queue; the first two overlap and both will flag the CLI reference.

1. Feature-docs gap review. For recent major features, survey every doc surface: the registry's `docs.surfaces` plus anything it missed, docs-site pages, every README (root and per package; a package whose siblings have READMEs and it does not is a gap), CONTRIBUTING, CLI `usage()` and `--help` strings, task-runner `desc:` lines, header comments describing file layouts. Per gap: file:line, what it says now (one line), what it should say (one line), priority (high = actively wrong, medium = incomplete, low = nice to have).
2. Merged-PR docs-miss sweep. `gh pr list --state merged --limit 20`, skip docs-only and dependabot, and for each PR find what operator-facing surface changed and whether any doc surface mentions it.
3. Illustration-gap review. Same surfaces, judged against the standard above. Give the agent the three-or-more threshold and the four forms. Same per-gap shape, with "what it should say" naming the form. The agent also lists the pages it rejected as below threshold, so the queue does not fill with decoration findings.

On completion record the marker that opens the release gate:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/kit-meta.sh" observe <owner/repo> docs_audit_at "$(date +%s)"
```

## Phase 2: fix (one docs-refresh PR)

One branch, one delegated coding run, one PR. `AGENTS.md` says how the worktree is made.

- Prune, do not append. Rewrite each stale sentence to be currently true, never "but now also". Delete false claims.
- Verify every claim against code before writing it: verb lists against the dispatcher, record fields against the serializer, defaults against the task runner. The coding agent skips with a reason rather than invents.
- Verification gate: the docs-site build passes, and the diff holds only docs, comment and usage-string changes. Check every non-markdown file in the diff one by one; delegates smuggle behaviour changes into "docs-only" diffs.
- Nothing local runs before the PR exists. `CI gate` and the conventional-commit title check are the only required checks, and unresolved review threads hold the merge (`pr-watch` Phase 0).

## Phase 3: retrofit the open backlog

Sweep open issues and append a docs acceptance criterion to each one that ships an operator- or agent-facing surface.

- Format: `- [ ] Docs: <specific surfaces, comma-separated> updated (or explicitly noted why none apply)`. Name real files and sections, never "update docs"; generic lines get ticked without thought.
- Read the docs pages first, so surface choices match the real structure.
- Skip issues closed by in-flight PRs, umbrella or research issues, pure-internal refactors.
- Edit safely: fetch the fresh body, append, `gh issue edit N --body-file`. Never lose existing content.

## Phase 4: prevention nets

Three layers in effectiveness order, in their own PR, separate from the docs refresh.

1. `.coderabbit.yaml` path instructions. The strongest net, because the PR diff is where a docs gap is visible. `reviews.path_instructions[].path` takes a single glob string, so one entry per glob from the registry's `docs.code_globs`, instruction text duplicated. Phrase it as "must update the RELEVANT surface, and name the specific stale surface"; "must touch docs/" is satisfied by any unrelated docs edit. While there, distil the repo's key invariants into path instructions; it is the only channel by which external-hub design decisions reach CodeRabbit. Append the illustration standard verbatim as its own paragraph in every entry:

   ```
   When a PR adds or substantially rewrites documentation that explains a resolution order, a mode/topology, a state machine, a pipeline, a precedence rule, or a side-by-side comparison — anything with three or more interacting parts — flag it as a documentation gap if the passage is prose-only. Such a passage must carry a worked example (real or realistically simulated input mapped to its output), a terminal transcript, a diagram (inline SVG or fenced diagram source — never a new build dependency added just to render one), or, only when the subject is genuinely graphical, a screenshot that names what invalidates it. Name the specific passage and which form fits; "add a diagram" is not an actionable finding. Do not flag prose that is below this threshold — a visual restating a two-step sequence is noise.
   ```

2. Issue template: a required "Docs impact" textarea on the feature template ("which doc surfaces will this touch, and 'none' must be justified").
3. PR template: a `## Docs` checklist ("docs updated for every changed surface, or none affected, with an explanation").

Process side: every implementation spec handed to a coding agent gets a "Docs surfaces" deliverable naming specific files, or "none affected because…". Put the same rule in the repo's AGENTS.md. Where a named surface explains three or more interacting parts, the spec also says which artifact carries it; prose-only there is an incomplete spec.

## Sequencing

Audit, then the docs-refresh PR, then retrofit and nets in parallel, then merge docs last if code PRs are in flight, since it absorbs their wording fallout. Trap: a docs refresh written while a feature PR is open cannot document that feature, and the feature PR ships docs-blind if the CodeRabbit net merges after it. After everything merges, run one final "does every verb and flag that landed appear in the reference?" sweep. CodeRabbit reviews the docs PR itself and catches drift in the new text; treat those findings as real.

## Release gate

The kit hook `release-docs-gate.sh` blocks `gh pr merge` of a release PR (title matching `release`) on any registry repo with a `docs` block unless `docs_audit_at` is within 14 days. Phase 1 records the marker. `DOCS_GATE=skip` in the merge command overrides, user-approved only.

Reference implementations: sreforge PRs #59 (docs refresh) and #61 (nets); prismalens PRs #205 (docs refresh) and #204 (nets). Rollout evidence is in the prismalens and sreforge hub notes (`docs-governance-playbook-*`, `build-specs-must-name-docs-surfaces`).

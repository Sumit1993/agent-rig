---
name: direction
description: "Answer where the estate stands and what to work on next, across all five repos, without reading an issue list. Load when a session is asked what to do next, when picking up work cold, or when a repo's queue has to be ranked. Priority is a p0 label, placement is a numbered milestone, and the pick is one command."
---

# Direction

Run `direction.sh` first, with no argument for the whole estate or one `owner/repo` to narrow it. The pick is the first line of section 4. Never run an unfiltered `gh issue list`; that is the failure this replaces.

A goal is a milestone whose title starts with three digits and a space, `010 R1 - ...`. Lower number is earlier. A milestone without that prefix is a bucket and is never current. There are no due dates anywhere and nothing is ever overdue.

An issue with no milestone is not startable. It is triage debt and appears in section 5.

`p0` sorts an issue to the front of its own goal. It never crosses goals and never makes an unplaced issue startable. Section 1 is a diagnostic, not a pick: a line reading `NO MILESTONE` or `LATER GOAL` is a triage flag to report, not work to start.

Sequence inside one goal is carried by a `blocked` label plus a comment naming the blocker. Never a hand-written ordered list in an issue body.

The full ruling, with the evidence and the falsifiers, is `Sumit1993/claude-kit#100`.

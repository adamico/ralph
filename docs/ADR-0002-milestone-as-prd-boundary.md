# ADR-0002 — GitHub milestone as PRD boundary

**Status:** accepted

## Context

The GitHub backend needs a way to scope which issues ralph considers during an
engagement. Candidates: milestone, label prefix, GitHub Project, separate repo.

## Decision

A GitHub **milestone** is the PRD boundary for the GitHub backend. Ralph accepts
it as a positional argument (`ralph once <milestone>`, `ralph run <N> <milestone>`)
rather than config, because it identifies *which queue to drain* per invocation —
the same role `.scratch/<prd>/` plays in the fs backend.

## Rationale

- Milestones have a native lifecycle: open while in progress, close when the queue
  drains. No bookkeeping labels needed.
- `gh issue list --milestone` is a first-class filter — no post-hoc jq gymnastics.
- A milestone is visually coherent in the GitHub UI: one page shows all issues in
  the queue, their state, and progress.
- Label prefixes would be invisible in search/filters; GitHub Projects add OAuth
  complexity; a separate repo is disproportionate.

## Consequences

- Milestone title must be passed each invocation; it cannot be omitted.
- `GH_MILESTONE` is not a config key — remove it from `.ralph.conf` examples.
- One active milestone at a time per invocation; parallel milestones require
  parallel ralph processes.

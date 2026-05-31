---
status: accepted
---

# Clean-tree preflight guard against false-green-on-restart

This extends **ADR-0009 (interrupted-iteration recovery)**. ADR-0009 fixed how a
human *recovers* a crashed iteration — redo-from-scratch against a recorded
baseline on the engagement branch (`ralph recover`/`cmd_recover`) — but
explicitly **deferred** the automated preflight self-heal, because auto
force-push risks nuking legitimate WIP. This ADR adds the preflight *detection*
half that was deferred, staying strictly **refuse, never auto-heal**: ralph
hard-stops before an iteration when the tree is in exactly the indeterminate
state ADR-0009 describes, and points the operator at the recovery runbook.

The remote-mode test oracle (ADR-0008 model B) clones `origin` and tests only
**pushed** state. When an AFK iteration is interrupted mid-implementation and
ralph is restarted, the agent's work lives in an unpushed dirty tree — but the
gate clones origin and runs the *stale, pre-work* suite green. The agent trusts
that green, commits, and pushes untested/broken code. This actually happened on
`adamico/locomotion` (commits `d582210` #15, `545ecad` #16: 18 failing tests
landed on `main`, one commit message even admitting validation was "pending").

## Context

The deep cause is that "tests passed" and "what got committed" can be different
code. ADR-0008's model B states the contract "WIP must be pushed to be testable"
(cf. locomotion ADR-0022), but ralph only states it as **prompt text** — the
harness never runs `TEST_CMD` (it is prompt-text-only), so nothing *enforces*
the commit→push→gate ordering. An interrupt severs gate from commit permanently,
and a restart silently inherits the unvalidated tree.

We need a guard that is enforced by the harness, not just trusted to the agent,
and it must work even though ralph does not execute the gate itself.

## Considered Options

- **(a) Enforced clean-tree/divergence preflight (chosen).** Before each
  iteration, refuse to start unless the working tree is clean AND `HEAD ==
  origin/<branch>`. Mechanically forces commit+push before any gate runs and
  makes a restart into a dirty/unpushed tree a hard stop. Mirrors the existing
  `check_main_branch_guard` (#38). Smallest change that makes the false-green
  *impossible* under model B. Overridable with `RALPH_ALLOW_DIRTY=1`.
- **(b) Prompt-text push-before-gate (also adopted, as defense-in-depth).**
  Spell out implement→commit→push→gate, and on red roll origin back (no red/WIP
  commits left), in `build_prompt`/`build_prompt_gh`. Relies on agent behaviour,
  so it complements (a) rather than replacing it.
- **(c) Default the gate to `local` mode.** Tests the actual working tree, so no
  stale-origin gap — but weakens the sandbox isolation ADR-0008/locomotion
  ADR-0022 bought (clean linux deps, one mental model). Rejected.

## Decision

Adopt **(a) + (b)**. The harness gains `check_clean_tree_guard`, called from
`iterate_once` after the main-branch guard (returns rc 12). The generated
prompts are hardened to state the commit→push→gate sequence and the red-rollback
recovery so origin never carries red/WIP commits.

## Consequences

- A restart into an interrupted iteration now hard-stops instead of silently
  testing stale origin. The guard detects the same dead-PID/dirty/diverged state
  that `ralph status` flags and `ralph recover` heals (ADR-0009); operators
  should reach for `ralph recover` (reset to recorded baseline) rather than an
  ad-hoc reset. `RALPH_ALLOW_DIRTY=1` overrides for intentional dirty runs.
- The "blocked" recovery path changes for model B: the agent must roll origin
  back to green (reset/revert + `--force-with-lease`) rather than `git stash -u`
  an uncommitted change, since under push-before-gate the red work is already
  committed and pushed. This mirrors ADR-0009's redo-from-baseline reset.
- The divergence check is skipped when no `origin/<branch>` ref exists (cannot
  verify), and the whole guard is skipped outside a git work tree.
- If model B is ever superseded (ADR-0008's escalation to **C**, CI oracle), the
  divergence half of this guard stays valid (CI is also origin-truth); revisit
  the dirty-tree half if a future `local`-mode gate is introduced.

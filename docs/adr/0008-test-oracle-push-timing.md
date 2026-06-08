---
status: proposed
---

# Test oracle and push timing for sandboxed AFK ports

When ralph drains issues in a sandbox, "are the tests green?" needs an oracle,
and that oracle's location dictates *when* the agent must push. Three options;
we currently ship **B**.

## Context

AFK iterations run the configured Agent CLI inside a ralph-level sandbox (`AGENT_CMD="sbx run <name> -- <agent-cli>"`).
Node ports hit a hard constraint: the host workspace is bind-mounted into the
container, but its `node_modules` is built for **darwin** and is unusable by the
**linux** sandbox. So tests cannot simply run against the mounted tree. Whatever
we pick must (a) test against clean linux deps and (b) define what "green" means
and therefore when a `git push` has to happen. The dragonruby recipe already
chose B (ADR-0022, `adamico/locomotion`: "WIP must be pushed to be testable").

## Considered Options

**B — in-sandbox, push-before-green (current).** `run_tests remote` does a fresh
`git clone` of origin into `/tmp` + `npm ci`, then runs vitest. The oracle is
**origin**, so the agent must commit AND push before tests reflect its work.

- ➕ Tests exactly what lands on origin — no "green local, red remote" gap.
- ➕ Clean linux deps fall out for free; stateless, reproducible.
- ➕ One mental model with the dragonruby recipe.
- ➖ Branch history polluted with red/WIP commits (needs squash/force-push).
- ➖ Every attempt is a push (network, fires webhooks); offline = no tests.
- ➖ Cannot test uncommitted experiments.

**A — in-sandbox, push-after-green.** Test the agent's local copy first (working
tree, or a `file://` clone of the mount for clean deps); push only once green.
The oracle is the **local copy**.

- ➕ Only green commits hit origin → push *is* the done-signal; clean history.
- ➕ Fast (no network per run); iterate on uncommitted code; works offline.
- ➖ Drift risk: untracked files / `.gitignore` gaps / env diff → green locally,
  red on origin or CI.
- ➖ Must re-solve clean-linux-deps with bespoke harness logic.
- ➖ Diverges from dragonruby → two mental models in one skill.

**C — CI-oracle (GitHub Actions).** Push triggers a workflow that runs the
suite; the agent polls the check (`gh run watch` / `gh run view --log-failed`)
for pass/fail. The oracle is **CI**. This is B taken to its logical end — origin
is truth, just moved off-box and async.

- ➕ Clean linux env for free; matches what humans/PRs already see; no in-sandbox
  dep handling at all.
- ➕ Single source of truth shared by agent, CI, and reviewers.
- ➖ Async: runner spin-up + queue = minutes per iteration vs seconds in-sandbox.
- ➖ Polling + CI-log parsing burden on a low-cost Agent CLI model (more steps/tokens, no
  clean exit code).
- ➖ Same push-noise as B, amplified (CI fires every push); loses any fast local
  mode.

## Decision

Stay on **B** for now (proposed). It is the honest oracle, gives clean deps for
free, and keeps one mental model with the proven dragonruby recipe. The push
noise is the accepted cost; tidy history is a post-hoc squash concern, not a
per-iteration one.

## Consequences

- The "commit + push before tests are green" contract must be stated wherever
  the agent can read it — the generated `.ralph.conf` header (`TEST_CMD` is
  prompt-text-only) and the recipe README.
- If push-noise or per-iteration latency becomes the dominant pain, **C** is the
  natural escalation (same oracle, async) — revisit then and supersede this ADR.
- **A** is only worth it if clean history / offline / uncommitted-iteration
  outweigh the drift risk; it requires building bespoke clean-dep handling, so it
  is not a free switch.

# LittleJS Recipe

Environment recipe for native `ralph init` (ADR-0013): sandbox + dual-mode test harness for
LittleJS (node/vitest) ports. Standard-tier sibling of the *mature-external*
dragonruby recipe (imported from `adamico/locomotion`). First built in
`adamico/obsi` at `build/littlejs/`.

## Contents

- `build.sh` — Create the `<repo>-littlejs` sbx sandbox (bare `node:20`, mounts the git root)
- `run_tests` — Dual-mode test/lint harness (`local` host in-place / `remote` fresh clone)
- `README.md` — This file

## Quick Start

1. Ensure `package.json` exists with vitest + eslint as devDeps and
   `test`/`lint` scripts.
2. Store Codex auth before building if using the default Codex setup:
   ```bash
   sbx secret set -g openai --oauth
   ```
   If OAuth is unavailable, store an API key as the fallback:
   ```bash
   echo "$OPENAI_API_KEY" | sbx secret set -g openai
   ```
3. Run `./build.sh` to create the `<repo>-littlejs` sandbox.
4. Run `ralph init` and pick this environment + an agent recipe (below).

## What this recipe contributes

`ralph init` appends this recipe's `env.conf` to `.ralph.conf` and copies
`build.sh` / `run_tests` into the project. `env.conf` sets only the harness:

```bash
TEST_CMD="LITTLEJS_TEST_SOURCE=remote ./run_tests test"
LINT_CMD="LITTLEJS_TEST_SOURCE=remote ./run_tests lint"
```

`LITTLEJS_` is the env-var prefix; rename it per-port if adapting the recipe for
another engine. `TEST_CMD`/`LINT_CMD` are **prompt text** ralph interpolates
into the agent's prompt — ralph never executes them; the agent does.

The `AGENT_*` / `MODEL_CLASS` lines come from a separate **agent recipe**
(`recipes/agents/`) chosen in the same `ralph init` run — e.g. `codex-docker`:

```bash
AGENT_CLI="codex"
AGENT_CMD="sbx run codex --"
AGENT_ARGS=""
MODEL_CLASS="low"
# MODEL="gpt-5.4-mini"
```

Configs use Agent CLI vocabulary. Legacy `CLAUDE_CMD` is not emitted by any
recipe; existing Claude-only configs are compatibility-mode examples.

## Test model (B) — push before green

`run_tests` is dual-mode via `LITTLEJS_TEST_SOURCE`:

- `local` — runs vitest/eslint on the host workspace in place; picks up
  uncommitted WIP. Fast human iteration.
- `remote` (default) — fresh `git clone` of the GitHub origin into `/tmp` inside
  the sandbox, then `npm ci` there. Builds clean linux deps and never shares the
  bind-mounted darwin `node_modules` into the linux container.

**Remote mode tests `origin/<branch>`, so the agent must commit AND push before
tests reflect its changes** (ADR-0022, locomotion: "WIP must be pushed to be
testable"). Surface this contract to the low-cost agent in the PRD/issue text,
since `env.conf` only carries `TEST_CMD`/`LINT_CMD`.

## Assumptions

- `package.json` with vitest + eslint and `test`/`lint` scripts
- `sbx` CLI installed and configured; `docker` daemon running
- Docker's Codex sandbox template is available for the default Codex adapter;
  the recipe layers Node.js 20 project tooling on top

## References

- LittleJS: https://github.com/KilledByAPixel/LittleJS
- Vitest: https://vitest.dev
- ESLint: https://eslint.org
- dragonruby sibling + ADR-0022: `adamico/locomotion`

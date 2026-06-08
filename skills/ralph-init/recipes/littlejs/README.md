# LittleJS Recipe

Bundled recipe for the ralph-init skill: sandbox + dual-mode test harness for
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
3. Run `./build.sh` to create the `<repo>-littlejs` sandbox. Set `AGENT_CLI=claude` or `AGENT_CLI=pi` first only when intentionally using a non-Codex adapter.
4. The skill generates a `.ralph.conf` (below).

## Configuration

The skill generates a `.ralph.conf` for the port with:

```bash
AGENT_CLI="codex"
AGENT_CMD="sbx run <repo>-littlejs -- codex"
AGENT_ARGS=""
MODEL_CLASS="low"
# MODEL="gpt-5.4"
TEST_CMD="<ENGINE>_TEST_SOURCE=remote <abs-path>/run_tests test"
LINT_CMD="<ENGINE>_TEST_SOURCE=remote <abs-path>/run_tests lint"
```

`<ENGINE>` is the port prefix (e.g. `LITTLEJS_` / `OBSI_`). `TEST_CMD`/`LINT_CMD`
are **prompt text** ralph interpolates into the agent's prompt — ralph never
executes them; the agent does. Use an absolute path because the agent's cwd in
the sandbox is not the mount.

New generated configs use Agent CLI vocabulary (`AGENT_CLI`, `AGENT_CMD`,
`AGENT_ARGS`, `MODEL_CLASS`, optional `MODEL`). Legacy `CLAUDE_CMD` is not
emitted by this recipe; existing Claude-only configs should be treated as
compatibility-mode examples.

## Test model (B) — push before green

`run_tests` is dual-mode via `<ENGINE>_TEST_SOURCE`:

- `local` — runs vitest/eslint on the host workspace in place; picks up
  uncommitted WIP. Fast human iteration.
- `remote` (default) — fresh `git clone` of the GitHub origin into `/tmp` inside
  the sandbox, then `npm ci` there. Builds clean linux deps and never shares the
  bind-mounted darwin `node_modules` into the linux container.

**Remote mode tests `origin/<branch>`, so the agent must commit AND push before
tests reflect its changes** (ADR-0022, locomotion: "WIP must be pushed to be
testable"). The generated `.ralph.conf` header states this contract so the
low-cost agent reads it.

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

# DragonRuby Recipe

Environment recipe for native `ralph init` (ADR-0013): sandbox template build + dual-mode test harness for DragonRuby ports.

## Contents

- `build.sh` — Build the `<repo>-dragonruby` sandbox template (ADR-0016)
- `dr-update-sandbox` — Sandbox-internal engine provisioner (part of ADR-0022)
- `run_tests` — Dual-mode test harness: local (host macOS) or remote (sandbox linux-arm64)
- `PATH-REWRITE-CHECKLIST.md` — Paths to customize when importing into a port
- `ADR-CONTEXT.md` — Design context (ADR-0016, ADR-0022)
- `README.md` — This file

## Quick Start

For a new DragonRuby port:

1. Copy all three scripts to the port's `.sbx/` directory (except `run_tests`, which goes to port root)
2. Customize paths per `PATH-REWRITE-CHECKLIST.md`
3. Run `shellcheck .sbx/build.sh .sbx/dr-update-sandbox ./run_tests`
4. For the default Codex setup, store OAuth credentials before building:
   ```bash
   sbx secret set -g openai --oauth
   ```
   API key fallback:
   ```bash
   echo "$OPENAI_API_KEY" | sbx secret set -g openai
   ```
5. Run `DR_LINUX_ARM64_SRC=~/Downloads/dragonruby-linux-arm64 .sbx/build.sh`.
   Set `AGENT_CLI=claude` only when intentionally using the legacy Claude-oriented import.
6. Test: `DR_TEST_SOURCE=local ./run_tests` (or `DR_TEST_SOURCE=remote ./run_tests` in CI)

## Generated ralph config shape

```bash
AGENT_CLI="codex"                     # claude | codex | pi
AGENT_CMD="sbx run <repo>-dragonruby -- codex"
AGENT_ARGS=""
MODEL_CLASS="low"
# MODEL="gpt-5.4-mini"
TEST_CMD="DR_TEST_SOURCE=remote ./run_tests"
LINT_CMD="bundle exec rubocop"
```

New generated configs use Agent CLI vocabulary. `CLAUDE_CMD` is legacy
compatibility only and should not be emitted by this recipe.

## Assumptions

- `.ruby-version` and `Gemfile` exist in port root
- `dragonruby-macos/` engine is available for local tests
- `sbx` CLI is installed and configured
- Docker's Codex sandbox template is available for the default Codex adapter;
  the recipe layers CRuby/Gemfile tooling on top
- `DR_LINUX_ARM64_SRC` env var points to unzipped linux-arm64 DragonRuby engine (for `build.sh`)

## References

- ADR-0016: SBX template build pattern
- ADR-0022: Remote fresh-clone test harness
- Source: github.com/adamico/locomotion

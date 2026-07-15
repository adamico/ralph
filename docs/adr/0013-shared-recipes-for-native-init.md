---
status: accepted
---

# Shared Recipes for Native Init

We decided to decouple configuration recipes from the `ralph` repository by using a shared installation directory (`~/.ralph/recipes/`). This directory contains two types of recipes:
1. `environments/` (e.g. `dragonruby`, `littlejs`): Provides test and lint harnesses (`run_tests`, `.sbx/build.sh`) and configures `TEST_CMD` / `LINT_CMD`.
2. `agents/` (e.g. `rtk`, `codex`, `claude`): Configures `AGENT_CLI`, `AGENT_CMD`, and `MODEL_CLASS`.

The native `ralph init` command will combine one environment recipe and one agent recipe (via auto-detection and interactive menu) to generate `.ralph.conf` and copy necessary files. The `install.sh` script is responsible for copying default recipes from the repository to `~/.ralph/recipes/`.

## Consequences
- **Positive**: Clean separation of config generation from the core script. Users can easily extend configurations by dropping files into `~/.ralph/recipes/`.
- **Negative**: Adds external filesystem dependency to `ralph init`. If `~/.ralph/recipes/` is missing or corrupt, initialization falls back to manual entry.

---
name: ralph-init
description: Scaffold a .ralph.conf for the current repo. Detects primary language (or, in a monorepo, multiple game-engine ports under build/<console>/), suggests TEST_CMD, LINT_CMD, BACKEND, MODEL, and CLAUDE_CMD. Optionally guides Docker/sbx sandbox setup so AFK runs execute in an isolated container (host machine is NOT used for tests/lint — the container is). Use when user says "ralph init", "set up ralph", "create .ralph.conf", or wants to configure ralph for a new project (single-engine or multi-engine monorepo).
---

# Bundled Recipes

This file documents the bundled resources available within the ralph-init skill.

## recipes/dragonruby/

Complete sandbox template build + dual-mode test harness for DragonRuby game-engine ports.

### Contents

- **build.sh** — Build the `<repo>-dragonruby` sandbox template (ADR-0016)
  - Creates a named `sbx` sandbox, provisions CRuby dependencies, bundles gems
  - Bakes the linux-arm64 DragonRuby binary into the template snapshot
  - Installs sandbox-specific `dr-update` provisioner script
  - Snapshots as reusable template for fast, reproducible test runs

- **dr-update-sandbox** — Sandbox-internal engine provisioner (ADR-0022)
  - Copies pre-cached linux-arm64 engine from `/opt/dragonruby-linux-arm64`
  - Handles mygame sync between host and sandbox
  - Supports `--os` and `--mygame` options for flexible provisioning

- **run_tests** — Dual-mode test harness (ADR-0022)
  - **Local mode** (`DR_TEST_SOURCE=local`): runs on host macOS engine (fast iteration)
  - **Remote mode** (`DR_TEST_SOURCE=remote`): fresh clone + sandbox linux-arm64 engine (CI/CD)
  - Auto-detects mode, handles clone/update, delegates engine provisioning to `dr-update`

- **PATH-REWRITE-CHECKLIST.md** — Path rewrites needed when importing into a port
  - Documents which paths are absolute vs. relative
  - Maps sandbox variables and defaults
  - Guides customization for new ports

- **ADR-CONTEXT.md** — Design context for both ADRs
  - ADR-0016 (template build pattern) rationale and implementation notes
  - ADR-0022 (fresh-clone harness) dual-mode design
  - Integration notes for new ports

- **README.md** — Quick reference for the recipe

### Usage in ralph-init (guided import, #24)

The `ralph-init` skill will eventually use this recipe to guide users through:

1. Clone `adamico/locomotion` (source of record)
2. Copy the three scripts into port's `.sbx/` directory
3. Apply path rewrites per PATH-REWRITE-CHECKLIST.md
4. Show each file for confirmation
5. Generate `.ralph.conf` with appropriate `CLAUDE_CMD`, `TEST_CMD`, `LINT_CMD`

### Status

✓ Recipe scripts (shellcheck-clean)
✓ Path-rewrite checklist
✓ ADR context documentation
⏳ Guided import integration (#24)
⏳ root config + monorepo orchestrator (#25)

### References

- Source: github.com/adamico/locomotion
- ADR-0016: SBX template build pattern
- ADR-0022: Remote fresh-clone test harness
- Related issues: #19, #20, #21, #22, #23, #24, #25

# DragonRuby Recipe

Bundled recipe for the ralph-init skill: sandbox template build + dual-mode test harness for DragonRuby ports.

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
4. Run `DR_LINUX_ARM64_SRC=~/Downloads/dragonruby-linux-arm64 .sbx/build.sh`
5. Test: `DR_TEST_SOURCE=local ./run_tests` (or `DR_TEST_SOURCE=remote ./run_tests` in CI)

## Assumptions

- `.ruby-version` and `Gemfile` exist in port root
- `dragonruby-macos/` engine is available for local tests
- `sbx` CLI is installed and configured
- `DR_LINUX_ARM64_SRC` env var points to unzipped linux-arm64 DragonRuby engine (for `build.sh`)

## References

- ADR-0016: SBX template build pattern
- ADR-0022: Remote fresh-clone test harness
- Source: github.com/adamico/locomotion

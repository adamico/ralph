---
status: accepted
---

# Mixed Agent CLIs and Native Init

## Context and Problem Statement
Tokens are expensive. Users need a workflow to juggle multiple agent CLI applications (e.g., full `claude` for complex logic vs token-optimized wrappers like `rtk` for repetitive operations). ADR-0011 explicitly rejected "Mixed Agent CLIs within one engagement" to keep baselines and logging simple. Furthermore, `.ralph.conf` generation was previously handled by the `/ralph-init` agent skill, which was error-prone and could not easily add CLIs to an existing configuration.

## Considered Options
1. **JSON/YAML Configuration**: Switch `.ralph.conf` to structured data to support multiple CLIs. Rejected because it breaks bash script sourcing, preventing arbitrary `export` commands, and introduces `jq` dependencies.
2. **Continue using `/ralph-init` skill**: Rejected because prompting an agent to modify an existing bash configuration interactively often fails or results in hallucinated syntax.

## Decision Outcome
We reverse the decision in ADR-0011 and allow mixing Agent CLIs within the same engagement.
1. `bin/ralph` supports `--cli CLI_NAME` at runtime (e.g., `ralph run 1 --cli rtk`).
2. We retain `.ralph.conf` as a bash script and use prefixed variables (`AGENT_CMD_${CLI_NAME}`, `AGENT_ARGS_${CLI_NAME}`) to define multiple CLIs, along with a `DEFAULT_AGENT_CLI`.
3. We introduce a native `ralph init` subcommand that interactively configures `.ralph.conf` with multiple CLIs and selects the default, bypassing the need for the AI skill.

## Consequences
- **Positive:** Developers can seamlessly switch agents per-iteration for token economy without manual configuration editing.
- **Positive:** Interactive CLI selection directly within `ralph init` ensures correctly-formatted configuration files.
- **Negative:** Recovery runbooks and baseline logs do not explicitly record *which* CLI was used for an interrupted iteration. A `ralph recover` will default to the primary CLI unless explicitly overridden, which is acceptable since the state of the codebase is the true source of truth.

---
status: accepted
---

# CLI-agnostic Agent CLI adapters

ralph no longer treats Claude Code as synonymous with the coding agent it invokes. A run uses exactly one configured **Agent CLI** per engagement: `AGENT_CLI` selects the adapter (`claude`, `codex`, or `pi`) and `AGENT_CMD` supplies the executable or wrapper, while legacy `CLAUDE_CMD` maps to the Claude adapter for compatibility. Each adapter owns its non-interactive invocation flags, JSONL progress parsing, and final-message extraction; sandboxing remains ralph-level via `sbx`, with the Docker Codex sandbox template used as a base for Codex recipes and OAuth supported via `sbx secret set -g openai --oauth`. ralph resolves `MODEL_CLASS=low` to known defaults for provider-native adapters (`claude` -> `sonnet`, `codex` -> `gpt-5.4`); Pi relies on external providers, so its model should be configured explicitly rather than inferred by ralph.

## Considered Options

- **Arbitrary command only.** Rejected because Claude and Codex expose different non-interactive flags, JSONL event schemas, and final-message mechanisms.
- **Provider-internal sandboxing.** Rejected as the default because ralph already wraps the whole Agent CLI invocation in `sbx`; provider sandbox flags can still be passed explicitly when useful.
- **Mixed Agent CLIs within one engagement.** Rejected because baselines, logs, recovery, and failure interpretation should have one stable executor identity per `.ralph.conf`.

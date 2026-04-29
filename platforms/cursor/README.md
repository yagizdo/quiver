# Quiver on Cursor

Quiver runs on Cursor IDE 2.5+ via a thin overlay. The canonical commands, agents, skills, and hooks under `commands/`, `agents/`, `skills/`, and `hooks/` are reused unchanged. Cursor-specific adapter content lives in this directory.

## Quick start

```bash
ln -s "$HOME/Projects/quiver-plugin" "$HOME/.cursor/plugins/local/quiver"
```

Then in Cursor: Cmd+Shift+P -> Reload Window. See [`install.md`](install.md) for full steps and verification.

## Install

Local symlink is the recommended install method. See [`install.md`](install.md) for prerequisites, verification, and troubleshooting.

## Supported commands and agents

The six core Quiver commands are supported on Cursor 2.5+ via the IDE:

- `/handover` -- session summary, including auto-save via the `preCompact` hook
- `/review` -- multi-agent review (with polyfilled prompts)
- `/plan` -- structured implementation plan with research agents
- `/work` -- execute a plan task-by-task
- `/commit` -- generate Conventional Commits message
- `/brainstorm` -- explore and validate a spec

All ten agents (`waste-detector`, `security-audit`, `architecture-strategist`, `developer-experience-auditor`, `logic-reviewer`, `test-reviewer`, `stress-tester`, `codex-code-reviewer`, `best-practices-researcher`, `project-context-analyst`) are registered in `.cursor-plugin/plugin.json` and dispatched via the Cursor `Task` tool.

Phase 2 (not yet supported on Cursor): `/load-handover`, `/delete-last-handover`, `/delete-all-handovers`, `/create-pr`, `/create-agent`, `/create-agents-md`, `/repair-skill`. These commands work in principle but are not part of the smoke-test surface for the initial overlay; expect them to land in a follow-up.

## Tool-name differences

Cursor uses different names for several tools (e.g., `Bash` -> `Shell`, `Edit` folded into `Write`, `Glob` unsupported). The full mapping table is in [`tool-map.md`](tool-map.md). The `quiver-shell-blocks.mdc` rule file applies these substitutions automatically when the Cursor agent loads a Quiver command body.

## Polyfills in effect

- `AskUserQuestion` -- Cursor has no public action-button question API as of 2026. Polyfilled as a numbered text prompt. See [`polyfills/ask-user.md`](polyfills/ask-user.md).

For the per-primitive Map/Polyfill/Skip classification, see [`primitives.md`](primitives.md).

## Known limitations

- The `cursor-agent` CLI does not load plugin skills (IDE-only). Use Cursor IDE for skill-using workflows.
- `WebFetch` and `WebSearch` are unsupported. Use the context7 MCP for documentation lookups.
- `Glob` requires a `find`/`fd` substitute via `Shell`. The `quiver-shell-blocks.mdc` rule file handles this automatically.
- First-install hook field-name verification: Cursor's `preCompact` event may use a different JSON field name than Claude Code. See [`install.md`](install.md) for the one-time probe.

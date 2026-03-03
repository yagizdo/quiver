# Quiver

Session handover plugin for Claude Code. Saves and restores conversation context across sessions.
Dependencies: `bash`, `claude` CLI.

## Architecture

- **`.claude-plugin/`** — Plugin manifest (`plugin.json`). Defines name, version, hook and command registration.
- **`commands/`** — Markdown slash commands (currently 5). Each file has a YAML `description` and is a self-contained prompt.
- **`hooks/`** — `hooks.json` registers event hooks; `scripts/` holds their implementations. Currently one hook: PreCompact (fires before context compaction).
- **Storage** — Handover files are written to `<project>/.claude/handovers/`.

## System Behavior

- **Commands** — Markdown files executed by Claude Code. Shell blocks (`` !`…` ``) run inline and inject output into the prompt. Commands cannot call hook scripts directly; they duplicate save/prune logic as Claude instructions.
- **Hooks** — Bash scripts invoked by Claude Code on lifecycle events. The PreCompact hook reads `transcript_path` from stdin JSON (via `sed`), pipes the transcript to `claude -p` for summarization, and writes the result to the handovers directory.
- **SYNC contract** — The 8 handover section headings are defined in two places that must stay identical: `commands/handover.md:15` and `hooks/scripts/pre-compact-handover.sh:25`. Both files contain a `SYNC:` comment pointing to the other. If you change headings, update both and verify line numbers in the comments.

## Development Standards

### Adding a Command

1. Create `commands/<name>.md` with a YAML front-matter `description` field.
2. Use `` !`…` `` blocks for any runtime data the prompt needs.
3. Do not reference `CLAUDE_PLUGIN_ROOT` — it is unavailable in commands.

### Adding or Modifying a Hook

1. Register the event in `hooks/hooks.json` with `"type": "command"` (the only supported hook type).
2. Place the script in `hooks/scripts/`. Use `$CLAUDE_PROJECT_DIR` (falls back to `pwd`) for the project root.
3. `$CLAUDE_PLUGIN_ROOT` is available in `hooks.json` and hook scripts.

### Invariants

- **Retention policy** — Exactly the 3 most recent `.md` files in `.claude/handovers/` are kept. Both the command and hook implement pruning independently.
- **Timestamp format** — Filenames use `date '+%Y-%m-%d_%H-%M-%S'`. This format is lexicographically sortable.

## Testing

- **Commands** — Run the slash command in a Claude Code session and verify output.
- **Hook** — Pipe test JSON to the script:
  ```bash
  echo '{"transcript_path":"/path/to/transcript.json"}' | bash hooks/scripts/pre-compact-handover.sh
  ```
- **Syntax check** — `bash -n hooks/scripts/pre-compact-handover.sh`
- **All commands** — Run each `/quiver:*` slash command in a Claude Code session and verify expected output/side-effects.

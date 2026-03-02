# Quiver — Session Handover Plugin for Claude Code

Automatically save and restore session context across Claude Code conversations. Never lose track of where you left off.

## Installation

```bash
claude plugin install /path/to/quiver-plugin
```

Or for development/testing:

```bash
claude --plugin-dir /path/to/quiver-plugin
```

### Cleanup Old Installation

If you previously used the skills-based handover system, remove the old hooks from your `~/.claude/settings.local.json` (the PreCompact hook entry) to prevent double-execution. Optionally remove the old skills from `~/.claude/skills/`.

## Commands

| Command | Description |
|---------|-------------|
| `/quiver:handover` | Creates and saves a structured handover summary |
| `/quiver:load-handover` | Loads the most recent handover into context |
| `/quiver:delete-all-handovers` | Deletes all handover files |
| `/quiver:delete-last-handover` | Deletes the most recent handover file |
| `/quiver:status` | Shows plugin version, handover count, and hook status |

### Auto-Compact Protection

A PreCompact hook automatically generates a handover from the session transcript before Claude compacts the conversation. This ensures no context is lost even if you forget to run `/quiver:handover`.

## How It Works

- Handover files are stored in `.claude/handovers/` within your project directory
- Files are timestamped (`YYYY-MM-DD_HH-mm-ss.md`) and sorted chronologically
- Only the 3 most recent handovers are kept (older ones are pruned automatically)
- The `/quiver:handover` command gathers git status/diff and prompts Claude to write a structured 8-section summary

## Environment Variables

| Variable | Available In | Notes |
|----------|-------------|-------|
| `CLAUDE_PLUGIN_ROOT` | `hooks.json`, hook scripts | Path to the plugin root directory. **Not** available in command `.md` files |
| `CLAUDE_PROJECT_DIR` | Hook scripts (via `$CLAUDE_PROJECT_DIR`) | Path to the current project. Falls back to `pwd` |

## Required Setup

> **Warning:** Handover files contain full session context including code snippets,
> decisions, and work-in-progress details. You **must** add the handover directory
> to `.gitignore` to avoid committing sensitive content to your repository.

Add to your project's `.gitignore`:

```
.claude/handovers/
```

## Recommended: Auto-load Handovers

For agent sessions (subagents, CI) to benefit from context continuity,
add this to your project's `CLAUDE.md`:

```
At session start, run /quiver:load-handover to restore context from the previous session.
```

## Uninstall

```bash
claude plugin uninstall quiver
```

Note: `.claude/handovers/` data persists after plugin removal. Delete it manually if no longer needed.

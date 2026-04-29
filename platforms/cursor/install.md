# Installing Quiver on Cursor

## Prerequisites

- Cursor IDE 2.5 or later (plugin system, Feb 2026)
- The Quiver repo cloned locally to a stable path (e.g., `~/Projects/quiver-plugin`)

## Install (local symlink, recommended)

```bash
# From any directory:
ln -s "$HOME/Projects/quiver-plugin" "$HOME/.cursor/plugins/local/quiver"
```

Then in Cursor: Cmd+Shift+P -> Reload Window. Cursor will discover `.cursor-plugin/plugin.json` at the symlink target and register the plugin.

## Verify

Open the Cursor settings file and confirm `quiver` appears under `installed_plugins.json` and is listed in `enabledPlugins`. Then in any Cursor agent prompt, type `/handover` -- if Quiver loaded correctly, the command appears in the slash-command picker.

## One-time hook field-name verification

Cursor's `preCompact` hook passes context as JSON on stdin. Quiver's hook script (`hooks/scripts/pre-compact-handover.sh:8-12`) reads `transcript_path` via `sed`. If Cursor uses a different field name, the hook will silently exit (per the script's exit-on-failure design). To verify on first install:

1. Open a Cursor agent session in a project with Quiver installed.
2. Trigger context compaction (Cursor settings -> Reload Window often forces compaction).
3. Check `.claude/handovers/` -- a new timestamped `.md` file should appear within ~150 seconds.
4. If no file appears, run a probe hook: edit `.cursor/hooks.json` to log the raw stdin to a file, trigger compaction, and inspect the log to see the exact field names Cursor sends.

## Optional: marketplace publish

Out of scope for this initial overlay. Future work: submit to `github.com/cursor/plugins` per the official spec repo.

## Troubleshooting

- Plugin not discovered: confirm the symlink resolves (`ls -la ~/.cursor/plugins/local/quiver`). Restart Cursor fully.
- Skills missing on cursor-agent CLI: known limitation. The CLI does not load plugin skills as of 2026. Use Cursor IDE for skill-using workflows.
- `Glob` errors in commands: confirm `quiver-shell-blocks.mdc` rule is loading (Cursor settings -> Rules should show it as active). The rule instructs the agent to substitute `find`/`fd`.

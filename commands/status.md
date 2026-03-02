---
description: Show Quiver plugin status — version, handover count, latest handover, and hook health.
---

# Quiver Status

## Plugin Info
- **Name:** quiver
- **Version:** !`jq -r '.name + " v" + .version' .claude-plugin/plugin.json 2>/dev/null || echo "unknown"`

## Handovers
- **Directory:** `.claude/handovers/`
- **Count:** !`ls -1 .claude/handovers/*.md 2>/dev/null | wc -l | tr -d ' '` file(s)
- **Latest:** !`ls -1t .claude/handovers/*.md 2>/dev/null | head -1 || echo "none"`

## Available Commands
| Command | File |
|---------|------|
| `/quiver:handover` | `commands/handover.md` |
| `/quiver:load-handover` | `commands/load-handover.md` |
| `/quiver:delete-all-handovers` | `commands/delete-all-handovers.md` |
| `/quiver:delete-last-handover` | `commands/delete-last-handover.md` |
| `/quiver:status` | `commands/status.md` |

## Hook Status
- **PreCompact hook:** !`if jq -e '.hooks.PreCompact' hooks/hooks.json &>/dev/null; then echo "registered"; else echo "NOT registered"; fi`
- **Hook script:** !`if [ -x hooks/scripts/pre-compact-handover.sh ]; then echo "executable"; elif [ -f hooks/scripts/pre-compact-handover.sh ]; then echo "exists but NOT executable"; else echo "MISSING"; fi`
- **jq available:** !`command -v jq &>/dev/null && echo "yes ($(jq --version 2>&1))" || echo "NO — hook will skip handover generation"`
- **claude CLI available:** !`command -v claude &>/dev/null && echo "yes" || echo "NO — hook will fail"`

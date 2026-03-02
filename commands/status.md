---
description: Show Quiver plugin status — version, handover count, latest handover, and hook health.
---

# Quiver Status

## Plugin Info
- **Name:** quiver
- **Version:** !`name=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .claude-plugin/plugin.json); version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .claude-plugin/plugin.json); echo "${name:-quiver} v${version:-?}"`

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
- **PreCompact hook:** !`if grep -q '"PreCompact"' hooks/hooks.json 2>/dev/null; then echo "registered"; else echo "NOT registered"; fi`
- **Hook script:** !`if [ -x hooks/scripts/pre-compact-handover.sh ]; then echo "executable"; elif [ -f hooks/scripts/pre-compact-handover.sh ]; then echo "exists but NOT executable"; else echo "MISSING"; fi`
- **claude CLI available:** !`command -v claude &>/dev/null && echo "yes" || echo "NO — hook will fail"`

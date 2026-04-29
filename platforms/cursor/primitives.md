# Cursor Primitive Compatibility

Each Quiver primitive is classified as Map (Cursor has a native equivalent), Polyfill (degraded-but-functional substitute), or Skip (no equivalent; dependent feature is unavailable).

| Primitive | Class | Cursor target | Affected Quiver commands |
|-----------|-------|---------------|--------------------------|
| Bash / Shell | Map | Shell tool | all six core |
| Read | Map | Read tool | all six core |
| Write | Map | Write tool | plan, work, commit, brainstorm |
| Edit | Map | Write tool (folded) | plan, work, commit |
| Grep | Map | Grep tool | review, work, plan |
| Glob | Polyfill | `find`/`fd` via Shell | review, work, plan |
| Skill | Map | native SKILL.md | review, brainstorm |
| Sub-agent dispatch | Map | Task tool | review, plan |
| MCP | Map | mcpServers in plugin.json | review (context7) |
| preCompact hook | Map | Cursor 1.7+ hooks | handover (auto-save) |
| AskUserQuestion | Polyfill | numbered text prompt (see `polyfills/ask-user.md`) | review, plan, work, commit, brainstorm |
| TaskCreate / TaskUpdate / TaskList | Map | Cursor todo tracking | plan, work |
| WebFetch | Skip | -- | (none in core six) |
| WebSearch | Skip | -- | (none in core six) |

## Verification expected during install

When installing on Cursor, verify the `transcript_path` field is present in the JSON Cursor passes to the preCompact hook. If Cursor uses a different field name, the handover script needs a 1-line shim. (See `install.md`.)

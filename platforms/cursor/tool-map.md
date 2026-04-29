# Quiver Tool Names on Cursor

When a Quiver command, agent, or skill references a Claude Code tool name, use the Cursor equivalent in the right column.

| Claude Code | Cursor | Notes |
|-------------|--------|-------|
| Bash | Shell | Identical semantics. |
| Read | Read | Identical. |
| Write | Write | Identical. |
| Edit | Write | Cursor folds Edit into Write. Pass the full new content. |
| Grep | Grep | Identical. |
| Glob | (use Shell) | Cursor does not expose Glob. Run `find` or `fd` via Shell. |
| Agent | Task | Cursor's sub-agent dispatch tool is named Task. |
| Skill | (native) | SKILL.md format loads automatically; no tool call needed. |
| AskUserQuestion | (polyfill) | See `polyfills/ask-user.md`. |
| WebFetch | (unsupported) | Use the context7 MCP for docs lookups. |
| WebSearch | (unsupported) | Out of scope on Cursor. |
| TaskCreate / TaskUpdate / TaskList | (Cursor todo) | Cursor exposes its own task tracking; the agent uses it naturally. |

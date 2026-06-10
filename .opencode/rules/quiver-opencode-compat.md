# Quiver OpenCode Compatibility

Quiver provides first-class OpenCode support via `.opencode/agents/`, `.opencode/skills/`,
`.opencode/commands/`, and `.opencode/plugins/quiver.ts`. All 19 agents, 19 skills, and
12 commands are available in OpenCode.

## Agents

All Quiver agents are available as subagents in OpenCode. Invoke them with `@agentname`:

`@waste-detector`, `@security-audit`, `@architecture-strategist`,
`@developer-experience-auditor`, `@logic-reviewer`, `@test-reviewer`, `@stress-tester`,
`@codex-code-reviewer`, `@report-checker`, `@senior-reviewer`,
`@best-practices-researcher`, `@project-context-analyst`, `@code-navigator`,
`@code-locator`, `@code-tracer`, `@log-analyzer`, `@regression-finder`,
`@environment-checker`, `@fix-reviewer`, `@plan-reviewer`

## Commands

Slash commands work identically to Claude Code. Available commands:

`/handover`, `/review`, `/plan`, `/commit`, `/brainstorm`, `/work`,
`/load-handover`, `/create-pr`, `/senior-review`, `/orchestrate-agents`,
`/delete-all-handovers`, `/delete-last-handover`

## Skills

Skills are loaded via the `skill` tool. OpenCode discovers them from `.opencode/skills/`.

## Differences from Claude Code

These Claude Code-specific primitives have no direct equivalent in OpenCode:

### 1. AskUserQuestion (interactive choice buttons)

OpenCode does not have the `AskUserQuestion` tool.

**Replacement:** Present choices as a numbered plain-text list and wait for the user
to type their selection number.

### 2. Agent tool (parallel subagent dispatch)

The `Agent` tool for spawning subagents is Claude Code-specific.

**Replacement:** Use `@agentname` mentions to invoke subagents. Multi-agent orchestration
(like `/review`) uses OpenCode's Task tool for sequential subagent dispatch instead of
parallel Claude Code subagents.

### 3. Session hooks (PreCompact, SessionStart)

PreCompact and SessionStart hooks do not fire in OpenCode.

**Replacement:** The Quiver OpenCode plugin hooks into `experimental.session.compacting`
to inject handover context. Trigger manual handover creation with `/handover` at natural
breakpoints or before ending a session.

### 4. Shell injection blocks

Inline shell blocks (`` !`command` ``) work identically in OpenCode. No adaptation needed.

### 5. Frontmatter fields (when-to-use, name)

`when-to-use:` and `name:` fields in skill files are Claude Code-specific.
OpenCode ignores them. No action needed.

### 6. Handover file paths

Handover files write to `.claude/handovers/` relative to the project root.
Unchanged in OpenCode since this is relative to the project root.

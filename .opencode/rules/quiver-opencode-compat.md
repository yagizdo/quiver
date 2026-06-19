# Quiver OpenCode Compatibility

Quiver provides first-class OpenCode support via `.opencode/agents/`, `.opencode/skills/`,
`.opencode/commands/`, and `.opencode/plugins/quiver.js`. All 20 agents, 20 skills, and
16 commands are available in OpenCode.

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
`/delete-all-handovers`, `/delete-last-handover`, `/hypothesis-debugging`,
`/create-agent`, `/create-agents-md`, `/repair-skill`

## Skills

Skills are loaded via the `skill` tool. OpenCode discovers them from `.opencode/skills/`.

The `using-quiver` meta-skill is loaded automatically by the plugin on every session
via `experimental.chat.messages.transform` (see section 5 below). It establishes the
"check for relevant skill before any response" rule.

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

### 5. Skill auto-activation (bootstrap injection)

In Claude Code, skills are loaded on-demand via the `Skill` tool. In OpenCode, the
Quiver plugin uses `experimental.chat.messages.transform` to inject the `using-quiver`
meta-skill into the first user message of every session. This means Quiver skills
auto-activate without explicit invocation -- the agent knows to check for relevant
skills before responding.

**No action required from the user** -- this happens transparently. The bootstrap
content is wrapped in `<EXTREMELY_IMPORTANT>` tags so the model treats it as a
high-priority directive. A guard checks for the `EXTREMELY_IMPORTANT` substring to
prevent double-injection when OpenCode reloads messages from DB each step.

Note: `experimental.chat.messages.transform` is an unstable API in OpenCode. If a
future OpenCode version breaks this hook, skills will still be discoverable via the
`skill` tool but won't auto-activate.

### 6. Skill directory auto-registration

The Quiver plugin uses the `config` hook to push the local `skills/` directory into
OpenCode's `config.skills.paths` array. No symlinks or manual setup needed -- the
plugin owns discovery. Users who previously needed the `setup-opencode.sh` symlink
overlay no longer need it when installing via the native `git+https` plugin spec.

### 7. Frontmatter fields (when-to-use, name)

`when-to-use:` and `name:` fields in skill files are Claude Code-specific.
OpenCode ignores them. No action needed.

### 8. Handover file paths

Handover files write to `.claude/handovers/` relative to the project root.
Unchanged in OpenCode since this is relative to the project root.

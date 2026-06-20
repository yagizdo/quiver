# Quiver for OpenCode

Complete guide for using [Quiver](https://github.com/yagizdo/quiver) with [OpenCode.ai](https://opencode.ai). Quiver is a development lifecycle plugin providing skills for brainstorming, planning, execution, debugging, code review, and session handover, plus specialized agents for review and debugging.

This directory is the OpenCode-specific overlay for Quiver. The plugin entry point is `.opencode/plugins/quiver.js`. Skills, agents, and commands are discoverable through OpenCode's native mechanisms.

## Installation

Add quiver to the `plugin` array in your `opencode.json` (global or project-level):

```json
{
  "plugin": ["quiver@git+https://github.com/yagizdo/quiver.git"]
}
```

Restart OpenCode. The plugin installs through OpenCode's plugin manager and
registers all skills automatically.

Verify by asking: "Tell me about your Quiver skills"

OpenCode uses its own plugin install. If you also use Claude Code, Codex, or
another harness, install Quiver separately for each one.

For a quick install walkthrough, see [INSTALL.md](INSTALL.md).

## Usage

### Finding Skills

Use OpenCode's native `skill` tool to list all available Quiver skills:

```
use skill tool to list skills
```

### Loading a Skill

```
use skill tool to load brainstorm
```

### Slash Commands

OpenCode 1.16.2+ does not list Quiver skills in its `/` autocomplete menu. The TUI filter in `footer.command.tsx` drops anything with `source: "skill"`, and Quiver skills register with that source, so the picker stays empty. The skills themselves still work, just not through the menu.

Two ways to invoke them:

**Slash prefix.** Type `/brainstorm <idea>`, `/hypothesis-debugging <bug>`, or any other `/skill-name` directly and submit. The `using-quiver` bootstrap teaches the model to match the prefix against each skill's `when-to-use:` frontmatter and load the skill via the `skill` tool. No autocomplete, but the skill runs.

**Plain language.** Describe what you want: "debug this login bug", "brainstorm a todo app", "review my changes". The bootstrap dispatches the matching skill the same way.

The full skill list lives in the `skill` tool. Run `use skill tool to list skills` to see all 16 user-facing Quiver skills.

#### Available skills

| Skill | Purpose |
|-------|---------|
| `brainstorm` | Turn a vague idea into a validated spec |
| `plan` | Research the codebase and produce an implementation plan |
| `work` | Execute a plan task-by-task |
| `review` | Dispatch review agents |
| `senior-review` | Standalone senior developer review |
| `hypothesis-debugging` | Systematic bug investigation |
| `commit` | Generate a Conventional Commits message |
| `create-pr` | Open a GitHub pull request |
| `handover` | Save session context |
| `load-handover` | Resume from the latest handover |
| `delete-last-handover` | Remove the most recent handover |
| `delete-all-handovers` | Reset session history |
| `create-agent` | Scaffold a new agent |
| `create-agents-md` | Generate an AGENTS.md |
| `repair-skill` | Fix a broken skill |
| `report-check` | Audit a review report |

### Agents

Quiver provides 20 specialist agents. Invoke them with `@agentname`:

- **Review:** `@architecture-strategist`, `@logic-reviewer`, `@waste-detector`, `@stress-tester`, `@security-audit`, `@test-reviewer`, `@developer-experience-auditor`, `@codex-code-reviewer`, `@report-checker`, `@senior-reviewer`
- **Research:** `@best-practices-researcher`, `@project-context-analyst`, `@code-navigator`, `@code-locator`
- **Debug:** `@code-tracer`, `@log-analyzer`, `@regression-finder`, `@environment-checker`, `@fix-reviewer`
- **Workflow:** `@plan-reviewer`

### Personal Skills

Create your own skills in `~/.config/opencode/skills/`:

```bash
mkdir -p ~/.config/opencode/skills/my-skill
```

Create `~/.config/opencode/skills/my-skill/SKILL.md`:

```markdown
---
name: my-skill
description: Use when [condition] - [what it does]
---

# My Skill

[Your skill content here]
```

### Project Skills

Create project-specific skills in `.opencode/skills/` within your project.

**Skill Priority:** Project skills > Personal skills > Quiver skills

## Updating

OpenCode installs Quiver through a git-backed package spec. Some OpenCode
and Bun versions pin that resolved git dependency in a lockfile or cache, so a
restart may not pick up the newest Quiver commit. If updates do not appear,
clear OpenCode's package cache or reinstall the plugin.

To pin a specific version, use a branch or tag:

```json
{
  "plugin": ["quiver@git+https://github.com/yagizdo/quiver.git#v1.13.0"]
}
```

## How It Works

The Quiver OpenCode plugin does four things:

1. **Registers the skills directory** via the `config` hook. The plugin pushes `skills/` (relative to itself) into `config.skills.paths`, so OpenCode discovers all Quiver skills without symlinks or manual config edits.

2. **Injects the `using-quiver` bootstrap** via the `experimental.chat.messages.transform` hook. On every new session, the first user message has the `using-quiver` meta-skill prepended, wrapped in `<EXTREMELY_IMPORTANT>` tags. This establishes the "check for relevant skill before any response" rule, so OpenCode agents invoke Quiver skills automatically.

3. **Preserves Quiver-specific context across compactions** via the `experimental.session.compacting` hook. When OpenCode compacts a session, the Quiver handover context (branch, task, in-progress files, decisions) is included in the compaction prompt.

4. **Logs session lifecycle events** via the `session.created` hook and `client.app.log()` for debugging.

### Tool Mapping

Skills speak in actions rather than naming any one runtime's tools. On OpenCode these resolve to:

- "Create a todo" / "mark complete in todo list" -> `todowrite`
- `Subagent (general-purpose):` -> `task` tool with `subagent_type: "general"` (or `"explore"` for codebase exploration, or a specific Quiver subagent)
- "Invoke a skill" -> OpenCode's native `skill` tool
- "Read a file" -> `read`
- "Create a file" / "edit a file" / "delete a file" -> `apply_patch`
- "Run a shell command" -> `bash`
- "Search file contents" / "find files by name" -> `grep`, `glob`
- "Fetch a URL" -> `webfetch`

## Differences from Claude Code

These Claude Code-specific primitives have no direct equivalent in OpenCode:

### 1. AskUserQuestion (interactive choice buttons)

OpenCode does not have the `AskUserQuestion` tool.

**Replacement:** Present choices as a numbered plain-text list and wait for the user to type their selection number.

### 2. Agent tool (parallel subagent dispatch)

The `Agent` tool for spawning subagents is Claude Code-specific.

**Replacement:** Use `@agentname` mentions to invoke subagents. Multi-agent orchestration (like `/review`) uses OpenCode's `task` tool for sequential subagent dispatch instead of parallel Claude Code subagents.

### 3. Session hooks (PreCompact, SessionStart)

PreCompact and SessionStart hooks do not fire in OpenCode.

**Replacement:** The Quiver OpenCode plugin hooks into `experimental.session.compacting` to inject handover context. Trigger manual handover creation with `/handover` at natural breakpoints or before ending a session.

### 4. Shell injection blocks

Inline shell blocks (`!`command``) work identically in OpenCode. No adaptation needed.

### 5. Frontmatter fields (when-to-use, name)

`when-to-use:` and `name:` fields in skill files are Claude Code-specific.
OpenCode ignores them. No action needed.

### 6. Handover file paths

Handover files write to `.claude/handovers/` relative to the project root.
Unchanged in OpenCode since this is relative to the project root.

## Troubleshooting

### Plugin not loading

1. Check OpenCode logs: `opencode run --print-logs "hello" 2>&1 | grep -i quiver`
2. Verify the plugin line in your `opencode.json` is correct
3. Make sure you're running a recent version of OpenCode

### Skills not found

1. Use OpenCode's `skill` tool to list available skills
2. Check that the plugin is loading (see above)
3. Each skill needs a `SKILL.md` file with valid YAML frontmatter

### Bootstrap not appearing

1. Check OpenCode version supports `experimental.chat.messages.transform` hook
2. Restart OpenCode after config changes
3. If a future OpenCode version removes this hook, skills will still be discoverable but won't auto-activate

### Windows install issues

Some Windows OpenCode builds have upstream installer issues with git-backed
plugin specs. See [INSTALL.md](INSTALL.md#windows-install-issues) for the
workaround.

## Getting Help

- Report issues: https://github.com/yagizdo/quiver/issues
- Main documentation: https://github.com/yagizdo/quiver
- OpenCode docs: https://opencode.ai/docs/

# Quiver

Session continuity, agent orchestration, and development workflows for Claude Code. Never lose context between sessions — carry your decisions, progress, and next steps forward automatically.

## Quick Start

```bash
/plugin marketplace add yagizdo/quiver
/plugin install quiver@yagizdo/quiver
```

Then try your first command:

```
/handover
```

## Installation

### Plugin Install (recommended)

```bash
/plugin install quiver@yagizdo/quiver
```

## Components

| Component | Count |
|-----------|-------|
| Commands | 9 |
| Hooks | 1 |
| Skills | 3 |
| Agents | 3 |

## Commands

### Session Handover

| Command | Description |
|---------|-------------|
| `/handover` | Build an 8-section handover note with freshness checks and quality gates |
| `/load-handover` | Load the most recent handover and highlight top priorities |

### Cleanup

| Command | Description |
|---------|-------------|
| `/delete-last-handover` | Show and delete the most recent handover file with confirmation |
| `/delete-all-handovers` | List all handover files, confirm, then delete everything |

### Code Review

| Command | Description |
|---------|-------------|
| `/review` | Multi-agent code review with synthesized findings |

**Diff source** (pick one):
```
/review                              # Review current branch (prompts for base)
/review --base main                  # Review against a specific base branch
/review <PR-URL>                     # Review a pull/merge request by URL
```

**Output flags** (combine with any diff source above):
```
--terminal                           # Print full report in terminal instead of saving
--output ./reports/                  # Save report to a custom path (one-time)
--set-output ./reports/              # Save report to a custom path and remember it as default
```

**Examples:**
```
/review <PR-URL> --terminal          # Review a PR and print in terminal
/review --base main --output ./tmp/   # Review against main, save to ./tmp/
/review --set-output ./reports/      # Set default save path for future reviews
```

### Git

| Command | Description |
|---------|-------------|
| `/commit` | Generate a Conventional Commits message from staged changes, commit, and optionally push |

### Agent Development

| Command | Description |
|---------|-------------|
| `/create-agent` | Scaffold a new agent interactively from a description or Q&A walkthrough |
| `/create-agents-md` | Analyze project context and generate an AGENTS.md checklist for AI agents |

### Maintenance

| Command | Description |
|---------|-------------|
| `/repair-skill` | Diagnose and fix a broken skill by analyzing structure and verifying API references |

## Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `pre-compact-handover` | PreCompact | Summarizes the conversation and saves a handover before Claude compacts context |

## Skills

### Agent Orchestration

| Skill | Description |
|-------|-------------|
| `orchestrate-agents` | Discover agents, plan an optimal team, and coordinate parallel or sequential execution |

### Agent Development

| Skill | Description |
|-------|-------------|
| `create-agent` | Agent authoring reference — frontmatter spec, category definitions, body structure, and quality gates |

### Maintenance

| Skill | Description |
|-------|-------------|
| `repair-skill` | Diagnose broken skills, verify API references against current docs, and apply targeted repairs |

## Agents

### Review

| Agent | Description |
|-------|-------------|
| `code-review` (`quiver:code-review`) | 5-phase PR review with severity ratings and file:line references |
| `security-audit` (`quiver:security-audit`) | Adversarial security auditor covering web, API, and mobile attack surfaces |

### Research

| Agent | Description |
|-------|-------------|
| `best-practices-researcher` (`quiver:best-practices-researcher`) | Researches and synthesizes current best practices for any technology or framework by dynamically detecting the project's tech stack via context7 MCP |

## How It Works

- **Session handovers** — structured summaries of your work: git state, decisions made, current progress, and planned next steps
- **Auto-save on compact** — PreCompact hook captures context automatically before Claude compacts the conversation
- **Retention policy** — keeps the 3 most recent handovers, prunes older ones automatically
- **Agent orchestration** — discover your local and plugin agents, assemble teams, and run subtasks in parallel
- **Agent scaffolding** — create new agents interactively with smart defaults and best practices

## External Dependencies

This plugin includes a [Context7](https://context7.com) MCP server for real-time library documentation lookups. It starts automatically when the plugin is enabled (configured in `plugin.json` under `mcpServers`). No authentication required.

**Tools provided:**
- `resolve-library-id` — Find library ID for a framework/package
- `get-library-docs` — Get documentation for a specific library

Supports 100+ frameworks including Rails, React, Next.js, Vue, Django, Laravel, and more. Library/framework names from your codebase are sent to the service only during review agent execution (e.g., best-practices checks), not at plugin load time.

## Uninstall

```
/uninstall quiver
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

# Quiver

Session continuity, agent orchestration, and development workflows for Claude Code. Never lose context between sessions — carry your decisions, progress, and next steps forward automatically.

## Components

| Component | Count |
|-----------|-------|
| Commands | 7 |
| Hooks | 1 |
| Skills | 2 |
| Agents | 1 |

## Commands

### Session Handover

| Command | Description |
|---------|-------------|
| `/quiver:handover` | Build an 8-section handover note (summary, decisions, dead ends, next steps, etc.) with freshness checks and quality gates |
| `/quiver:load-handover` | Load the most recent handover, highlight top priorities, and ask which next step to focus on |

### Cleanup

| Command | Description |
|---------|-------------|
| `/quiver:delete-last-handover` | Show and delete the most recent handover file with confirmation |
| `/quiver:delete-all-handovers` | List all handover files, confirm, then delete everything and verify |

### Git

| Command | Description |
|---------|-------------|
| `/quiver:commit` | Generate a Conventional Commits message from staged changes, review, commit, and optionally push with `--push` |

### Agent Development

| Command | Description |
|---------|-------------|
| `/quiver:create-agent` | Scaffold a new agent interactively — parse a description or walk through Q&A, then generate the file under `agents/<category>/` |
| `/quiver:agents-md` | Analyze project context (CI, linters, configs) and generate an AGENTS.md checklist with constraints, conventions, and gotchas |

## Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `pre-compact-handover` | PreCompact | Automatically summarizes the conversation transcript and saves a handover before Claude compacts context |

## Skills

### Agent Orchestration

| Skill | Description |
|-------|-------------|
| `orchestrate-agents` | Discover local and plugin agents, plan an optimal team, and coordinate parallel or sequential execution across 5 patterns (fan-out, progressive deepening, etc.) |

### Agent Development

| Skill | Description |
|-------|-------------|
| `create-agent` | Agent authoring reference — frontmatter spec, category definitions, body structure (persona, methodology, output format), quality gates, and anti-patterns |

## Agents

### Review

| Agent | Description |
|-------|-------------|
| `senior-pr-reviewer` | 5-phase PR review (best practices, performance, readability, extensibility, scope) with severity ratings and file:line references |

## How It Works

- **Session handovers** — structured summaries of your work: git state, decisions made, current progress, and planned next steps
- **Auto-save on compact** — PreCompact hook captures context automatically before Claude compacts the conversation
- **Retention policy** — keeps the 3 most recent handovers, prunes older ones automatically
- **Agent orchestration** — discover your local and plugin agents, assemble teams, and run subtasks in parallel
- **Agent scaffolding** — create new agents interactively with smart defaults and best practices

## Installation

```
/install yagizdo/quiver
```

## Quick Start

Save a handover before ending your session:

```
/quiver:handover
```

Restore context at the start of a new session:

```
/quiver:load-handover
```

That's it. Your decisions, progress, and next steps carry over.

## Setup

Add the handover directory to your project's `.gitignore`:

```
.claude/handovers/
```

## Uninstall

```
/uninstall quiver
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

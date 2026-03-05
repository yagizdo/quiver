# Quiver

Never lose context between Claude Code sessions. Quiver saves and restores your session context — decisions, progress, and next steps — so you can pick up exactly where you left off.

## Components

| Component | Count |
|-----------|-------|
| Commands | 7 |
| Hooks | 1 |
| Skills | 1 |
| Agents | 1 |

## Commands

### Session Handover

| Command | Description |
|---------|-------------|
| `/quiver:handover` | Create and save a structured handover summary |
| `/quiver:load-handover` | Load the most recent handover into context |

### Cleanup

| Command | Description |
|---------|-------------|
| `/quiver:delete-last-handover` | Delete the most recent handover file |
| `/quiver:delete-all-handovers` | Delete all handover files |

### Git

| Command | Description |
|---------|-------------|
| `/quiver:commit` | Generate a Conventional Commits message, commit, and optionally push |

### Agent Development

| Command | Description |
|---------|-------------|
| `/quiver:create-agent` | Scaffold a new Claude Code agent with smart defaults from a description or interactive Q&A |
| `/quiver:agents-md` | Generate or rewrite an AGENTS.md operational checklist for AI coding agents |

## Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `pre-compact-handover` | PreCompact | Auto-saves a handover before Claude compacts the conversation |

## Agents

| Agent | Category | Description |
|-------|----------|-------------|
| `senior-pr-reviewer` | Review | Analyzes diffs for best practices, performance, readability, and extensibility |

## How It Works

- **Session handovers** — structured summaries of your work: git state, decisions made, current progress, and planned next steps
- **Auto-save on compact** — PreCompact hook captures context automatically before Claude compacts the conversation
- **Retention policy** — keeps the 3 most recent handovers, prunes older ones automatically

## Installation

```
/plugin marketplace add yagizdo/quiver
```

```
/plugin install quiver@yagizdo-quiver
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
/plugin uninstall quiver
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

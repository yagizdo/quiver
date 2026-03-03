# Quiver

Never lose context between Claude Code sessions.

> Quiver is under active development. Commands and hooks are stable; skills and agents are coming soon.

## What is Quiver?

Quiver is a Claude Code plugin that saves and restores your session context — decisions, progress, and next steps — so you can pick up exactly where you left off. It works through slash commands and an event-driven hook that captures context before it's lost.

- **Session handovers** — structured summaries of your work: git state, decisions made, current progress, and planned next steps
- **Auto-save on compact** — PreCompact hook captures context automatically before Claude compacts the conversation
- **Retention policy** — keeps the 3 most recent handovers, prunes older ones automatically
- **Skills & Agents** — coming soon

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

## Commands

| Command | Description |
|---------|-------------|
| `/quiver:handover` | Creates and saves a structured handover summary |
| `/quiver:load-handover` | Loads the most recent handover into context |
| `/quiver:delete-all-handovers` | Deletes all handover files |
| `/quiver:delete-last-handover` | Deletes the most recent handover file |
| `/quiver:status` | Shows plugin version, handover count, and hook status |

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


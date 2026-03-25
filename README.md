# Quiver

[![Version](https://img.shields.io/badge/version-1.6.0-blue)](https://github.com/yagizdo/quiver/releases)

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

## Why Quiver?

- **Session handovers** -- never re-explain context when starting a new session
- **Auto-save on compact** -- context is captured automatically before Claude compacts
- **Multi-agent code review** -- security, architecture, and code quality analysis in parallel
- **Planning & execution** -- structured plans with parallel agent research, then systematic implementation
- **Agent scaffolding** -- create custom agents with smart defaults from a description

## Components

| Component | Count |
|-----------|-------|
| Commands | 11 |
| Hooks | 1 |
| Skills | 5 |
| Agents | 6 |

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
--comment-pr                         # Post the review as a PR comment (opt-in)
```

**Examples:**
```
/review <PR-URL> --terminal          # Review a PR and print in terminal
/review --base main --output ./tmp/   # Review against main, save to ./tmp/
/review --set-output ./reports/      # Set default save path for future reviews
/review <PR-URL> --comment-pr        # Review a PR and post the report as a comment
```

> When a PR URL is provided, you'll be prompted after the review to post it as a comment. Use `--comment-pr` to skip the prompt and post directly.

**Re-review detection:** If you run `/review` again on the same branch after fixing issues, it automatically detects the previous report and switches to re-review mode. It only flags new issues introduced since the last review -- no duplicate findings, no infinite review loops. If nothing functional changed, it approves immediately.

### Git

| Command | Description |
|---------|-------------|
| `/commit` | Generate a Conventional Commits message from staged changes, commit, and optionally push |

```
/commit                              # Commit with interactive prompt (commit, commit & push, edit, cancel)
/commit --push                       # Auto commit and push without prompting
```

### Agent Development

| Command | Description |
|---------|-------------|
| `/create-agent` | Scaffold a new agent interactively from a description or Q&A walkthrough |
| `/create-agents-md` | Analyze project context and generate an AGENTS.md checklist for AI agents |

### Planning & Execution

| Command | Description |
|---------|-------------|
| `/plan` | Create a structured implementation plan with parallel agent research before coding |
| `/work` | Execute a work plan or specification systematically with continuous testing and incremental commits |

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

### Planning & Execution

| Skill | Description |
|-------|-------------|
| `work` | Execute a work plan or specification systematically -- read the plan, set up a branch, implement tasks with continuous testing, commit incrementally, and ship a PR |

### Code Navigation

| Skill | Description |
|-------|-------------|
| `code-navigation` | LSP-first code navigation with grep fallback -- guides agents on when to use goToDefinition, findReferences, and documentSymbol vs grep-based search |

### Maintenance

| Skill | Description |
|-------|-------------|
| `repair-skill` | Diagnose broken skills, verify API references against current docs, and apply targeted repairs |

## Agents
<!-- agents-start -->

### Review
<!-- agents:review-start -->

| Agent | Description |
|-------|-------------|
| `waste-detector` (`quiver:waste-detector`) | Detects wasted effort in diffs: unnecessary files, dead code paths, redundancy with existing codebase utilities, over-engineered abstractions, and ceremony the framework already handles |
| `security-audit` (`quiver:security-audit`) | Adversarial security auditor covering web, API, and mobile (Flutter, Kotlin/Android, Swift/iOS) attack surfaces with prompt-vs-code awareness |
| `architecture-strategist` (`quiver:architecture-strategist`) | Evaluates structural integrity via context7-driven convention discovery, diff manifest-aware boundary analysis, and pattern compliance grounded in the project's actual codebase |
| `developer-experience-auditor` (`quiver:developer-experience-auditor`) | Evaluates code changes for developer experience quality across discoverability, error messages, debugging experience, and automation-readiness for both human developers and AI agents |

<!-- agents:review-end -->

### Research
<!-- agents:research-start -->

| Agent | Description |
|-------|-------------|
| `best-practices-researcher` (`quiver:best-practices-researcher`) | 5-phase research pipeline that dynamically detects the project's tech stack, validates against current docs via context7 MCP, and flags deprecations before they become bugs |
| `project-context-analyst` (`quiver:project-context-analyst`) | Cross-references the diff against project memory, git history, and past decisions to surface institutional knowledge, churn patterns, and recurring issues |

<!-- agents:research-end -->
<!-- agents-end -->

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
- `query-docs` — Get documentation for a specific library

Supports 100+ frameworks including Rails, React, Next.js, Vue, Django, Laravel, and more. Library/framework names from your codebase are sent to the service only during review agent execution (e.g., best-practices checks), not at plugin load time.

## Uninstall

```
/uninstall quiver
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

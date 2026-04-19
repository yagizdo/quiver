# Quiver

[![Version](https://img.shields.io/badge/version-1.8.1-blue)](https://github.com/yagizdo/quiver/releases)

Quiver is a Claude Code plugin for multi-agent code review, end-to-end workflow orchestration, and session continuity -- carry your plans, decisions, and review findings from idea to PR without re-explaining context between sessions.

## What is Quiver?

Quiver coordinates multi-step development workflows and session continuity for Claude Code. You use it to brainstorm feature ideas, produce research-backed implementation plans, execute those plans with continuous testing and incremental commits, and run a suite of specialized agents that review the resulting code for logic bugs, security gaps, architectural drift, and weak test coverage before merging. When work spans sessions, Quiver saves a handover with decisions, blockers, and next steps so you resume exactly where you left off -- no re-investigation, no lost context.

## Typical workflow

A normal feature cycle in Quiver chains the commands below. Each command is self-contained, so skip or substitute steps as needed.

1. `/brainstorm` -- turn a vague idea into a validated spec by walking through clarifying questions and trade-off analysis on 2-3 design approaches.
2. `/plan` -- research the codebase in parallel, then break the chosen approach into verifiable step-by-step tasks with exact file paths.
3. `/work` -- execute the plan task-by-task with continuous testing, branch setup, and incremental commits.
4. `/commit` -- generate a Conventional Commits message from staged changes and commit (optionally pushing).
5. `/create-pr` -- open a GitHub pull request with an auto-generated title and description from the branch diff.
6. `/review` -- dispatch specialized review agents in parallel (logic, architecture, security, tests, devex, waste) and synthesize findings into one report.
7. `/handover` -- save an 8-section summary of the session so the next session resumes with full context.

## Quick Start

```bash
/plugin marketplace add yagizdo/quiver
/plugin install quiver@yagizdo/quiver
```

Then try your first command:

```
/brainstorm
```

## Components

| Component | Count |
|-----------|-------|
| Commands | 13 |
| Hooks | 1 |
| Skills | 6 |
| Agents | 9 |

## Commands

### Session Handover

| Command | Description | When to use |
|---------|-------------|-------------|
| `/handover` | Builds an 8-section handover note with freshness checks and quality gates | At the end of a work session to preserve context for resuming later |
| `/load-handover` | Loads the most recent handover and highlights top priorities | At the start of a new session to pick up where the last one left off |

### Cleanup

| Command | Description |
|---------|-------------|
| `/delete-last-handover` | Show and delete the most recent handover file with confirmation |
| `/delete-all-handovers` | List all handover files, confirm, then delete everything |

### Code Review

| Command | Description | When to use |
|---------|-------------|-------------|
| `/review` | Dispatches specialized review agents in parallel and synthesizes their findings into one report | Before merging a PR, or whenever you want multi-agent code review of a branch or PR URL |

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
| `/create-pr` | Create a GitHub pull request from the current branch |

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

| Command | Description | When to use |
|---------|-------------|-------------|
| `/brainstorm` | Explores ideas, compares approaches, and produces a validated spec before planning | When you have a vague idea and need to pin down scope, constraints, and approach before coding |
| `/plan` | Creates a structured implementation plan with parallel agent research before coding | When scope is clear but the work breakdown and research are not -- produces a step-by-step plan |
| `/work` | Executes a work plan or specification systematically with continuous testing and incremental commits | When a plan file is ready and you want hands-off task-by-task execution with tests and commits |

### Maintenance

| Command | Description |
|---------|-------------|
| `/repair-skill` | Diagnose and fix a broken skill by analyzing structure and verifying API references |

## Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `pre-compact-handover` | PreCompact | Summarizes the conversation and saves a handover before Claude compacts context |

> The hook keeps the 3 most recent handovers in `.claude/handovers/` and prunes older ones automatically. Filenames are timestamps, so sort order is lexicographic.

## Skills

### Agent Orchestration

| Skill | Description |
|-------|-------------|
| `orchestrate-agents` | Discover agents, plan an optimal team, and coordinate parallel or sequential execution |

### Agent Development

| Skill | Description |
|-------|-------------|
| `create-agent` | Agent authoring reference -- frontmatter spec, category definitions, body structure, and quality gates |

### Planning & Execution

| Skill | Description |
|-------|-------------|
| `work` | Execute a work plan or specification systematically -- read the plan, set up a branch, implement tasks with continuous testing, commit incrementally, and ship a PR |

### Code Navigation

| Skill | Description |
|-------|-------------|
| `code-navigation` | LSP-first code navigation with grep fallback -- guides agents on when to use goToDefinition, findReferences, and documentSymbol vs grep-based search |

### Brainstorming

| Skill | Description |
|-------|-------------|
| `visual-companion` | Browser-based visual brainstorming companion for showing mockups, diagrams, and visual options when topics are better understood visually |

### Maintenance

| Skill | Description |
|-------|-------------|
| `repair-skill` | Diagnose broken skills, verify API references against current docs, and apply targeted repairs |

## Agents
<!-- agents-start -->

### Review
<!-- agents:review-start -->

| Agent | What it catches |
|-------|-----------------|
| `architecture-strategist` (`quiver:architecture-strategist`) | Code that violates the project's own conventions and module boundaries |
| `logic-reviewer` (`quiver:logic-reviewer`) | Branches where inputs don't reach the documented output correctly |
| `waste-detector` (`quiver:waste-detector`) | Dead code, redundant utilities, unnecessary abstractions |
| `stress-tester` (`quiver:stress-tester`) | Failure scenarios: inputs, timings, and states that break the new code |
| `security-audit` (`quiver:security-audit`) | Concrete exploit paths for web, API, and mobile surfaces |
| `test-reviewer` (`quiver:test-reviewer`) | Tests that pass without proving the code works |
| `developer-experience-auditor` (`quiver:developer-experience-auditor`) | Confusing error messages, hidden debugging paths, brittle UX for humans and agents |

<!-- agents:review-end -->

### Research
<!-- agents:research-start -->

| Agent | What it catches |
|-------|-----------------|
| `best-practices-researcher` (`quiver:best-practices-researcher`) | Deprecated APIs and outdated patterns versus current library docs |
| `project-context-analyst` (`quiver:project-context-analyst`) | Prior decisions, past bugs, and churn patterns in this area of the codebase |

<!-- agents:research-end -->
<!-- agents-end -->

## External Dependencies

This plugin includes a [Context7](https://context7.com) MCP server for real-time library documentation lookups. It starts automatically when the plugin is enabled (configured in `plugin.json` under `mcpServers`). No authentication required.

**Tools provided:**
- `resolve-library-id` -- Find library ID for a framework/package
- `query-docs` -- Get documentation for a specific library

Supports 100+ frameworks including Rails, React, Next.js, Vue, Django, Laravel, and more. Library/framework names from your codebase are sent to the service only during review agent execution (e.g., best-practices checks), not at plugin load time.

## Uninstall

```
/uninstall quiver
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

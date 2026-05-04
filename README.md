# Quiver

[![Version](https://img.shields.io/badge/version-1.8.1-blue)](https://github.com/yagizdo/quiver/releases)

Quiver is a development lifecycle plugin for AI coding CLIs -- purpose-built skills for brainstorming, planning, execution, code review, and session handover, plus 10 specialized review agents that run in parallel.

## Typical workflow

A normal feature cycle chains these skills. Each one is self-contained and works on its own -- skip steps, reorder them, or use just the ones you need.

1. `/brainstorm` -- turn a vague idea into a validated spec by walking through clarifying questions and trade-off analysis on 2-3 design approaches.
2. `/plan` -- research the codebase in parallel, then break the chosen approach into verifiable step-by-step tasks with exact file paths.
3. `/work` -- execute the plan task-by-task with continuous testing, branch setup, and incremental commits.
4. `/commit` -- generate a Conventional Commits message from staged changes and commit (optionally pushing).
5. `/create-pr` -- open a GitHub pull request with an auto-generated title and description from the branch diff.
6. `/review` -- dispatch specialized review agents in parallel (logic, architecture, security, tests, devex, waste) and synthesize findings into one report.
7. `/handover` -- save an 8-section summary of the session so the next session resumes with full context.

## Installation

Installation differs by CLI.

### Claude Code

```
/plugin marketplace add yagizdo/quiver
/plugin install quiver@yagizdo/quiver
```

Then try `/brainstorm` in any session.

### Cursor (2.5+)

```text
/add-plugin quiver
```

Or browse [cursor.com/marketplace](https://cursor.com/marketplace) and click "Add to Cursor".

- The `cursor-agent` CLI does not load plugin skills (IDE-only). Use Cursor IDE for skill-using workflows.
- `WebFetch` and `WebSearch` are unsupported on Cursor; the included context7 MCP covers documentation lookups.
- If handover auto-save does not fire after install, Cursor's `preCompact` event may use a different JSON field name than Claude Code. Edit `.cursor/hooks.json` to log raw stdin to a file, trigger context compaction, and inspect the log for the actual field names.

### OpenAI Codex CLI

```text
codex plugin marketplace add yagizdo/quiver
```

Then try `/brainstorm` in any session.

- The handover auto-save hook maps to Codex's `Stop` event with a 10-minute cooldown. For on-demand handovers, use `/handover` directly.
- `AskUserQuestion` is polyfilled as numbered text prompts -- reply with the option number.
- Agent dispatch uses `spawn_agent(worker)` with the agent's persona prompt read from `agents/`. The `/review` skill dispatches up to 10 agents in parallel this way.
- The hook script uses `claude -p` for transcript summarization. If the `claude` CLI is not installed, the auto-save hook will silently skip (manual `/handover` still works).

### Gemini CLI

```text
gemini extensions install quiver
```

Then try `/brainstorm` in any session.

- `ask_user` is native on Gemini CLI -- interactive prompts render with full fidelity.
- The handover auto-save hook maps to Gemini CLI's `PreCompress` event. Unlike Codex's Stop event, no cooldown guard is needed -- PreCompress fires only before history compression.
- Agent dispatch reads agent persona prompts from `agents/` and executes them inline. The `/review` skill dispatches up to 10 agents this way.
- The hook script uses `claude -p` for transcript summarization. If the `claude` CLI is not installed, the auto-save hook will silently skip (manual `/handover` still works).

## Components

| Component | Count |
|-----------|-------|
| Hooks | 1 |
| Skills | 16 |
| Agents | 10 |

## Skills

### Session Handover

| Skill | Description | When to use |
|-------|-------------|-------------|
| `/handover` | Builds an 8-section handover note with freshness checks and quality gates | At the end of a work session to preserve context for resuming later |
| `/load-handover` | Loads the most recent handover and highlights top priorities | At the start of a new session to pick up where the last one left off |

### Cleanup

| Skill | Description |
|-------|-------------|
| `/delete-last-handover` | Show and delete the most recent handover file with confirmation |
| `/delete-all-handovers` | List all handover files, confirm, then delete everything |

### Code Review

| Skill | Description | When to use |
|-------|-------------|-------------|
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
--with-codex                         # Also dispatch a Codex-backed reviewer in parallel
```

**Examples:**
```
/review <PR-URL> --terminal          # Review a PR and print in terminal
/review --base main --output ./tmp/   # Review against main, save to ./tmp/
/review --set-output ./reports/      # Set default save path for future reviews
/review <PR-URL> --comment-pr        # Review a PR and post the report as a comment
/review --with-codex                 # Run the standard review plus Codex (cross-model coverage)
```

> When a PR URL is provided, you'll be prompted after the review to post it as a comment. Use `--comment-pr` to skip the prompt and post directly.

> `--with-codex` requires the `codex` CLI installed (`npm install -g @openai/codex`, >= 0.123.0) and authenticated (`codex login`). When the flag is set but the CLI is missing or not authenticated, the Codex agent is skipped with a one-line note and the review proceeds with Claude agents only. Codex findings carry a `(codex-code-reviewer)` source prefix in the synthesized report; when both Claude and Codex flag the same line, the existing `Flagged by:` consensus annotation kicks in.
>
> **Model selection:** Quiver does not pass `--model` to the codex CLI -- whichever model your local codex is configured to use (set in `~/.codex/config.toml`, CLI default, or env override) is the model that will run the review. If your auth method or plan does not have access to a given model, change your local codex configuration; Quiver will not override it.

**Re-review detection:** If you run `/review` again on the same branch after fixing issues, it automatically detects the previous report and switches to re-review mode. It only flags new issues introduced since the last review -- no duplicate findings, no infinite review loops. If nothing functional changed, it approves immediately.

### Git

| Skill | Description |
|-------|-------------|
| `/commit` | Generate a Conventional Commits message from staged changes, commit, and optionally push |
| `/create-pr` | Create a GitHub pull request from the current branch |

```
/commit                              # Commit with interactive prompt (commit, commit & push, edit, cancel)
/commit --push                       # Auto commit and push without prompting
```

### Agent Development

| Skill | Description |
|-------|-------------|
| `/create-agent` | Scaffold a new agent interactively from a description or Q&A walkthrough |
| `/create-agents-md` | Analyze project context and generate an AGENTS.md checklist for AI agents |

### Planning & Execution

| Skill | Description | When to use |
|-------|-------------|-------------|
| `/brainstorm` | Explores ideas, compares approaches, and produces a validated spec before planning | When you have a vague idea and need to pin down scope, constraints, and approach before coding |
| `/plan` | Creates a structured implementation plan with parallel agent research before coding | When scope is clear but the work breakdown and research are not -- produces a step-by-step plan |
| `/work` | Executes a work plan or specification systematically with continuous testing and incremental commits | When a plan file is ready and you want hands-off task-by-task execution with tests and commits |

### Maintenance

| Skill | Description |
|-------|-------------|
| `/repair-skill` | Diagnose and fix a broken skill by analyzing structure and verifying API references |

### Internal References

These skills back the slash-invocable skills above. They are not invoked directly; they exist so other skills and agents can include their methodology by reference.

| Skill | Description |
|-------|-------------|
| `code-navigation` | LSP-first code navigation with grep fallback -- guides agents on when to use goToDefinition, findReferences, and documentSymbol vs grep-based search |
| `orchestrate-agents` | Discover agents, plan an optimal team, and coordinate parallel or sequential execution |
| `visual-companion` | Browser-based visual brainstorming companion for showing mockups, diagrams, and visual options when topics are better understood visually |

## Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `pre-compact-handover` | PreCompact | Summarizes the conversation and saves a handover before the CLI compacts context |

> The hook keeps the 3 most recent handovers in `.claude/handovers/` and prunes older ones automatically. Filenames are timestamps, so sort order is lexicographic.

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
| `codex-code-reviewer` (`quiver:codex-code-reviewer`) | Cross-model code review via the OpenAI Codex CLI; dispatched only when `--with-codex` is passed and the `codex` CLI is installed. Uses whatever model your local codex is configured for -- Quiver does not override `--model` |

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

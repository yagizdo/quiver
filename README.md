# Quiver

[![Version](https://img.shields.io/badge/version-1.15.0-blue)](https://github.com/yagizdo/quiver/releases)

Quiver is a development lifecycle plugin for AI coding CLIs. Purpose-built skills for brainstorming, planning, execution, debugging, code review, and session handover, plus specialized agents for review and debugging.

## Typical workflow

A normal feature cycle chains these skills. Each one is self-contained and works on its own. Skip steps, reorder them, or use just the ones you need. If you hit a bug at any point, run `/hypothesis-debugging` to investigate it systematically.

1. `/brainstorm`: turn a vague idea into a validated spec by walking through clarifying questions and trade-off analysis on 2-3 design approaches.
2. `/plan`: research the codebase in parallel, then break the chosen approach into verifiable step-by-step tasks with exact file paths.
3. `/work`: execute the plan task-by-task with continuous testing, branch setup, and incremental commits.
4. `/commit`: generate a Conventional Commits message from staged changes and commit (optionally pushing).
5. `/create-pr`: open a GitHub pull request with an auto-generated title and description from the branch diff.
6. `/review`: dispatch review agents to check code quality, security, and architecture, then synthesize findings into one report. Runs 5 agents by default; `--deep` for the full pipeline.
7. `/handover`: save an 8-section summary of the session so the next session resumes with full context.

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
- `AskUserQuestion` is polyfilled as numbered text prompts: reply with the option number.
- Agent dispatch uses `spawn_agent(worker)` with the agent's persona prompt read from `agents/`. The `/review` skill dispatches 5 agents by default, or the full pipeline with `--deep`.
- The hook script uses `claude -p` for transcript summarization. If the `claude` CLI is not installed, the auto-save hook will silently skip (manual `/handover` still works).

### Gemini CLI

```text
gemini extensions install quiver
```

Then try `/brainstorm` in any session.

- `ask_user` is native on Gemini CLI: interactive prompts render with full fidelity.
- The handover auto-save hook maps to Gemini CLI's `PreCompress` event. Unlike Codex's Stop event, no cooldown guard is needed: PreCompress fires only before history compression.
- Agent dispatch reads agent persona prompts from `agents/` and executes them inline. The `/review` skill dispatches 5 agents by default, or the full pipeline with `--deep`.
- The hook script uses `claude -p` for transcript summarization. If the `claude` CLI is not installed, the auto-save hook will silently skip (manual `/handover` still works).

### OpenCode

OpenCode uses its own plugin install; install Quiver separately even if you
already use it in another harness.

- Tell OpenCode:

  ```
  Fetch and follow instructions from https://raw.githubusercontent.com/yagizdo/quiver/refs/heads/master/.opencode/INSTALL.md
  ```

- Detailed docs: [`.opencode/README.md`](.opencode/README.md)

## Components

| Component | Count |
|-----------|-------|
| Hooks | 1 |
| Skills | 22 |
| Agents | 20 |

## What Do I Use?

### Building Something

| Situation | Command | What happens |
|-----------|---------|--------------|
| I have a vague idea, not sure where to start | `/brainstorm` | Walks through clarifying questions, compares 2-3 approaches, outputs a validated spec |
| Scope is clear, need a step-by-step breakdown | `/plan` | Researches codebase in parallel, produces a task-by-task plan with file paths |
| Plan is ready, want hands-off execution | `/work` | Executes tasks one by one with testing, branch setup, and incremental commits |
| Want a quick second opinion on an approach | `/advise` | Gives a senior-style inline review -- no spec or plan artifact |

### Shipping Something

| Situation | Command | What happens |
|-----------|---------|--------------|
| I want to build a project from a description without touching it myself | `/ship` | Deep planning Q&A (outcomes, scope, stack, verification), then autonomous loop: code + test + review + fix until done. Manifest at `docs/ship/<project>-manifest.md` |

### Reviewing Code

| Situation | Command | What happens |
|-----------|---------|--------------|
| About to merge, want multi-agent review | `/review` | Dispatches 5 review agents, synthesizes findings into one report |
| Want a quick senior dev sanity check | `/senior-review` | One pragmatic reviewer evaluates structure, quality, risks |
| Got a review report, not sure which findings matter | `/report-check` | Audits the report for noise, false positives, and overkill |

```
/review                    # fast review (5 agents, prompts for base branch)
/review --deep             # full pipeline: all agents + quality check + senior review
/review --base main        # review against a specific base branch
/review <PR-URL>           # review a pull request by URL
```

Pass `--comment-pr` to post the report as a PR comment. Use `--deep --with-codex` for cross-model coverage (requires `codex` CLI).

Re-review detection: if you run `/review` again on the same branch after fixing issues, it automatically detects the previous report and switches to re-review mode.

### Fixing a Bug

| Situation | Command | What happens |
|-----------|---------|--------------|
| Bug won't go away after multiple attempts | `/hypothesis-debugging` | Generates hypotheses, tests each systematically, traces root cause, proposes reviewed fix |

### Git & Shipping

| Situation | Command | What happens |
|-----------|---------|--------------|
| Changes ready to commit | `/commit` | Generates a Conventional Commits message, commits, optionally pushes |
| Branch ready for PR | `/create-pr` | Creates a GitHub pull request with auto-generated title and description |

### Session Management

| Situation | Command | What happens |
|-----------|---------|--------------|
| Ending a work session | `/handover` | Saves an 8-section summary so the next session resumes with full context |
| Starting a new session | `/load-handover` | Loads the most recent handover and highlights top priorities |
| Last handover is stale or wrong | `/delete-last-handover` | Shows and deletes the most recent handover file with confirmation |
| Want a clean slate | `/delete-all-handovers` | Lists all handover files, confirms, then deletes everything |

### Tooling & Maintenance

| Situation | Command | What happens |
|-----------|---------|--------------|
| A skill is broken or outdated | `/repair-skill` | Diagnoses the skill's structure and fixes API references |
| Need a new agent for the project | `/create-agent` | Scaffolds a new agent interactively from a description |
| Want an AGENTS.md for the project | `/create-agents-md` | Analyzes project context and generates an operational checklist |

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
| `codex-code-reviewer` (`quiver:codex-code-reviewer`) | Cross-model code review via the OpenAI Codex CLI; dispatched only when `--with-codex` is passed and the `codex` CLI is installed. Uses whatever model your local codex is configured for: Quiver does not override `--model` |
| `report-checker` (`quiver:report-checker`) | Independent quality auditor for review reports -- detects noise, false positives, overkill, and findings that exist to appear thorough |
| `senior-reviewer` (`quiver:senior-reviewer`) | Language-aware senior developer review -- evaluates code through a pragmatic team lead lens with optional meta-review of other agents' findings in the pipeline |

<!-- agents:review-end -->

### Research
<!-- agents:research-start -->

| Agent | What it catches |
|-------|-----------------|
| `best-practices-researcher` (`quiver:best-practices-researcher`) | Deprecated APIs and outdated patterns versus current library docs |
| `project-context-analyst` (`quiver:project-context-analyst`) | Prior decisions, past bugs, and churn patterns in this area of the codebase |
| `code-locator` (`quiver:code-locator`) | Fast file:line locations for "where is X / what calls Y" without heavy mapping |
| `code-navigator` (`quiver:code-navigator`) | CodeGraph-first codebase explorer that maps files, symbols, and patterns relevant to a task |

<!-- agents:research-end -->

### Debug
<!-- agents:debug-start -->

| Agent | What it does |
|-------|--------------|
| `code-tracer` (`quiver:code-tracer`) | Traces execution paths across files to find where behavior diverges from expectation |
| `log-analyzer` (`quiver:log-analyzer`) | Parses log dumps and stack traces to extract error patterns and map them to source code |
| `regression-finder` (`quiver:regression-finder`) | Analyzes git history to find which commit introduced a bug |
| `environment-checker` (`quiver:environment-checker`) | Checks dependency versions, config files, and environment setup for mismatches |
| `fix-reviewer` (`quiver:fix-reviewer`) | Reviews every proposed fix for overengineering, workarounds, and architectural consistency |

<!-- agents:debug-end -->

### Workflow
<!-- agents:workflow-start -->

| Agent | What it does |
|-------|--------------|
| `plan-reviewer` (`quiver:plan-reviewer`) | Reviews implementation plans for logical coherence, dependency ordering, coverage completeness, and spec alignment |

<!-- agents:workflow-end -->
<!-- agents-end -->

## External Dependencies

This plugin includes a [Context7](https://context7.com) MCP server for real-time library documentation lookups. It starts automatically when the plugin is enabled (configured in `plugin.json` under `mcpServers`). No authentication required.

**Tools provided:**
- `resolve-library-id`: Find library ID for a framework/package
- `query-docs`: Get documentation for a specific library

Supports 100+ frameworks including Rails, React, Next.js, Vue, Django, Laravel, and more. Library/framework names from your codebase are sent to the service only during review agent execution (e.g., best-practices checks), not at plugin load time.

## Uninstall

```
/uninstall quiver
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

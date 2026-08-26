# Quiver

[![Version](https://img.shields.io/badge/version-1.17.0-blue)](https://github.com/yagizdo/quiver/releases)

Quiver is a development lifecycle plugin for AI coding CLIs. Purpose-built skills for brainstorming, planning, execution, debugging, code review, and session handover, plus specialized agents for review and debugging.

## Contents

- [Typical workflow](#typical-workflow)
- [Installation](#installation)
- [Components](#components)
- [What Do I Use?](#what-do-i-use)
  - [Building Something](#building-something)
  - [Building a Whole Project](#building-a-whole-project)
  - [Implementing a Design](#implementing-a-design)
  - [Reviewing Code](#reviewing-code)
  - [Fixing a Bug](#fixing-a-bug)
  - [Committing & PRs](#committing--prs)
  - [Session Management](#session-management)
  - [Tooling & Maintenance](#tooling--maintenance)
- [Hooks](#hooks)
- [Agents](#agents)
  - [Review](#review)
  - [Research](#research)
  - [Debug](#debug)
  - [Workflow](#workflow)
- [External Dependencies](#external-dependencies)
- [CLI Notes](#cli-notes)
- [Uninstall](#uninstall)
- [License](#license)

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

Installation differs by CLI. Once it is installed, `/brainstorm` works in any session; per-CLI differences are in [CLI Notes](#cli-notes).

### Claude Code

```
/plugin marketplace add yagizdo/quiver
/plugin install quiver@yagizdo/quiver
```

### Cursor (2.5+)

```text
/add-plugin quiver
```

Or browse [cursor.com/marketplace](https://cursor.com/marketplace) and click "Add to Cursor".

### OpenAI Codex CLI

```text
codex plugin marketplace add yagizdo/quiver
```

### OpenCode

OpenCode has its own plugin install, so install Quiver separately even if you already use it in another harness. Tell OpenCode:

```
Fetch and follow instructions from https://raw.githubusercontent.com/yagizdo/quiver/refs/heads/master/.opencode/INSTALL.md
```

Detailed docs: [`.opencode/README.md`](.opencode/README.md)

## Components

| Component | Count |
|-----------|-------|
| Hooks | 3 |
| Skills | 25 |
| Agents | 20 |

## What Do I Use?

### Building Something

| Situation | Command | What happens |
|-----------|---------|--------------|
| I have a vague idea, not sure where to start | `/brainstorm` | Walks through clarifying questions, compares 2-3 approaches, outputs a validated spec |
| Scope is clear, need a step-by-step breakdown | `/plan` | Researches codebase in parallel, produces a task-by-task plan with file paths |
| Plan is ready, want hands-off execution | `/work` | Executes tasks one by one with testing, branch setup, and incremental commits |
| Want a quick second opinion on an approach | `/advise` | Gives a senior-style inline review -- no spec or plan artifact |

### Building a Whole Project

| Situation | Command | What happens |
|-----------|---------|--------------|
| I want to build a project from a description without touching it myself | `/ship` | Deep planning Q&A (outcomes, scope, stack, verification), then autonomous loop: code + test + review + fix until done. Manifest at `docs/ship/<project>-manifest.md` |

### Implementing a Design

| Situation | Command | What happens |
|-----------|---------|--------------|
| A Figma frame is ready to become code | `/design` | Reads the selected nodes through the figma-bridge MCP, maps Figma variables onto the project's own theme tokens, and writes a self-contained plan to `.claude/plans/` |
| Want the frame built and measured without babysitting it | `/design --auto` | Same extraction and same questions, then straight through the build and the fidelity measurement with no further prompt |
| Design plan is ready, want it built pixel-accurate | `/design-build` | Implements each node against its embedded spec, then fixes whatever `/design-verify` reports, under a bounded retry budget |
| Built UI is on screen, want to know how far off it is | `/design-verify` | Captures the running app, normalizes both images to a common logical width, measures the deviations, and writes a report to disk |

```
/design                    # extract whatever is selected in Figma
/design 4029:12345         # extract a specific node by ID
/design --auto             # extract, then build and measure without stopping
/design --auto --no-commit # same, and write no commit whatever the plan says
/design-build              # pick a design plan and build it
/design-verify             # measure a built screen against its spec
```

`--auto` removes the handoffs between the three stages, not the questions that decide what gets built.

- `/design` still asks which file, which nodes, what an unmapped variable resolves to, how the build should commit and verify, and whether to overwrite a plan that already exists for the same screen.
- Those questions all arrive in one call. After that the run stays quiet until the fidelity summary.
- One node still gets three fix attempts. Auto mode records whatever deviation is left over and moves on rather than asking.

`--no-commit` forces `commit_strategy: none` for a single run.

- On a fresh plan it changes nothing. Not committing is already the recommended answer to `/design`'s commit question, so the flag guarantees that answer rather than overriding it.
- It earns its keep against an existing plan that carries `per-task` or `single`, because `/design-build` never re-asks that question.
- The override lasts one run and never edits the plan.
- The two flags are independent. `/design-build <plan> --no-commit` is as valid as `/design --auto --no-commit`.

`/design` is the only stage that talks to Figma.

- The plan carries every measurement, token, and layout anchor `/design` produced, so `/design-build` runs with Figma disconnected and `/design-verify` measures against the plan alone.
- `/design-verify` reads any file with a `### Node Specs` section, including a measurement spec you wrote by hand. It does not need a screenshot or an installed comparison tool.
- Setup is in [External Dependencies](#external-dependencies).

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

### Committing & PRs

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
| `pre-tool-use-guard` | PreToolUse | Classifies every Bash command before it runs -- refuses the handful that are irreversible, prompts on the destructive-but-recoverable ones, stays silent otherwise |
| `pre-compact-handover` | PreCompact | Summarizes the conversation and saves a handover before the CLI compacts context |
| `session-start-auto-dispatch` | SessionStart | Reads every skill's `when-to-use` and emits a routing block so intent matches invoke the right skill |

> The handover hook keeps the 3 most recent handovers in `.claude/handovers/` and prunes older ones automatically. Filenames are timestamps, so sort order is lexicographic.

## Agents

Review, research, and debug agents run with the `Edit`, `Write`, `NotebookEdit`,
`WebSearch`, and `WebFetch` tools denied -- they are built to read your code and
report findings, not to change it. `Bash` stays enabled because these agents need
`git diff`, `git log`, and `git blame`, so the denial is a guardrail against
accidental edits rather than a sandbox: a shell command can still write a file or
reach the network. Two agents carry a narrower denylist: `best-practices-researcher`
keeps web access so it can check library versions against upstream release notes,
and `codex-code-reviewer` can write because it persists the raw output of the
external reviewer it wraps.

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

### figma-bridge (optional, for `/design`)

`/design` reads Figma through the [figma-mcp-bridge](https://github.com/gethopp/figma-mcp-bridge) MCP server. It is not bundled in `plugin.json` -- the bridge also needs a Figma plugin installed by hand, so auto-starting the server alone would only get you halfway.

Add the server to your MCP config:

```json
{
  "figma-bridge": {
    "command": "npx",
    "args": ["-y", "@gethopp/figma-mcp-bridge"]
  }
}
```

The Figma plugin side is a manual import from the bridge's [releases page](https://github.com/gethopp/figma-mcp-bridge/releases), and its README carries the current steps. Leave the plugin running inside the file you are reading -- it holds the WebSocket, and closing it drops the connection mid-extraction.

`/design` only calls the bridge's read tools. `/design-build` and `/design-verify` never call it at all. Every other Quiver skill works without it.

### ImageMagick (optional, for `/design-verify`)

`/design-verify` works with nothing installed -- it reads the built UI against the spec and marks the report low confidence. Installing ImageMagick upgrades that structural read into a measured differing-pixel count:

```
brew install imagemagick
```

The skill probes `magick -version` and `magick -list metric`, picks the `PDC` metric when the build has it, and records which comparison path produced each report. Nothing breaks without it; the reports simply carry fewer numbers.

Device capture is optional in the same way. `/design-verify` uses `xcrun simctl` for iOS simulators, `adb` for Android, `pymobiledevice3` for physical iOS devices, and the Playwright MCP for web -- whichever is already on the machine. Each absent tool prints one install hint and the run continues down to the next option.

## CLI Notes

Every CLI runs the same skills and the same agents, and `/review` fans out to 5 agents by default on all of them, or the full pipeline with `--deep`.

### Cursor

- The `cursor-agent` CLI does not load plugin skills (IDE-only). Use Cursor IDE for skill-using workflows.
- `WebFetch` and `WebSearch` are unsupported on Cursor; the included context7 MCP covers documentation lookups.
- If handover auto-save does not fire after install, Cursor's `preCompact` event may use a different JSON field name than Claude Code. Edit `.cursor/hooks.json` to log raw stdin to a file, trigger context compaction, and inspect the log for the actual field names.

### Codex

- Codex uses the bundled default `PreCompact` hook in `hooks/hooks.json` for automatic handover auto-save before automatic compaction. If Codex prompts for hook review, open `/hooks` and trust the Quiver hook; `/handover` also works manually.
- `AskUserQuestion` is polyfilled as numbered text prompts: reply with the option number.
- Agent dispatch uses `spawn_agent(worker)` with the agent's persona prompt read from `agents/`.

### Gemini CLI (legacy)

Google retired Gemini CLI on 18 June 2026, with no grace period for free, AI Pro, and Ultra personal accounts. Under a Gemini Code Assist Standard or Enterprise license the extension still installs and runs:

```text
gemini extensions install quiver
```

Antigravity CLI is Google's replacement. Quiver has not been tested there yet.

- `ask_user` is native: interactive prompts render with full fidelity.
- The handover auto-save hook maps to Gemini CLI's `PreCompress` event, which fires only before history compression (like Claude Code's PreCompact) -- no cooldown guard needed.
- Agent dispatch reads agent persona prompts from `agents/` and executes them inline.
- The hook script uses `claude -p` for transcript summarization. If the `claude` CLI is not installed, the auto-save hook will silently skip (manual `/handover` still works).

## Uninstall

```
/uninstall quiver
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

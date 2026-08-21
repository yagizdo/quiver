# Quiver on Codex: Interpretation Rules

Quiver's agents and skills were originally written for Claude Code. When you (the Codex agent) load any file under `agents/` or `skills/` and execute the workflow it describes, follow these substitution rules.

## Inline shell-block syntax

Quiver skills contain blocks like:

    !`git status`

In Claude Code, the harness pre-executes these and injects the output into the prompt. Codex does not do this. When you see one of these blocks in a skill body:

1. Execute the command yourself via shell execution.
2. Read the output.
3. Continue with the rest of the skill body, treating the output as if the harness had injected it.

## Tool-name substitutions

When a Quiver agent or skill references a Claude Code tool name, use the Codex equivalent.

| Claude Code | Codex | Notes |
|-------------|-------|-------|
| Bash | Shell execution | Identical semantics. |
| Read | File read | Built-in file reading capability. |
| Write | apply_patch (full file) | Use apply_patch with the full file content, or shell redirection for new files. |
| Edit | apply_patch (partial) | Apply a unified diff patch to modify specific lines. |
| Grep | Shell grep | Run `grep` via shell execution. |
| Glob | Shell find | Run `find` via shell execution. Codex does not expose a Glob tool. |
| Agent | spawn_agent | See the Agent dispatch section below. |
| AskUserQuestion | (polyfill) | See the AskUserQuestion section below. |
| WebFetch | (unsupported) | Use the context7 MCP for documentation lookups. |
| WebSearch | Web search | Codex has native web search. |
| TaskCreate / TaskUpdate | update_plan | Codex exposes plan tracking; the agent uses it naturally. |

## Agent dispatch

Quiver skills dispatch specialized agents using the Agent tool with a `subagent_type` parameter (e.g., `subagent_type: "quiver:security-audit"`). Codex does not have a named agent registry in the plugin manifest. When a skill asks you to dispatch a named agent:

1. Parse the agent name from the subagent_type (strip the `quiver:` prefix if present).
2. Find the corresponding `.md` file in the plugin's `agents/` directory:
   - Review agents: `agents/review/<name>.md`
   - Research agents: `agents/research/<name>.md`
3. Read the full file content -- the YAML frontmatter plus the markdown body is the agent's persona prompt.
4. Spawn a worker agent with the persona prompt plus the task-specific context (diff, file list, etc.) that the skill provides:
   - `spawn_agent(agent_type="worker", message=<persona prompt + task context>)`
5. The `model` field in the agent's YAML frontmatter is advisory -- use whatever model is available.

When a skill dispatches multiple agents in parallel (e.g., `/review` dispatches up to 10 agents), spawn them as parallel workers. Collect all results before continuing to the synthesis step.


## AskUserQuestion substitution

Codex does not expose an action-button question API. When a Quiver skill says `AskUserQuestion(...)` or asks you to present action-button prompts, render a numbered text prompt and wait for the user's reply.

Format:

    <one-sentence question>

    1. <Option A label> -- <one-line description>
    2. <Option B label> -- <one-line description>
    3. <Option C label> -- <one-line description>
    4. Other -- describe your choice

    Reply with the number, or describe your choice.

Rules:

1. Always include "Other -- describe" as the last option, mirroring Claude Code's free-text fallback.
2. Number options 1-N; do not letter them.
3. Do not collapse multiple decisions into a single prompt unless the original AskUserQuestion call did so. One question per polyfill prompt is the default.
4. After the user replies with a number, restate the choice in one sentence ("Going with option 2: ...") before continuing. This catches misclicks visible to the user before the action runs.

## Handover auto-save hook

Codex supports `PreCompact`, and Quiver bundles the shared `hooks/hooks.json` config so the handover auto-save hook runs before automatic compaction. No `Stop` hook or separate Codex hook manifest is needed for that default bundled hook file. If Codex reports that the hook needs review, use `/hooks` to inspect and trust the Quiver hook before expecting it to run. The manual `/handover` skill always works regardless of hook trust state.

An earlier version mapped the handover auto-save hook onto Codex's `Stop` event (turn completion) with a 10-minute guard, but the guard only reset on a *successful* save -- if the save kept failing (e.g. `transcript_path` absent from Codex's Stop payload, or `claude` not resolvable in the hook's shell), it re-ran the full summarization on every single turn instead of throttling. That cost real time and tokens with nothing to show for it, so the Stop-hook mapping was removed. Do not reintroduce Stop-event handover auto-save or fallback polling as a substitute for `PreCompact`.

# Quiver on Gemini CLI: Interpretation Rules

Quiver's agents and skills were originally written for Claude Code. When you (the Gemini CLI agent) load any file under `agents/` or `skills/` and execute the workflow it describes, follow these substitution rules.

## Inline shell-block syntax

Quiver skills contain blocks like:

    !`git status`

In Claude Code, the harness pre-executes these and injects the output into the prompt. Gemini CLI does not do this. When you see one of these blocks in a skill body:

1. Execute the command yourself via `run_shell_command`.
2. Read the output.
3. Continue with the rest of the skill body, treating the output as if the harness had injected it.

## Tool-name substitutions

When a Quiver agent or skill references a Claude Code tool name, use the Gemini CLI equivalent.

| Claude Code | Gemini CLI | Notes |
|-------------|-----------|-------|
| Bash | run_shell_command | Identical semantics. |
| Read | read_file | Identical semantics. |
| Write | write_file | Identical semantics. |
| Edit | replace | Same old_string/new_string semantics. |
| Grep | grep_search | Gemini has native regex grep. |
| Glob | glob | Gemini has native glob. |
| Agent | (runtime injection) | See the Agent dispatch section below. |
| AskUserQuestion | ask_user | Native -- map the tool name. |
| WebSearch | google_web_search | Native. |
| WebFetch | web_fetch | Native. |
| TaskCreate / TaskUpdate | write_todos | Gemini's task tracking. |
| EnterPlanMode | enter_plan_mode | Native. |
| ExitPlanMode | exit_plan_mode | Native. |
| Skill | activate_skill | Native. |

## Agent dispatch

Quiver skills dispatch specialized agents using the Agent tool with a `subagent_type` parameter (e.g., `subagent_type: "quiver:security-audit"`). Gemini CLI does not have a named agent registry in the extension manifest. When a skill asks you to dispatch a named agent:

1. Parse the agent name from the subagent_type (strip the `quiver:` prefix if present).
2. Find the corresponding `.md` file in the extension's `agents/` directory:
   - Review agents: `agents/review/<name>.md`
   - Research agents: `agents/research/<name>.md`
3. Read the full file content -- the YAML frontmatter plus the markdown body is the agent's persona prompt.
4. Execute the persona prompt inline, treating the agent's instructions as your own for the duration of that task. Apply the persona's methodology to the diff or file set the skill provides.
5. The `model` field in the agent's YAML frontmatter is advisory -- use whatever model is available.

When a skill dispatches multiple agents in parallel, execute them sequentially. Collect all results before continuing to the synthesis step.


## PreCompress hook

The handover auto-save hook maps to Gemini CLI's PreCompress event via `hooks/hooks-gemini.json`. PreCompress fires before history compression -- the same trigger point as Claude Code's PreCompact. No guard condition is needed. The hook script uses `claude -p` for transcript summarization. If the `claude` CLI is not installed, the auto-save hook will silently skip (manual `/handover` still works).

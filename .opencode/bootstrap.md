# Quiver Bootstrap

You have Quiver: a set of skills covering the development lifecycle.

## Instruction Priority

Quiver skills override default system behavior, but **user instructions always take precedence**:

1. **User's explicit instructions** (CLAUDE.md, AGENTS.md, direct requests) -- highest priority
2. **Quiver skills** -- override default system behavior where they conflict
3. **Default system prompt** -- lowest priority

If AGENTS.md says "don't use TDD" and a Quiver skill says "always use TDD", follow the user's instructions. The user is in control.

## Check For a Skill First

Before responding to a user message -- including a clarifying question -- check whether a Quiver skill covers the request, and load it with OpenCode's native `skill` tool if one does. Match on each skill's `when-to-use:` frontmatter, whether the user typed a `/skill-name` prefix or described the task in plain language. A skill that turns out to be the wrong fit costs one tool call; skipping the check costs the workflow it encodes. When several apply, process skills (`brainstorm`, `hypothesis-debugging`) come before implementation skills (`plan`, `work`).

## OpenCode Tool Mapping

Skills speak in actions ("create a todo", "dispatch a subagent", "read a file") rather than naming any one runtime's tools. On OpenCode these resolve to:

| Action in a skill | OpenCode tool |
|-------------------|---------------|
| Create or update todos | `todowrite` |
| `Subagent (general-purpose):` | `task` with `subagent_type: "general"` (or `"explore"`, or a named Quiver agent) |
| Invoke a skill | `skill` |
| Read a file | `read` |
| Create, edit, or delete a file | `apply_patch` |
| Run a shell command | `bash` |
| Search file contents / find files by name | `grep`, `glob` |
| Fetch a URL | `webfetch` |

OpenCode has no `AskUserQuestion` equivalent. Where a skill asks for a decision, present the options as a numbered list and wait for the user to type a number.

## Quiver Workflow

The canonical chain, in order. Skip steps, reorder them, or use only the ones you need.

1. `/brainstorm` -- turn a vague idea into a validated spec
2. `/plan` -- research the codebase in parallel, break the chosen approach into verifiable steps
3. `/work` -- execute the plan task-by-task with continuous testing
4. `/commit` -- generate a Conventional Commits message and commit
5. `/create-pr` -- open a GitHub pull request
6. `/review` -- dispatch review agents and synthesize findings
7. `/handover` -- save an 8-section summary for the next session (`/handover --clear` drops a stale one)

Hit a bug at any point: `/hypothesis-debugging`.

When the work starts from a Figma design rather than a written idea, `/design` replaces steps 1-2 and `/design-build` replaces step 3. `/design-build` reports fidelity as skipped; `/design-fix` closes that gap, comparing one built component against its Figma node -- or against the plan's Node Specs when the bridge is not connected -- and fixing the deviations you pick. Rejoin the chain at `/commit`.

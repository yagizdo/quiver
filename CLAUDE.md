# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Quiver

Composable development lifecycle plugin for AI coding CLIs. Expert tools for every development moment -- independently useful, optionally combined.
Dependencies: `bash`, `claude` CLI.

## Architecture

- **`.claude-plugin/`** — Plugin manifest (`plugin.json`) and marketplace listing (`marketplace.json`). Defines name, version, hook/skill/agent registration, and MCP servers.
- **`skills/`** — 16 skill directories (each contains `SKILL.md`). Each `SKILL.md` carries YAML front-matter (`name`, `description`) and is a self-contained prompt; the `name` field doubles as the slash invocation (`/handover`, `/review`, etc.). **Exception:** `visual-companion` also contains `server.py`, a runtime executable -- this is the only skill with non-prompt code.
- **`agents/`** — 10 agent definitions organized by category (`review/`, `research/`). Agents are persona prompts spawned as subagents.
- **`hooks/`** — `hooks.json` registers event hooks; `scripts/` holds implementations. Currently one hook: PreCompact (fires before context compaction).
- **Storage** — Handover files are written to `<project>/.claude/handovers/`.
- **Rules** — `.claude/rules/` contains `skill-rules.md` (hard rules and learned lessons for skills, formerly `command-rules.md`), `review-agent-rules.md`, `cli-overlay-rules.md`, and `readme-structure.md`.
- **External MCP** — Context7 MCP server (`plugin.json` > `mcpServers`) provides real-time library documentation lookups for review agents.

## System Behavior

- **Skills** — Markdown files executed by Claude Code. Shell blocks (`` !`…` ``) run inline and inject output into the prompt. Skills cannot call hook scripts directly; they duplicate save/prune logic as Claude instructions.
- **Hooks** — Bash scripts invoked by Claude Code on lifecycle events. The PreCompact hook reads `transcript_path` from stdin JSON (via `sed`), pipes the transcript to `claude -p` for summarization, and writes the result to the handovers directory.
- **SYNC contract** — The 8 handover section headings are defined in two places that must stay identical: `skills/handover/SKILL.md:96` (the marker comment) plus the headings at lines 99-129, and `hooks/scripts/pre-compact-handover.sh:25`. Both files contain a `SYNC:` comment pointing to the other. If you change headings, update both and verify line numbers in the comments.

## Development Standards

### Feature Admission Test

Every proposed feature must pass both conditions before design begins:

1. **Standalone:** It must be useful when invoked in isolation, without any other Quiver skill having been run.
2. **Composable:** It must accept input from other skills and/or produce output that other skills can consume.

If a feature only works inside a pipeline (requires prior skill X to have run), redesign it to accept equivalent input from any source. If it produces no output that other skills can use and accepts no input from them, it is a utility -- still valid, but verify it belongs in Quiver rather than in the user's project.

### Adding a Skill

1. Create `skills/<name>/SKILL.md` with YAML front-matter containing `name` and `description` fields. The `name` field must match the directory (and filename without `.md`) — it enables prefix-free access (e.g., `/handover` instead of `/quiver:handover`).
2. Skills are **prompts**, not scripts. `` !`…` `` blocks gather raw data; the rest of the file is a prompt that tells Claude how to interpret the data, make decisions, and take actions with its own tools. Never write a bare code block without accompanying prompt guidance — marketplace users need skills that work out of the box.
3. Do not use `$()` command substitution, variable assignment, `if/else`, or logic-bearing pipes in `` !`…` `` blocks — Claude Code blocks these in marketplace plugins.
4. Do not reference `CLAUDE_PLUGIN_ROOT` from inside `SKILL.md` — it is unavailable in skill prompts. (`CLAUDE_PLUGIN_ROOT` is still available inside `hooks.json` and hook scripts.)
5. Follow the hard rules and learned lessons in `.claude/rules/skill-rules.md`. For structural patterns (role framing, decision trees, output format), read existing skills (`skills/review/SKILL.md`, `skills/work/SKILL.md`, `skills/commit/SKILL.md`) as examples -- adapt to the new skill's purpose, don't copy mechanically.
6. Every `` !`…` `` block must exit 0 even when the target file or directory does not exist. Use the `|| echo "NOT_FOUND: <path>"` pattern (like the existing `|| echo "NO_GIT"` pattern for git commands) so the prompt receives actionable context instead of a silent failure. Reserve `|| true` only when no downstream logic needs to know the path was missing.
7. End every migrated or new skill with a `## Test Plan` section (Trigger / Setup / Expected behavior / Verification checklist / Known gotchas). The Test Plan is the merge gate -- a skill without one is incomplete.

### Adding an Agent

1. Run `/quiver:create-agent` to scaffold agents interactively -- it handles path, category, and frontmatter automatically.
2. Agents are **persona prompts**, not skills. They define a specialist role that gets spawned as a subagent by skills or directly via the Agent tool.
3. Agents live in `agents/<category>/<name>.md` with YAML front-matter fields: `name`, `description`, `model`.
4. Category directories: `review/`, `research/`, `workflow/`, `design/`, `docs/`, or custom.
5. The `agents/` directory is registered in `plugin.json`'s `agents` array.
6. If the agent searches the broader codebase (beyond files it already knows about), reference the `code-navigation` skill and include the Code Navigation Strategy block from `skills/code-navigation/SKILL.md`. The dispatching skill must pass `lsp_available` context.
7. If the agent will be dispatched by `/quiver:review` (anything under `agents/review/` or any cross-category agent listed in `skills/review/SKILL.md` Step 2a Tier 2), follow the hard rules in `.claude/rules/review-agent-rules.md`. In particular, every review agent must carry the hypothetical-language ban rule (canonical text, or a domain-specific exemption variant for adversarial agents like `stress-tester` and `security-audit`).

### Adding or Modifying a Hook

1. Register the event in `hooks/hooks.json` with `"type": "command"` (the only supported hook type).
2. Place the script in `hooks/scripts/`. Use `$CLAUDE_PROJECT_DIR` (falls back to `pwd`) for the project root.
3. `$CLAUDE_PLUGIN_ROOT` is available in `hooks.json` and hook scripts.

### Invariants

- **Retention policy** — Exactly the 3 most recent `.md` files in `.claude/handovers/` are kept. Both the handover skill and hook implement pruning independently.
- **Timestamp format** — Filenames use `date '+%Y-%m-%d_%H-%M-%S'`. This format is lexicographically sortable.

## Testing

- **Skills** — Run the slash invocation in a Claude Code session and follow the `## Test Plan` section embedded in each `SKILL.md`.
- **Hook** — Pipe test JSON to the script:
  ```bash
  echo '{"transcript_path":"/path/to/transcript.json"}' | bash hooks/scripts/pre-compact-handover.sh
  ```
- **Syntax check** — `bash -n hooks/scripts/pre-compact-handover.sh`
- **All skills** — Run each `/quiver:*` slash invocation in a Claude Code session and verify the expected output/side-effects defined in its Test Plan.

## Known Gotchas

- The PreCompact hook pipes transcript + prompt to `claude -p` via stdin to avoid `ARG_MAX` limits -- do not refactor to use command-line arguments.
- Hook timeout is 180s (`hooks.json`), but the inner `claude -p` call has `timeout 150` -- the 30s gap prevents zombie processes.
- `ls -1r` in the prune loop relies on filenames being timestamps for correct sort order -- non-timestamp filenames break pruning.
- The hook silently exits 0 on any failure (missing transcript, empty claude output) -- check handover directory contents to verify it ran.
- Changing the timestamp format (`date '+%Y-%m-%d_%H-%M-%S'`) breaks lexicographic sort ordering of existing handover files.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Quiver

Composable development lifecycle plugin for AI coding CLIs. Expert tools for every development moment -- independently useful, optionally combined.
Dependencies: `bash`, `claude` CLI.

## Architecture

- **`.claude-plugin/`** — Plugin manifest (`plugin.json`) and marketplace listing (`marketplace.json`). Defines name, version, hook/skill/agent registration, and MCP servers.
- **`skills/`** — 25 skill directories (each contains `SKILL.md`). Each `SKILL.md` carries YAML front-matter (`name`, `description`) and is a self-contained prompt; the `name` field doubles as the slash invocation (`/handover`, `/review`, etc.). **Exception:** `visual-companion` also contains `server.py`, a runtime executable -- this is the only skill with non-prompt code.
- **`agents/`** — 20 agent definitions organized by category (`review/`, `research/`, `debug/`). Agents are persona prompts spawned as subagents.
- **`hooks/`** — `hooks.json` registers event hooks; `scripts/` holds implementations. Three hooks: PreToolUse (matcher `Bash`, classifies a command as deny/ask/silence before it runs), PreCompact (fires before context compaction, saves a handover) and SessionStart (emits the skill routing block from every skill's `when-to-use`).
- **`install.sh`** — Repo-root install script for the runtimes with no plugin manager. Its install targets are a six-column TSV heredoc inside `targets()`; adding a runtime is one row and no other line. It symlinks into the user's clone (so `git pull` is the update mechanism) and never removes or overwrites a path that is not a symlink resolving into the repo. It must stay at the repo root -- `.gitignore` drops `/scripts/`.
- **Storage** — Handover files are written to `<project>/.claude/handovers/`.
- **Rules** — `.claude/rules/` contains `skill-rules.md` (hard rules and learned lessons for skills, formerly `command-rules.md`), `review-agent-rules.md`, `cli-overlay-rules.md`, `agent-capability-rules.md`, and `readme-structure.md`.
- **External MCP** — Context7 MCP server (`plugin.json` > `mcpServers`) provides real-time library documentation lookups for review agents.

## System Behavior

- **Skills** — Markdown files executed by Claude Code. Shell blocks (`` !`…` ``) run inline and inject output into the prompt. Skills cannot call hook scripts directly; they duplicate save/prune logic as Claude instructions.
- **Hooks** — Bash scripts invoked by Claude Code on lifecycle events. The PreCompact hook reads `transcript_path` from stdin JSON (via `sed`), pipes the transcript to `claude -p` for summarization, and writes the result to the handovers directory. The PreToolUse hook reads `tool_name` and `tool_input.command` from the same stdin JSON, splits the command on shell separators, and classifies each segment by its first word; a match prints a `hookSpecificOutput` object with a `permissionDecision` of `deny` or `ask`, and everything else prints nothing.
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
6. Assign the agent a capability profile and effort tier, add it to the `## Assignments` table in `.claude/rules/agent-capability-rules.md`, and copy the profile's canonical `disallowedTools` string into the agent's frontmatter. `/quiver:create-agent` does this for you.
7. If the agent searches the broader codebase (beyond files it already knows about), reference the `code-navigation` skill and include the Code Navigation Strategy block from `skills/code-navigation/SKILL.md`. The dispatching skill must pass `lsp_available` context.
8. If the agent will be dispatched by `/quiver:review` (anything under `agents/review/` or any cross-category agent listed in `skills/review/SKILL.md` Step 2a Tier 2), follow the hard rules in `.claude/rules/review-agent-rules.md`. In particular, every review agent must carry the hypothetical-language ban rule (canonical text, or a domain-specific exemption variant for adversarial agents like `stress-tester` and `security-audit`).
9. If the agent is a `/quiver:review` Step 2 participant, give it a row in the `## Dispatch Gates` table in `.claude/rules/review-agent-rules.md` and restate that row in `skills/review/SKILL.md` Step 2b. The split is the one the skill's "Adding future agents" block already draws: review-scoped agents under `agents/review/` are discovered automatically and always need the row, while a cross-category agent needs it only when you also add its path to the Tier 2 list in Step 2a. Agents outside that set -- `agents/debug/`, `agents/workflow/`, and any research agent not on the Tier 2 list -- take no row, and `tests/skills/test-review-dispatch-contract.sh` fails on a row naming an agent `/quiver:review` never dispatches exactly as it fails on a participant with no row.

### Adding or Modifying a Hook

1. Register the event in `hooks/hooks.json` with `"type": "command"` (the only supported hook type).
2. Place the script in `hooks/scripts/`. Use `$CLAUDE_PROJECT_DIR` (falls back to `pwd`) for the project root.
3. `$CLAUDE_PLUGIN_ROOT` is available in `hooks.json` and hook scripts.

### Invariants

- **Retention policy** — Exactly the 3 most recent `.md` files in `.claude/handovers/` are kept. Both the handover skill and hook implement pruning independently.
- **Timestamp format** — Filenames use `date '+%Y-%m-%d_%H-%M-%S'`. This format is lexicographically sortable.

## Testing

- **All tests** -- `bash tests/run-all.sh` runs every `tests/**/test-*.sh` and exits nonzero if any failed. `.github/workflows/tests.yml` runs it on every pull request and on every push to `master`. A failing test does not stop the run, so one invocation reports every contract that drifted.
- **Adding a test** -- put it at `tests/<area>/test-<name>.sh`; `run-all.sh` discovers it with no edit. The contract is the one all existing tests honor: runnable under `bash` from any working directory, exit 0 on pass and nonzero on fail. A shared helper must not match `test-*.sh` -- name it `lib-*.sh`.
- **Skills** — Run the slash invocation in a Claude Code session and follow the `## Test Plan` section embedded in each `SKILL.md`.
- **Hook** — Pipe test JSON to the script:
  ```bash
  echo '{"transcript_path":"/path/to/transcript.json"}' | bash hooks/scripts/pre-compact-handover.sh
  ```
- **Agent capability contract** — `bash tests/agents/test-capability-profile-contract.sh` checks every agent's `disallowedTools` and `effort` frontmatter against the profiles and assignments in `.claude/rules/agent-capability-rules.md`, and fails when a copy drifts, an agent is missing from the table, or a table row has no file.
- **Destructive command guard** — `bash tests/hooks/test-destructive-guard.sh` feeds real PreToolUse payloads to `hooks/scripts/pre-tool-use-guard.sh` and asserts the decision each one should produce, including the cases that must stay silent. Beyond the tier, it asserts the reason text (an empty or wrong target makes the prompt worthless), byte-exact silence rather than trimmed silence, that a target carrying quotes still emits parseable JSON, and that a 1000-target delete stays inside the 5s timeout in `hooks/hooks.json`.
- **Review dispatch contract** -- `bash tests/skills/test-review-dispatch-contract.sh` binds the canonical `## Dispatch Gates` table in `.claude/rules/review-agent-rules.md` to its runtime copy: the Step 2b prose in `skills/review/SKILL.md`. It fails when that copy's class list or mode list drifts from the canonical row, when a file under `agents/review/` or either Tier 2 research agent has no row, and when a canonical row names no agent file in dispatch scope.
- **Install script** -- `bash tests/install/test-install-script.sh` runs `install.sh` under a throwaway `HOME` from `mktemp -d` and asserts the symlink is created, a second run changes nothing, a real directory at a destination is skipped with the run exiting nonzero, `--uninstall` removes only links resolving into the repo, `XDG_CONFIG_HOME` relocates the OpenCode destination, and every target row has exactly six tab-separated columns. That last assertion is what catches an editor turning the table's tabs into spaces.
- **Manifest parity** -- `bash tests/manifests/test-manifest-parity.sh` binds `.claude-plugin`, `.cursor-plugin`, and `.codex-plugin` to one version string, asserts the Cursor `agents` array equals the Claude one and that Claude registers every file under `agents/`, and checks the README version badge. `gemini-extension.json` is deliberately out of scope; Gemini CLI was retired 2026-06-18. `scripts/release.sh` applies the bump, this test enforces it -- the helper is gitignored and cannot be the gate.
- **Syntax check** — `bash -n hooks/scripts/pre-compact-handover.sh` and `bash -n hooks/scripts/pre-tool-use-guard.sh`
- **All skills** — Run each `/quiver:*` slash invocation in a Claude Code session and verify the expected output/side-effects defined in its Test Plan.

## Known Gotchas

- The PreCompact hook pipes transcript + prompt to `claude -p` via stdin to avoid `ARG_MAX` limits -- do not refactor to use command-line arguments.
- Hook timeout is 180s (`hooks.json`), but the inner `claude -p` call has `timeout 150` -- the 30s gap prevents zombie processes.
- `ls -1r` in the prune loop relies on filenames being timestamps for correct sort order -- non-timestamp filenames break pruning.
- The hook silently exits 0 on any failure (missing transcript, empty claude output) -- check handover directory contents to verify it ran.
- Changing the timestamp format (`date '+%Y-%m-%d_%H-%M-%S'`) breaks lexicographic sort ordering of existing handover files.
- The PreToolUse guard is an accident brake, not a security boundary. It reads the literal command string before the shell ever sees it, so shell escapes, variable expansion, aliases, base64, and any deliberate obfuscation are outside its threat model by construction. It exists to catch a slip, and a determined bypass is not a bug in it. This bullet is the one home for that fact; `hooks/scripts/pre-tool-use-guard.sh` points here rather than repeating it.
- Three invariants inside the guard are documented at the code that depends on them rather than restated here: first-word segment anchoring (the Segmentation block), `set -uf` without `set -e` (the file header), and masking JSON escapes before extracting the command (above `json_field`). Read those comments before editing the classifier -- none of the three survives a "simplify this" pass that has not read them, and the first two each protect against a specific defect this repository has already shipped once.
- The guard stops classifying at the first heredoc or herestring opener, and drops any double-quoted span that contains a newline, before it segments. Both are text being written rather than commands being run, and the first-word anchoring cannot tell them apart once a newline is a separator -- `cat <<EOF > notes.md` followed by a line reading `rm -rf /` is a documentation edit. The concession is one-directional on purpose: it costs a missed prompt for anything destructive that follows a heredoc in the same command, and it removes a wrong `deny`, which is the one decision a user cannot override.
- Lesson LO3 in `.claude/rules/cli-overlay-rules.md` says to prefer no automatic hook over a frequently-firing one with a fragile guard. The PreToolUse guard fires more often than the `Stop` hook that lesson killed and is still the right call: the killed hook ran `claude -p` on every fire behind a cooldown that only reset on success, while this one is `sed` plus `tr`, holds no state, has no cooldown to be fragile, and exits 0 on every path. LO3 constrains expensive hooks with stateful guards, not cheap stateless ones.
- Cursor needs no Quiver install of its own when Claude Code has one. It discovers skills by scanning a fixed root list -- `.cursor/skills/`, `.cursor/skills-cursor/`, `.cursor/cloud-skills/`, `.cursor/plugins/`, `.claude/skills/`, `.claude/plugins/`, `.codex/skills/`, `.agents/skills/` -- hardcoded in the app bundle with no setting to disable it. A Claude Code install lands in `~/.claude/plugins/` and is therefore visible in Cursor; a Codex install lands in `~/.codex/plugins/`, which is NOT on that list, so it is not. A symlink under `~/.cursor/plugins/local/` is NOT picked up: measured on Cursor 3.17.21 by disabling the Claude Code install and watching Quiver vanish from Cursor while that symlink was still in place. `install.sh` therefore has no cursor row. `.cursor-plugin/plugin.json` still matters, because Cursor's own plugin import (git URL or local repo) reads it -- that is the path for a Cursor-only user.
- `hooks/hooks.json` ships to Cursor as well (`.cursor-plugin/plugin.json` sets `"hooks": "./hooks/hooks.json"`), so Cursor receives the PreToolUse block whether or not it implements `permissionDecision`. Codex and Gemini have no `hooks` key in their manifests and are unaffected.
- `claude plugin validate ./ --strict` fails in plugin-manifest mode (the mode chosen when `.claude-plugin/marketplace.json` is absent) on a warning that `CLAUDE.md` at the plugin root is not loaded as project context. This predates the guard -- it reproduces on `master` at `6f74e11` -- and marketplace-manifest mode, which is how the plugin actually ships, passes clean.

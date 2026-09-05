# AGENTS.md

Read `CONTRIBUTING.md` before changing anything. `CLAUDE.md` has the architecture and the per-component rules.

## Must-follow constraints

- Branching: Create a feature branch for any non-trivial change. If already on the correct branch, keep using it -- do not create additional branches or worktrees unless explicitly requested.
- Safety: Do not delete or overwrite user data. Avoid destructive commands.
- Tests: Run `bash tests/run-all.sh` before you finish. Most tests are contract checks between two copies of one string; a red test points at the copy you have not updated. Fix the copy, not the test.
- ASCII-first: Use ASCII characters only unless the file already contains Unicode.
- Release: Plugin version lives in `.claude-plugin/plugin.json` `"version"` field. Release is handled by a private project command -- do not bump version, create tags, or publish releases manually.

## Important locations

- `.claude-plugin/plugin.json` -- Plugin manifest (name, version, skill/agent registration).
- `.claude-plugin/marketplace.json` -- Marketplace listing metadata (keywords, tags, category).
- `hooks/hooks.json` -- Hook event registration: PreToolUse (`pre-tool-use-guard.sh`, classifies a Bash command as deny/ask/silence), PreCompact (`pre-compact-handover.sh`, saves a handover), SessionStart (`session-start-auto-dispatch.sh`, emits the skill routing block).
- `hooks/scripts/pre-compact-handover.sh` -- PreCompact hook implementation; uses `claude -p` for summarization.
- `skills/handover/SKILL.md` -- the 8 handover headings sit under a `SYNC:` comment that points at the hook script.
- `hooks/scripts/pre-compact-handover.sh` -- the same 8 headings inside `PROMPT_PREFIX`, under a `SYNC:` comment that points back. `tests/hooks/test-handover-sync-contract.sh` fails when the two lists differ.

## Change safety rules

- Changing the timestamp format breaks lexicographic sort ordering of existing handover files.

## Known gotchas

- The PreCompact hook pipes transcript + prompt to `claude -p` via stdin to avoid `ARG_MAX` limits -- do not refactor to use command-line arguments.
- Hook timeout is 180 seconds (`hooks.json`), but the inner `claude -p` call has a `timeout 150` -- the 30-second gap prevents zombie processes.
- `ls -1r` in the prune loop relies on filenames being timestamps for correct sort order -- non-timestamp filenames will break pruning.
- The hook silently exits 0 on any failure (missing transcript, empty claude output) -- check handover directory contents to verify it actually ran.

# AGENTS.md

## Must-follow constraints

- Branching: Create a feature branch for any non-trivial change. If already on the correct branch, keep using it -- do not create additional branches or worktrees unless explicitly requested.
- Safety: Do not delete or overwrite user data. Avoid destructive commands.
- ASCII-first: Use ASCII characters only unless the file already contains Unicode.
- Release: Plugin version lives in `.claude-plugin/plugin.json` `"version"` field. Release is handled by a private project command -- do not bump version, create tags, or publish releases manually.

## Important locations

- `.claude-plugin/plugin.json` -- Plugin manifest (name, version, skill/agent registration).
- `.claude-plugin/marketplace.json` -- Marketplace listing metadata (keywords, tags, category).
- `hooks/hooks.json` -- Hook event registration (currently only PreCompact).
- `hooks/scripts/pre-compact-handover.sh` -- PreCompact hook implementation; uses `claude -p` for summarization.
- `skills/handover/SKILL.md:96` -- SYNC comment pointing to hook script headings; the 8 headings live at lines 99-129.
- `hooks/scripts/pre-compact-handover.sh:25` -- SYNC comment pointing to handover skill headings.

## Change safety rules

- Changing the timestamp format breaks lexicographic sort ordering of existing handover files.

## Known gotchas

- The PreCompact hook pipes transcript + prompt to `claude -p` via stdin to avoid `ARG_MAX` limits -- do not refactor to use command-line arguments.
- Hook timeout is 180 seconds (`hooks.json`), but the inner `claude -p` call has a `timeout 150` -- the 30-second gap prevents zombie processes.
- `ls -1r` in the prune loop relies on filenames being timestamps for correct sort order -- non-timestamp filenames will break pruning.
- The hook silently exits 0 on any failure (missing transcript, empty claude output) -- check handover directory contents to verify it actually ran.

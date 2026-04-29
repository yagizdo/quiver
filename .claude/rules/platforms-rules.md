# Platform Overlay Rules

Hard rules and learned lessons for branches that add a new CLI platform overlay (e.g., `feat/cursor`, `feat/gemini-cli`, `feat/codex-cli`, `feat/antigravity`). These rules lock the architecture invariants and the layout decisions made on the first overlay branch (`feat/cursor`, 2026-04-29) so subsequent overlay branches stay consistent.

For command authoring rules, see `command-rules.md`. For review-agent rules, see `review-agent-rules.md`.

---

## Hard Rules

Non-negotiable. Every platform-overlay branch must follow all of these. Violations break the source-of-truth invariant and force duplication.

**PR1. Diff scope.** The PR diff for `feat/<cli>` may modify only paths under `platforms/<cli>/`, the CLI's manifest dir at the repo root if applicable (e.g., `.cursor-plugin/`), `README.md`, and -- on the first overlay branch only -- `.claude/rules/platforms-rules.md`. Any other modification is a violation. Verified by `git diff --name-only master...HEAD`.

**PR2. Source-of-truth invariant.** `commands/`, `agents/`, `skills/`, `.claude-plugin/plugin.json`, and `hooks/` are byte-identical across all CLI branches. Never modify, never duplicate. Verified by `git diff --stat master...HEAD -- commands/ agents/ skills/ hooks/ .claude-plugin/`.

**PR3. Dependency direction.** `platforms/<cli>/` and the CLI's manifest dir reference the canonical sources (commands, agents, skills, hooks). The reverse is forbidden -- no `requires:`, `platforms:`, or `cli:` field in canonical frontmatter; no conditional branches in command bodies based on detected CLI. Verified by `grep -rn 'platforms/' commands/ agents/ skills/ hooks/`.

**PR4. Per-CLI docs location.** The per-CLI install/usage doc lives at `platforms/<cli>/README.md`. Never under `docs/` (gitignored per `.gitignore:54`). The repo `README.md` links to it from the `## Other CLIs` section.

**PR5. Manifest location.** If a CLI's plugin system requires a manifest at the repo root, the manifest dir is named `.<cli>-plugin/` (sibling of `.claude-plugin/`). The plan owns this decision per CLI; document the reason in `platforms/<cli>/install.md`.

**PR6. Polyfill bodies are per-CLI, not shared.** Until at least 3 of 4 CLIs ship near-identical polyfills for the same primitive, do not extract a `_shared/` directory. (YAGNI; matches spec's stance.)

**PR7. Compatibility matrix is hand-maintained in the README.** No auto-generation, no separate matrix file. Per-CLI `primitives.md` is the contract; the README matrix is the summary.

**PR8. Branch hygiene.** Each CLI branch is based on `master` (not on a long-lived integration branch). Sequential merges only. Lessons propagate via spec/rules edits, not branch ordering.

---

## Learned Lessons

Each lesson comes from a real decision or failure on a previous overlay branch. Add new entries when issues are discovered.

**LP1. Prefer rule-files or context-injection over forking commands.**
Cursor 2.5+ does not auto-execute Claude Code's inline `` !`<command>` `` shell blocks. The first instinct was to fork command files into `platforms/cursor/commands/` so the forks could be rewritten for Cursor. This was rejected because it violates PR2 -- every fix to a canonical command would need to be mirrored into N forks, and drift would be inevitable. The accepted solution: ship a Cursor rule file (`platforms/cursor/rules/quiver-shell-blocks.mdc`, `alwaysApply: true`) that tells the Cursor agent to read `` !`<command>` `` blocks as instructions and execute them via the `Shell` tool. When facing a similar "commands assume harness behavior X" gap on Gemini, Codex, or Antigravity, prefer rule-file or context-injection mechanisms over duplication. Cite: `docs/brainstorms/2026-04-29-multi-cli-platform-overlays.md` and `.claude/plans/2026-04-29-feat-cursor-platform-overlay-plan.md` (Phase 3 Task 8).

# CLI Overlay Rules

Hard rules and learned lessons for branches that add or modify a CLI overlay (Cursor, future Gemini CLI, future Codex CLI, etc.). These rules lock the architecture invariants of the flattened overlay layout.

For command authoring rules, see `command-rules.md`. For review-agent rules, see `review-agent-rules.md`.

---

## Hard Rules

Non-negotiable. Every CLI overlay branch must follow all of these. Violations break the source-of-truth invariant or force duplication.

**OR1. Source-of-truth invariant.** `commands/`, `agents/`, `skills/`, `hooks/`, and `.claude-plugin/plugin.json` are byte-identical regardless of which CLIs are supported. CLI overlay work must never modify these. Verified by `git diff --stat master...HEAD -- commands/ agents/ skills/ hooks/ .claude-plugin/`.

**OR2. Dependency direction.** A CLI's manifest dir or root manifest file references the canonical sources (commands, agents, skills, hooks). The reverse is forbidden: no `requires:`, `platforms:`, or `cli:` field in canonical frontmatter; no conditional branches in command bodies based on the running CLI. Verified by `grep -rn '\.cursor-plugin\|\.codex-plugin\|gemini-extension' commands agents skills hooks` returning no matches.

**OR3. Each CLI has one home.** Cursor's overlay lives entirely inside `.cursor-plugin/`. Future overlays live inside their CLI's native manifest location at the repo root: `.codex-plugin/`, `gemini-extension.json` (single-file manifest), and so on. There is no `platforms/<cli>/` parallel home. CLI-specific files (rule files, per-CLI hook variants, per-CLI shims) live next to that CLI's manifest.

**OR4. Shared assets live at the repo root.** Logo files, icons, and other shared graphical assets live in `assets/` at the repo root. Each CLI's manifest references its own assets by repo-root-relative path. No per-CLI asset folders.

**OR5. Scaffolding-on-demand.** CLI-specific abstractions are created only when a concrete consumer in the canonical content needs them, not in advance. Specifically:
- **Tool-name maps:** when a skill genuinely fans out to multiple CLIs with different tool names, ship a per-skill `references/<cli>-tools.md` next to that skill. Do not maintain a global per-CLI tool map.
- **Degraded-mode behavior:** when a command needs a fallback because a CLI lacks a primitive (e.g. `AskUserQuestion`), inline the fallback in the command body. Do not create a separate polyfill file.
- **Hook variants:** when a CLI's hook contract genuinely differs from `hooks/hooks.json`, ship a parallel `hooks/hooks-<cli>.json` and reference it from that CLI's manifest. Do not modify the canonical hooks file.

**OR6. Branch hygiene.** Each CLI overlay branch is based on `master` (not on a long-lived integration branch). Sequential merges only.

---

## Learned Lessons

Each lesson comes from a real decision or failure on a previous overlay branch. Add new entries when issues surface.

**LO1. Prefer rule-files or context-injection over forking commands.**
Cursor 2.5+ does not auto-execute Claude Code's inline `` !`<command>` `` shell blocks. The first instinct was to fork command files into a parallel directory so the forks could be rewritten for Cursor. That was rejected because it violates OR1 -- every fix to a canonical command would need to be mirrored into N forks, and drift would be inevitable. The accepted solution: ship a Cursor rule file (`.cursor-plugin/rules/quiver-shell-blocks.mdc`, `alwaysApply: true`) that tells the Cursor agent to read those blocks as instructions and execute them via the `Shell` tool. When facing a similar "the CLI does not implement Claude Code behavior X" gap on a future CLI, prefer rule files or context-injection mechanisms (rules/, context files like `GEMINI.md`) over command duplication.

**LO2. Delete unused scaffolding rather than carrying it forward.**
The first overlay branch shipped `platforms/cursor/{primitives,tool-map,polyfills/}` as forward-looking documentation for abstractions that no command, agent, or skill exercised. Carrying the empty scaffolding forward created the worst of both worlds: documentation no consumer honored, and structure no skill referenced. The flatten refactor (this branch) removed it. Lesson: when reviewing an overlay before merge, audit each file for a current consumer; if none exists, delete and resurrect later when a real need surfaces.

# Skill Rules

Hard rules and learned lessons for writing Quiver skills. Updated whenever a new issue is discovered.

> **Note:** This file was previously `command-rules.md`. After the commands-to-skills migration, skills are the universal primitive that backs every Quiver slash invocation. The rules apply unchanged; older lesson text that mentions "command" should be read as "skill". The R-numbered hard rules and L-numbered lessons keep their identifiers so prior pull requests, agent files, and review reports that cite them still resolve.

For structural patterns (role framing, decision trees, output format), read existing skills as examples -- `skills/review/SKILL.md`, `skills/work/SKILL.md`, `skills/commit/SKILL.md`. Adapt to the new skill's purpose, don't copy mechanically.

---

## Hard Rules

Non-negotiable. Every command must follow all of these. Violations break things.

**R1. Frontmatter required.** YAML frontmatter with `name` + `description`. `name` must match filename without `.md`. Enables prefix-free access (`/handover` not `/quiver:handover`).

**R2. Shell blocks exit 0.** Even when targets don't exist. Use `2>/dev/null || echo "NOT_FOUND: <path>"` or `|| echo "NO_GIT"`. Non-zero exit causes Claude Code to report shell failure before prompt logic runs.

**R3. No shell logic.** No `$()` substitution, variable assignment, `if/else`, or logic-bearing pipes in `!` blocks. Claude Code blocks these in marketplace plugins.

**R4. No `CLAUDE_PLUGIN_ROOT`.** Unavailable in command markdown files (only available in hooks).

**R5. User decisions via `AskUserQuestion`.** Use action buttons, not plain text questions. Plain text loses button UI and degrades user experience.

**R6. Confirm before destructive ops.** `rm`, file overwrite, `git push` require explicit user confirmation via `AskUserQuestion` before execution.

**R7. Silent decision logic.** Don't show "Branch B selected" or mode labels to the user. Internal routing is implementation detail.

**R8. ASCII-only.** No Unicode characters or emoji in command files and output templates. Project-wide constraint unless the file already contains Unicode.

**R9. No AI attribution.** No `Co-authored-by` or similar in commits/PRs unless the user explicitly requests it.

**R10. `when-to-use:` required for user-facing skills.** Every user-facing skill must include a `when-to-use:` field in its YAML frontmatter. The value must be a single-line double-quoted string (not a multi-line YAML block scalar -- multi-line format produces empty routing entries in the hook). The string must contain: the skill's slash command name as an anchor (e.g. `'/plan'`), at least one concrete quoted user utterance, and the abstract intent category. Exceptions: internal reference skills (code-navigation, verification, tdd). An exempt skill must omit the field entirely, not carry an unused one -- the SessionStart routing hook tells the model to invoke a matching skill silently before it responds, and a reference skill is not a thing the model invokes. There is no destructive-skill exemption: a destructive operation lives inside a skill carrying `disable-model-invocation: true`, behind an `AskUserQuestion` confirmation, as `/handover --clear` does. Such a skill is not exempt and keeps its `when-to-use:` in the format above -- it is still slash-invocable -- but the routing hook drops it from the block, because the model is not allowed to invoke it and an entry for one instructs the model to do something impossible. That drop, not an exemption, is what keeps a destructive path unreachable by silent auto-invocation. Verified by `bash tests/skills/test-when-to-use-contract.sh`.

**R11. Read the skill you name.** A skill or agent that invokes, delegates to, reads the output of, or describes the behavior of another skill, agent, or hook opens that file first and rests every such sentence on a line it read -- the frontmatter flag (`disable-model-invocation`, `user-invocable`, `disallowedTools`), the phase that writes the file being read, the path that carries the promise. The same holds for anything outside the plugin: a claim about a Claude Code feature, a harness rule, or a tool flag is checked against the docs (the `claude-code-guide` agent) or measured in-session before it lands, never written from a memory of how it probably works. The `/ship` rewrite on PR #69 (2026-09-11) asserted four things its neighbors contradict -- a Skill-tool call to `review`, which carries `disable-model-invocation: true` and is refused; a mandatory `**Provides:**` line that `/plan` Check 8 forbids when no symbol crosses tasks; an open-finding count re-read from a report `/work` never edits; a "third failed attempt is accepted" promise `/work` kept only on its 1-2 task path -- and every one read as plausible because it described what the neighbor should do. A claim about a file that was not opened is a defect the review finds; the writer finds it first by reading, and quotes the line in the same edit when the claim is load-bearing.

**R12. User-facing questions are plain language.** Every `AskUserQuestion` question, button label, and option description is written for someone who has never read the skill file. No internal field names (`verify_gate`, `plan_write`), no plugin vocabulary (gate, verdict, manifest, dispatch, fan-out), no rule codes. Each option carries a one-line description saying what happens when it is picked -- `description` is a required field on every option, so the choice is either explained deliberately or filled in by guesswork, and on a CLI that renders the call as plain text instead of buttons that line is the only thing the user has to go on. R7 bans leaking internal routing; R12 bans leaking internal vocabulary. `skills/review/SKILL.md`'s "Status Messages: Plain Language Required" section is this rule worked out for one skill, ban list included; the list is review-specific, the shape is not. The same applies to the status lines a skill prints: a summary column reading `Gate` is the same defect as a button reading `No gate`.

---

## Learned Lessons

Each lesson comes from a real failure. Add new entries when issues are discovered.

**L1. Non-git CLI tools break with `||` in shell blocks.**
`gh auth status 2>/dev/null || echo "NO_GH"` fails in marketplace sandbox. The permission parser splits `||` and evaluates each part independently. `git` commands are pre-approved, but `gh`, `curl`, `jq` are not.
*Prevention:* For non-git tools, use `2>&1` redirection only. Detect errors from output text in prompt logic. Never use `||`, `&&`, `;` with non-git commands in `!` blocks.

**L2. Step 0 git check must define fallback behavior.**
Commands that depend on git but don't check for it fail silently or crash in non-git directories.
*Prevention:* Every git-dependent command starts with `NO_GIT` check. Explicitly state what happens: "Stop here" (for git-required commands like `commit`) or "degrade gracefully" (for commands like `handover` that can work without git).

**L3. Verify after every file write/delete.**
Without verification, Claude assumes success. Silent write failures corrupt handover state, plans, or reports.
*Prevention:* After every `Write`, `Edit`, or `rm`: read back the file (or re-list the directory) to confirm the operation succeeded. All existing commands do this -- new commands must too.

**L4. Output placeholders left unfilled.**
Claude sometimes outputs `{placeholder}` text verbatim instead of filling it with real values.
*Prevention:* Verification step should confirm no raw `{...}` placeholder text remains in user-facing output.

**L5. Anti-patterns must come from observed LLM failures.**
Theoretical "don't" lists don't prevent real mistakes. Effective anti-patterns describe what Claude actually does wrong and why.
*Prevention:* Each anti-pattern entry should state the bad behavior AND why it happens. Add new anti-patterns only when a real failure is observed.

**L6. Cross-command references only when logical.**
Old template forced `**Tip:** /quiver:x` lines on every command. Most were irrelevant and cluttered output.
*Prevention:* Only add cross-command tips when the referenced command is a genuine next step in the user's workflow. If the command is self-contained, no tip needed.

**L7. Multiple `AskUserQuestion` calls need independent flow control.**
When a command has multiple user decision points, each must have its own stop/continue logic. "Asked but didn't use the answer" is a bug.
*Prevention:* Each `AskUserQuestion` call must handle all its options (including Cancel) with explicit routing. No dangling decision points.

**L8. Thorough first pass, not incremental discovery.**
Shallow audits that miss issues force multiple "check again" rounds.
*Prevention:* When a command performs any audit or validation (quality gates, verification), trace every data flow path end-to-end in one pass. Don't declare done until all categories are checked.

**L9. Rules are mandatory, patterns are not.**
Hard rules (this document) must be followed. But command structure (role framing format, decision tree layout, output template style) is not prescribed.
*Prevention:* Learn structure from existing good commands. Read `review.md`, `work.md`, `commit.md` for examples. Don't copy them mechanically -- adapt to the new command's purpose.

**L10. Documenting the shell-block syntax inside a skill body executes it.**
The loader scans a SKILL.md body for a `!` immediately followed by a backtick-delimited span and runs that span through the shell before any step logic. Markdown nesting does not protect it -- a double-backtick inline code span wrapped around an example is invisible to that scanner. `skills/design-fix/SKILL.md` shipped in v1.24.0 with a gotcha line reading "this skill carries no `` !`...` `` shell blocks on purpose", and loading `/design-fix` aborted before Step 0 with `command not found: ...`. `/design` failed identically because it routes into the same file. The line looks like correct markdown and reads as documentation, so nothing about it flags on review.
*Prevention:* Write the mention as `!` -- a backtick immediately before the bang, the form `skills/handover/SKILL.md` and `skills/ship/SKILL.md` already use -- or keep the example out of the skill body. Verified by `bash tests/skills/test-shell-block-syntax.sh`, which is also the only thing that catches the mixed shape: one line carrying a safe mention and an executable one.

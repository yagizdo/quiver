# Quiver Opencode Compatibility Rules

These rules apply when running Quiver commands (`/commandname`) or agents (`@agentname`)
inside Opencode. They explain how to handle Claude Code-specific primitives that have
no direct equivalent in Opencode.

## 1. AskUserQuestion (interactive choice buttons)

`AskUserQuestion` is a Claude Code tool. Opencode does not have it.

**Replacement:** When a command needs a user decision, present the choices as a numbered
plain-text list and wait for the user to type their selection number.

Example -- instead of an interactive button prompt:
```
Choose an option:
1. Execute this plan
2. Create a new branch
3. Done -- I'll handle the rest
```
Then wait for the user to respond with a number before proceeding.

## 2. Agent tool (subagent dispatch)

The `Agent` tool for spawning subagents is Claude Code-specific.

**Replacement:** Use `@agentname` mentions to invoke a specialist agent as a subagent.
For example, where a command says "dispatch the `senior-reviewer` agent", use
`@senior-reviewer` in your message. Available agents are listed in `.opencode/agents/`.

Note: Multi-agent orchestration commands (`/review`, `/plan`) use `Agent` tool dispatch
internally. These commands load and run in Opencode, but subagent dispatch relies on
Opencode's `@agent` mention behavior instead of parallel Claude Code subagents.

## 3. Shell injection blocks

Inline shell blocks (`` !`command` ``) work identically in Opencode. No adaptation needed.

## 4. Frontmatter fields (when-to-use, name)

`when-to-use:` and `name:` frontmatter fields in command files are Claude Code-specific
routing metadata. Opencode ignores them. No action needed -- they are harmless.

## 5. Handover file paths

Handover files write to `.claude/handovers/` relative to the project root. This path is
unchanged in Opencode since it is relative to the project root, not the CLI install path.

## 6. Session hooks (PreCompact, SessionStart)

PreCompact and SessionStart hooks do not fire in Opencode. They are Claude Code lifecycle
events. Consequence: automatic handover creation on context compaction does not happen.

**Replacement:** Trigger handover creation manually by invoking `/handover` at natural
breakpoints or before ending a session.

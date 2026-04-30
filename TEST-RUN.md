# commands-to-skills Refactor — Test Run

This file is one-time merge evidence for the `refactor/commands-to-skills` branch. The user fills it in during the merge-gate session-restart test (Plan T28), then either commits it to the PR or pastes its contents into the PR description before merging. Delete after merge.

## Setup

1. Restart Claude Code (so the new `skills/` directory is watched fresh and the old `commands/` mappings are dropped).
2. Open a session in this repository.
3. For each skill below, run the listed slash invocation and walk through the Test Plan section embedded in the corresponding `skills/<name>/SKILL.md` file. Mark the result.

## Results

Legend: `[ ] PENDING`, `[x] PASS`, `[!] FAIL` (note details), `[~] PARTIAL`.

| # | Skill | Slash invocation | Result | Notes |
|---|-------|-----------------|--------|-------|
| 1 | handover | `/handover` | [ ] | |
| 2 | load-handover | `/load-handover` | [ ] | |
| 3 | delete-last-handover | `/delete-last-handover` | [ ] | |
| 4 | delete-all-handovers | `/delete-all-handovers` | [ ] | |
| 5 | brainstorm | `/brainstorm <idea>` | [ ] | |
| 6 | plan | `/plan <task>` | [ ] | |
| 7 | work | `/work [path-or-name]` | [ ] | |
| 8 | review | `/review` (and `/review --with-codex` if codex CLI installed) | [ ] | |
| 9 | commit | `/commit` | [ ] | |
| 10 | create-pr | `/create-pr` | [ ] | |
| 11 | create-agent | `/create-agent <description>` | [ ] | |
| 12 | create-agents-md | `/create-agents-md` | [ ] | |
| 13 | repair-skill | `/repair-skill` | [ ] | |
| 14 | code-navigation | reference (loaded via Skill tool, no slash) | [ ] | |
| 15 | orchestrate-agents | reference (loaded via Skill tool, no slash) | [ ] | |
| 16 | visual-companion | reference (used by /brainstorm Step 1.5) | [ ] | |

## Platform-bug verification

| Bug | Check | Result | Notes |
|-----|-------|--------|-------|
| Claude Code issue #22345 — `disable-model-invocation: true` may be silently ignored on plugin-distributed skills | Inspect `/permissions` or watch token usage; if the flag is honored, slash-only skills are not auto-invoked by the model. Acceptable if not honored on this version (cost ~4.4K tokens/request). | [ ] | |
| Cursor forum 155748 (Cursor 2.6.20) — plugin-distributed skills with `disable-model-invocation: true` may be hidden from `/` palette | Open Cursor 2.6+ session, type `/` and confirm all 13 user-facing skills are listed. If hidden, contingency: strip the flag from affected skills and document. | [ ] | |

## Acceptance criteria signoff

- [ ] AC1 — Every previously-existing slash command is invocable on Claude Code with identical behavior.
- [ ] AC2 — `commands/` directory does not exist at HEAD.
- [ ] AC3 — `skills/` contains exactly 16 directories.
- [ ] AC4 — Both plugin manifests no longer contain a `commands` field.
- [ ] AC5 — Every migrated skill contains a `## Test Plan` section.
- [ ] AC6 — All 16 test plans pass on Claude Code.
- [ ] AC7 — PreCompact hook fires correctly.
- [ ] AC8 — Both SYNC contracts (handover-hook, review-report) updated and bodies still match.
- [ ] AC9 — OR1 in `cli-overlay-rules.md` no longer enumerates `commands/`.
- [ ] AC10 — `.claude/rules/command-rules.md` renamed to `skill-rules.md` and referrers updated.
- [ ] AC11 — Cursor smoke-test (post-merge): all 13 migrated skills appear in Cursor's `/` palette.

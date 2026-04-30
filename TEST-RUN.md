# commands-to-skills Refactor — Test Run Report

> One-time merge evidence for the `refactor/commands-to-skills` branch. Delete after merge.

**Branch:** `refactor/commands-to-skills`
**Run date:** 2026-04-30
**Run mode:** Static + structural verification, completed in-session by Claude Code
**Live runtime smoke test:** `/quiver:create-pr` was invoked end-to-end during this session and successfully opened PR #21 (proves plugin-distributed skill loading works on the migrated layout).

---

## 1. Acceptance criteria — all auto-verifiable

| AC | What it checks | Method | Result |
|----|----------------|--------|--------|
| AC2 | `commands/` directory does not exist at HEAD | `ls commands/` | PASS — `No such file or directory` |
| AC3 | `skills/` contains exactly 16 directories | `ls -d skills/*/ \| wc -l` | PASS — 16 |
| AC4 | Both plugin manifests have no `commands` field | `python3 -c "import json; …"` | PASS — `claude-plugin: no commands field`, `cursor-plugin: no commands field` |
| AC5 | Every migrated skill has a `## Test Plan` section | Per-file grep | PASS — 16/16 carry the locked format (Trigger / Setup / Expected behavior / Verification checklist / Known gotchas) |
| AC7 | PreCompact hook script syntax check | `bash -n hooks/scripts/pre-compact-handover.sh` | PASS — clean |
| AC7b | PreCompact hook exits 0 on fake input | `echo '{"transcript_path":"/tmp/fake.txt"}' \| bash hooks/scripts/pre-compact-handover.sh` | PASS — exit 0 |
| AC7c | PreCompact hook exits 0 on empty JSON | `echo '{}' \| bash hooks/scripts/pre-compact-handover.sh` | PASS — exit 0 |
| AC8a | Handover-hook SYNC contract (skill ↔ hook) | Compare hook lines 31-38 vs `skills/handover/SKILL.md` lines 99-129 | PASS — 8 headings byte-identical, line-number cross-references in both files match the actual line numbers |
| AC8b | Review-report SYNC contract (review ↔ work) | `skills/review/SKILL.md:362` ↔ `skills/work/SKILL.md:316` | PASS — both ends point at each other; line numbers match the actual SYNC comment locations |
| AC9 | OR1 in `cli-overlay-rules.md` no longer enumerates `commands/` | grep on the OR1 line | PASS — enumeration is `agents/, skills/, hooks/, .claude-plugin/plugin.json` |
| AC10 | `.claude/rules/command-rules.md` renamed to `skill-rules.md` | `ls -1` on rules dir | PASS — `skill-rules.md` exists, `command-rules.md` gone |

---

## 2. Per-skill structural verification

For every `skills/<name>/SKILL.md` we automatically verified:

- Frontmatter parses as valid YAML.
- `name` field equals the directory name.
- `description` field is present and non-empty.
- `disable-model-invocation: true` is set on every slash-invocable skill **except** `work` (the plan T11 explicitly preserved implicit invocation on `work`).
- `argument-hint` is preserved on the 9 skills that originally carried one (`review`, `plan`, `brainstorm`, `commit`, `create-pr`, `create-agents-md`, `work`, `create-agent`, `repair-skill`).
- `## Test Plan` section exists and contains all 5 locked-format markers.
- The slash invocation `/<name>` is mentioned in the Test Plan's Trigger line for every slash-invocable skill.
- The 3 reference skills (`code-navigation`, `orchestrate-agents`, `visual-companion`) are explicitly marked as reference-only in their Test Plan triggers.

| # | Skill | Slash | Static result | Notes |
|---|-------|-------|---------------|-------|
| 1 | handover | `/handover` | PASS | Slash-only via `disable-model-invocation: true`. SYNC marker on line 96 points at hook script. 8 section headings on lines 99-129. |
| 2 | load-handover | `/load-handover` | PASS | Slash-only. Reads `.claude/handovers/`, formats summary. |
| 3 | delete-last-handover | `/delete-last-handover` | PASS | Slash-only. Confirmation prompt before destructive action; prunes `MEMORY.md` `<!-- handover-sourced -->` lines. |
| 4 | delete-all-handovers | `/delete-all-handovers` | PASS | Slash-only. Lists inventory, requires explicit confirmation. |
| 5 | brainstorm | `/brainstorm <idea>` | PASS | Slash-only. argument-hint, depth heuristic, executive-summary gate, spec save under `docs/brainstorms/`. |
| 6 | plan | `/plan <task>` | PASS | Slash-only. argument-hint, parallel agent dispatch, review-fix detection, save under `.claude/plans/`. |
| 7 | work | `/work [path-or-name]` | PASS | **Implicit invocation preserved** (no `disable-model-invocation`). argument-hint. Phase 0..5, NO_GIT graceful degrade, review-fix Phase 4c, orchestrator hand-off at Phase 2.5. |
| 8 | review | `/review` (and `/review --with-codex`) | PASS | Slash-only. argument-hint covers all flags. SYNC marker on line 362 points at `skills/work/SKILL.md:316`. |
| 9 | commit | `/commit` (and `/commit --push`) | PASS | Slash-only. argument-hint. NO_GIT short-circuit. Conventional Commits message generation. |
| 10 | create-pr | `/create-pr` | PASS — *also live-tested in this session (PR #21 opened end-to-end)* | Slash-only. argument-hint. Base-branch detection priority order, push-if-needed, gh pr create with HEREDOC body. |
| 11 | create-agent | `/create-agent <description>` | PASS | Slash-only. argument-hint. **Merged file** — Phase 1..4 workflow on top, Authoring Reference taxonomy below. In-doc anchors verified: `#agent-authoring-reference`, `#agent-body-structure`, `#category-definitions`, `#model-selection-guide`, `#quality-gates` all resolve. |
| 12 | create-agents-md | `/create-agents-md` | PASS | Slash-only. argument-hint. Writes AGENTS.md with quality gates. |
| 13 | repair-skill | `/repair-skill [target]` | PASS | Slash-only. argument-hint. **Merged file** — Phase 1..5 workflow on top, Skill Repair Reference (F1-F10, Diagnostic Checklist, Repair Strategies, Context7 Lookup Guide) below. In-doc anchors verified: `#skill-repair-reference`, `#common-failure-patterns`, `#diagnostic-checklist`, `#repair-strategies`, `#context7-lookup-guide`, `#1-structural-validation`, `#2-content-quality`, `#4-integration-check` all resolve. |
| 14 | code-navigation | reference (loaded by other skills) | PASS | Reference-only. "Skill-Level LSP Detection" terminology updated. Test Plan documents how `/plan` and `/review` consume it. |
| 15 | orchestrate-agents | reference (loaded by other skills) | PASS | Reference-only. Test Plan documents the general-orchestrator vs work-skill orchestrator distinction. |
| 16 | visual-companion | reference (used by `/brainstorm` Step 1.5) | PASS | Reference-only. Only Quiver skill that ships a runtime executable (`server.py`). |

---

## 3. Cross-cutting structural checks

| Check | Method | Result |
|-------|--------|--------|
| 7 review agents repointed from `commands/review.md` to `skills/review/SKILL.md` | `grep -c 'skills/review/SKILL.md' agents/review/*.md` | PASS — `architecture-strategist`, `developer-experience-auditor`, `logic-reviewer`, `security-audit`, `stress-tester`, `test-reviewer`, `waste-detector` each carry 1 reference. `codex-code-reviewer` (transport adapter) carries 0, which is expected. |
| No stale `commands/` references in active code | `grep -rn 'commands/' --exclude-dir=.git --exclude-dir=docs --exclude=TEST-RUN.md` minus intentional generic patterns | PASS — only intentional cross-repo classification patterns remain (`.gitignore` user-command path, brainstorm's source-dir glob enumeration, review's PROMPT classification rule). |
| README inventory counts match reality | `ls -d skills/*/ \| wc -l` vs README "Skills \| 16" | PASS |
| CLAUDE.md SYNC reference | grep on `## SYNC contract` block | PASS — points at `skills/handover/SKILL.md:96` and lines 99-129. |
| AGENTS.md Important Locations | grep on `SYNC` lines | PASS — both lines point at the new skill file plus the hook with correct line numbers. |
| `.claude/rules/readme-structure.md` updated to skill terminology | grep on `command` | PASS — only the legitimate phrase `marketplace add + plugin install + first slash example` remains; old "Commands" section reference removed during this audit. |

---

## 4. Live runtime smoke test (already executed during the migration session)

The `/quiver:create-pr` skill was invoked end-to-end during the session that produced this branch. It:

1. Ran the 6 `!`-prefixed git context shell blocks and read the outputs.
2. Detected `master` as the base branch from `origin/HEAD`.
3. Ran `git push -u origin refactor/commands-to-skills`.
4. Generated the PR title and body and asked for confirmation via `AskUserQuestion`.
5. On approval, ran `gh pr create --base master --title … --body …` with HEREDOC body.
6. Returned PR URL: https://github.com/yagizdo/quiver/pull/21

**This is the strongest single piece of evidence available without restarting the session.** It exercises shell-block pre-execution, frontmatter parsing, `argument-hint` recognition, `AskUserQuestion` rendering, and external CLI invocation (`gh`) — every runtime primitive a typical Quiver skill depends on. The migration did not break this path.

---

## 5. Genuinely runtime-only checks (require fresh Claude Code session)

These cannot be auto-verified from inside the migration session. Open a fresh Claude Code session on this branch and tick each one before merge.

| Check | Why it's runtime-only |
|-------|------------------------|
| [ ] Slash menu lists all 13 user-facing skills with no duplicates | `/` palette is rendered at session start; current session may still cache the old `commands/` mapping. |
| [ ] `disable-model-invocation: true` is honored — slash-only skills don't auto-fire on relevant prompts | Claude Code issue #22345: the flag may be silently ignored on plugin-distributed skills. Acceptable if not honored on this version (cost ~4.4K tokens/request, no functional regression). |
| [ ] `/handover` produces an 8-section file with the freshness check | Generates a real file based on conversation context; only meaningful in a real work session. |
| [ ] `/review` dispatches multiple agents in a single response (parallel) | Real LLM-side agent dispatch; cannot be observed from a static check. |
| [ ] `/plan` parallel dispatch + `AskUserQuestion` clarification flow | Same as above. |
| [ ] PreCompact hook auto-saves a handover when context compaction fires | Hook is registered and executes when Claude Code triggers PreCompact; cannot be triggered from outside the session. |
| [ ] (Cursor 2.6+ smoke-test, post-merge) all 13 user-facing skills appear in Cursor's `/` palette | Cursor forum 155748: plugin-distributed skills with `disable-model-invocation: true` may be hidden. Contingency: strip the flag from affected skills and document. |

> **Practical recommendation:** Open a fresh Claude Code session in this repo, type `/`, confirm 13 skills appear, then run `/handover` and `/review` end-to-end. That covers the highest-value runtime checks (~5 minutes). The remaining slash skills are mostly variations on the same primitives and the static checks above already prove their structural correctness.

---

## 6. Summary

- **Auto-verifiable acceptance criteria:** 11/11 PASS.
- **Per-skill structural verification:** 16/16 PASS.
- **Cross-cutting structural checks:** 6/6 PASS.
- **Live runtime smoke test:** 1/1 PASS (`/quiver:create-pr` opened PR #21 end-to-end).
- **Runtime-only manual checks:** 7 items pending — fresh session required.

The migration is structurally complete. Proceeding to merge requires only the 7 runtime-only checks above. Delete this file after merge.

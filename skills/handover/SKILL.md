---
name: handover
description: Summarize the current work state and prepare a handover note for the next session.
disable-model-invocation: true
when-to-use: "user wants to save session context or wrap up a session -- '/handover', 'save handover', 'create a handover', 'end of session', 'save my progress'"
---

# Step 0 — Gather Git Context

```
!`git rev-parse --is-inside-work-tree 2>/dev/null || echo "NO_GIT"`
```

```
!`git status --short 2>/dev/null || echo "NO_GIT"`
```

```
!`git diff --stat 2>/dev/null || echo "NO_GIT"`
```

If any block above returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- skipping branch/commit context.`
Continue — git context is optional. Treat all git-sourced fields as empty.

---

# Session Freshness Check

Before generating a handover, determine whether this session produced meaningful work worth preserving. **You must prove substance exists — do not assume it.**

### Step 1 — Enumerate Meaningful Work

Review the full conversation and list every meaningful action taken during **this session**. Write this list as a **Decision Log** before choosing a branch.

**Counts as meaningful work:**
- Code created, edited, or deleted (file writes, not just reads)
- Bug investigated with findings or conclusions
- Architectural or design decisions made
- Multi-step debugging with a diagnosis
- Configuration changes applied
- Tests written, run, or fixed
- Plans created or refined with concrete next steps

**Does NOT count as meaningful work:**
- The `/quiver:handover` command itself and its git context-gathering commands
- Reading files solely to answer a quick question with no follow-up action
- Greetings, small talk, or simple Q&A with no project impact
- Pre-existing git dirty state from a prior session (changes that were already there when this session started)
- Exploring or browsing code without reaching conclusions or decisions

### Step 2 — Decision Log

Output the following before choosing a branch:

> **Decision Log — Session Freshness**
> Meaningful actions found:
> - {list each meaningful action, or "None"}
> Verdict: {Branch A or Branch B}

### Branch A — No Meaningful Work (skip handover)

If the meaningful actions list is empty:

> **Handover skipped** — This session has no meaningful work to summarize.
> A handover file was **not** created.
>
> **When to run this command:**
> - After making code changes, investigating bugs, or making decisions
> - At the end of a productive work session
> - Before closing a session you would like to resume later

**Stop here.** Do not create the handover directory, do not write any files, and do not proceed to the Handover Instructions below.

### Branch B — Meaningful Work Exists (create handover)

If the meaningful actions list has at least one item, proceed to the Handover Instructions section below and generate the full handover.

---

# Handover Instructions

**Your role:** You are a session handover specialist. Your goal is to produce a zero-re-discovery handover — the next session should never re-investigate what this session already learned. Be specific: include file paths, function names, line numbers, and exact error messages.

If git context was not available (see Step 0), build the handover from the conversation context alone and note "Git not available" in the Summary.

**Workflow:**
```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ 1. GATHER       │ ──► │ 2. BUILD         │ ──► │ 3. SAVE & VERIFY │
│ Read git status  │     │ Write 8 sections │     │ Write file       │
│ Review convo     │     │ Check quality    │     │ Prune old files  │
│ Identify files   │     │ gates            │     │ Update MEMORY.md │
└─────────────────┘     └──────────────────┘     └──────────────────┘
```

<!-- SYNC: The 8 section headings below must match the PROMPT_PREFIX headings in hooks/scripts/pre-compact-handover.sh. Verified by tests/hooks/test-handover-sync-contract.sh. -->
Using the context above and our conversation, prepare a structured handover note with these exact sections:

## Summary
{One-paragraph TL;DR. Include: what feature/bug was worked on, current status (done / in-progress / blocked), and branch name if applicable. Example:}
> Implemented JWT refresh token rotation on `feature/auth-refresh`. All tests passing; PR ready for review.

## What Was Done
{Bulleted list. Each item: file path + what changed. Example:}
- `src/auth.ts` — Added JWT refresh token rotation
- `tests/auth.test.ts` — Added 3 test cases for token expiry

## What We Tried / Dead Ends
{Approaches that didn't work and why. Include enough detail to prevent re-investigation. Example:}
- Tried using `jsonwebtoken` v8 but it lacks `rotateRefresh()` — downgraded to v7 API

## Bugs & Fixes
{Issues found and how they were resolved. Include file paths and line numbers. Example:}
- `src/auth.ts:42` — Off-by-one in token expiry calculation; changed `>=` to `>`

## Key Decisions (and Why)
{Architectural choices made this session. State the alternatives considered. Example:}
- Chose Redis over in-memory cache for token blacklist — survives server restarts

## Gotchas / Things to Watch Out For
{Non-obvious constraints, traps, or environment quirks. Example:}
- `AUTH_SECRET` env var must be ≥32 chars or the signing silently falls back to HS256

## Next Steps
{Ordered list — first item is the highest priority action for the next session. Example:}
1. Open PR for `feature/auth-refresh` and request review
2. Add rate limiting to `/token/refresh` endpoint

## Important Files Map
{Key files and their roles in the current work. Example:}
- `src/auth.ts` — Main authentication module (token issue + refresh)
- `config/redis.yml` — Token blacklist store configuration

**If a section has no content, write `N/A — {reason}` instead of omitting the heading.**

---

## Quality Gates

Before saving, verify the handover passes these checks:

**BLOCKING** (fix before saving):
- Summary is not empty
- Next Steps has at least one item
- What Was Done references at least one file path

**WARNING** (review if session was longer than ~15 minutes):
- What We Tried / Dead Ends is empty — long sessions usually have dead ends worth noting

---

## Anti-Patterns

- **Don't** write vague summaries like "worked on auth stuff" — include the specific feature and current status.
- **Don't** paste full file contents into the handover — summarize changes with file paths and line references.
- **Don't** skip updating MEMORY.md — it's the cross-session index.
- **Don't** leave Next Steps empty — every session has a logical continuation.

---

## Save to Disk (Required)

After writing the handover above, do all of the following:

### 1. Write handover file
Get a timestamp: run `date '+%Y-%m-%d_%H-%M-%S'` via Bash.
Create directory: `.claude/handovers/` in the project root (if it doesn't exist).
Write the full 8-section handover to: `.claude/handovers/{timestamp}.md`
**Verify:** Read back the file to confirm it was written correctly.

### 2. Prune old handover files
List all `.md` files in `.claude/handovers/`, sorted by name (newest first).
Delete all files beyond the 3 most recent.
**Verify:** Re-list the directory and confirm only ≤3 files remain.

### 3. Update MEMORY.md
In the project memory file, update (or add) a `## Last Handover` section:
```
## Last Handover
- file: .claude/handovers/{timestamp}.md <!-- handover-sourced -->
- summary: {one sentence from the Summary section} <!-- handover-sourced -->
```
**Verify:** Read MEMORY.md to confirm the update.

### 4. Save any active plan
If there is an unsaved implementation plan in context, save it to `PLAN.md`. Skip if already current.

### Completion Confirmation

After all saves, output this confirmation:

> **Handover saved:** `.claude/handovers/{timestamp}.md`
> **Files retained:** {comma-separated list of kept handover files}
> **MEMORY.md updated:** yes/no
> **Ready to close the session.**

---

## Test Plan

**Trigger:** `/handover` (and `/quiver:handover` should also work)

**Setup:**
- Current directory is a git repo with at least one file modification or substantive conversation history.

**Expected behavior:**
1. Skill runs the three `git` shell blocks (`rev-parse`, `status --short`, `diff --stat`); on a non-git directory, prints `> No git repository detected -- skipping branch/commit context.` and continues.
2. Skill produces a Decision Log enumerating meaningful actions; if none, exits with `Handover skipped` and writes nothing.
3. With meaningful work present, skill writes a handover note containing all 8 required sections (Summary, What Was Done, What We Tried / Dead Ends, Bugs & Fixes, Key Decisions, Gotchas, Next Steps, Important Files Map).
4. Skill saves the handover to `.claude/handovers/<timestamp>.md` (filename uses `date '+%Y-%m-%d_%H-%M-%S'` format), prunes the directory to the 3 most recent files, and updates MEMORY.md with a `## Last Handover` block tagged `<!-- handover-sourced -->`.
5. Final confirmation block prints the saved file path, retained filenames, and `MEMORY.md updated: yes`.

**Verification checklist:**
- [ ] Slash menu shows `/handover`.
- [ ] All 8 section headings are present in the saved file (no section silently omitted).
- [ ] Filename matches `YYYY-MM-DD_HH-MM-SS.md`.
- [ ] Older handovers beyond the 3 most recent are removed.
- [ ] `MEMORY.md` gains a `## Last Handover` block with the `<!-- handover-sourced -->` marker.
- [ ] In an empty/no-progress session, the skill exits cleanly without writing any file.

**Known gotchas:**
- The 8 section headings are part of a SYNC contract with `hooks/scripts/pre-compact-handover.sh`. If headings here change, the hook's `PROMPT_PREFIX` must change in lockstep. `tests/hooks/test-handover-sync-contract.sh` is the gate on that.
- Lexicographic prune ordering depends on the timestamp filename format; do not rename existing handovers.

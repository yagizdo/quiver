---
name: handover
description: Summarize the current work state and prepare a handover note for the next session.
argument-hint: "[--clear | --clear-all]"
disable-model-invocation: true
when-to-use: "user wants to save session context or wrap up a session -- '/handover', 'save handover', 'create a handover', 'end of session', 'save my progress'"
---

# Step 0.5 — Argument Parsing

Read `$ARGUMENTS` as plain text:

- If it contains `--clear-all`: set clear-all intent. Go directly to the `# Clear Mode` section (after the save path's Completion Confirmation). Do not continue into Step 0 and do not write a handover.
- If it contains `--clear`: set clear-last intent. Go directly to `# Clear Mode`. Do not continue into Step 0 and do not write a handover.
- **Precedence:** `--clear-all` > `--clear`. The string `--clear-all` contains `--clear`, so test for `--clear-all` first; when it is present, clear the clear-last intent and delete every file, not just the newest.
- If it is empty, or contains neither flag: proceed to Step 0 and run the save path below, unchanged.

Both flags delete files and write nothing. Everything from Step 0 through the Completion Confirmation is the save path and does not run in Clear Mode.

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

Output the following before choosing a branch. The branch labels are internal
routing and never reach the user (R7) -- name the outcome in words instead.

> **Session check — is there work worth handing over?**
> Meaningful actions found:
> - {list each meaningful action, or "None"}
> Outcome: {writing a handover | nothing to hand over, skipping}

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

# Clear Mode

Reached only from Step 0.5, when `$ARGUMENTS` carried `--clear` or `--clear-all`. This path deletes handover files and never writes one. Ignore the git context from Step 0 — it has no bearing on a delete.

### Step C1 — Inventory

Use the Glob tool to list `.claude/handovers/*.md`. Sort the results by filename descending (newest first, since filenames are timestamps). This listing is the only source of truth for what gets deleted; do not add a second listing mechanism.

#### Branch A — No Files

If the listing errors (e.g., "No such file or directory"), is empty, or contains **no `.md` files**:

> No handover files found — nothing to delete.

**Stop here.** Do not create the directory, do not call `AskUserQuestion`, do not run any `rm`.

#### Branch B — Files Exist

Resolve the deletion set from the intent set in Step 0.5:

- **clear-last** (`--clear`): the **first `.md` file** in the sorted listing — the most recent one. Exactly one file.
- **clear-all** (`--clear-all`): **every `.md` file** in the listing.

### Step C2 — State the Deletion Set

Print the full inventory before asking anything. The user must see every filename that is about to be removed, not a count.

For **clear-last**:
> **Target:** `{filename}`
> **Remaining after deletion:** {count - 1} handover file(s)

For **clear-all**:
> **Files to delete ({count}):**
> {bulleted list of every `.md` filename in the deletion set}

### Step C3 — Confirm (Required)

Ask with the `AskUserQuestion` tool — never plain text.

For **clear-last**:
- Question: "Delete `{filename}`? This cannot be undone."
- Options: `["Yes, delete it", "Cancel"]`

For **clear-all**:
- Question: "Delete all {count} handover file(s)? This cannot be undone."
- Options: `["Yes, delete all", "Cancel"]`

**Only proceed on the affirmative option.** On "Cancel", print and stop:

> **Cancelled** — no files were deleted.

Nothing is removed on the cancel path: no `rm`, no MEMORY.md edit, no output template.

### Step C4 — Delete

Run exactly one command with the Bash tool, matching the intent:

- **clear-last:**
  ```
  rm .claude/handovers/{filename}
  ```
- **clear-all:**
  ```
  rm -f .claude/handovers/*.md
  ```

### Step C5 — Verify the Delete (Required)

Re-list `.claude/handovers/` with Glob and compare against the deletion set.

- **clear-last:** the target filename is gone and every other file from the Step C1 inventory is still present. If the target is still listed, the delete failed — report the failure and stop, do not print the output template.
- **clear-all:** zero `.md` files remain. Confirm: `Directory clean — 0 handover files.` If any remain, report which ones and stop.

### Step C6 — Memory Cleanup

Read the auto-memory file (`MEMORY.md` in your memory directory). Using the Edit tool, remove only the lines containing the `<!-- handover-sourced -->` marker. Leave every other entry untouched. Count the removed lines as {N} and report:

> Also removed {N} handover-sourced references from MEMORY.md.

If no matching lines were found, skip this message entirely.

### Step C7 — Output Template

For **clear-last**:

> **Deleted:** `{filename}`
> **Remaining:** {count - 1} handover file(s)

For **clear-all**:

> **Purged:** {count} handover file(s)
> **Files deleted:** {comma-separated filenames}
> **Status:** Clean slate.

Fill every `{...}` from the Step C1 inventory — Step C5's re-list verifies the delete, it does not supply these values. No raw `{placeholder}` may survive into the printed output.

### Clear Mode Anti-Patterns

- **Don't** delete without printing the filenames first — a count alone does not tell the user what they are losing.
- **Don't** skip the `AskUserQuestion` confirmation, even under an automated test. Both deletes are irreversible.
- **Don't** treat `--clear-all` as `--clear` because the substring matches. Step 0.5 resolves precedence; honor it.
- **Don't** skip the re-list in Step C5 — without it a failed `rm` is reported as a success.
- **Don't** create `.claude/handovers/` on the delete path. A missing directory is Branch A, not an error to repair.

---

## Test Plan

**Trigger:** `/handover`, `/handover --clear`, `/handover --clear-all` (the `/quiver:handover` forms should also work)

### Case: no flag (save path)

**Setup:**
- Current directory is a git repo with at least one file modification or substantive conversation history.

**Expected behavior:**
1. Skill runs the three `git` shell blocks (`rev-parse`, `status --short`, `diff --stat`); on a non-git directory, prints `> No git repository detected -- skipping branch/commit context.` and continues.
2. Skill produces a Decision Log enumerating meaningful actions; if none, exits with `Handover skipped` and writes nothing.
3. With meaningful work present, skill writes a handover note containing all 8 required sections (Summary, What Was Done, What We Tried / Dead Ends, Bugs & Fixes, Key Decisions, Gotchas, Next Steps, Important Files Map).
4. Skill saves the handover to `.claude/handovers/<timestamp>.md` (filename uses `date '+%Y-%m-%d_%H-%M-%S'` format), prunes the directory to the 3 most recent files, and updates MEMORY.md with a `## Last Handover` block tagged `<!-- handover-sourced -->`.
5. Final confirmation block prints the saved file path, retained filenames, and `MEMORY.md updated: yes`.

**Verification checklist (save path):**
- [ ] Slash menu shows `/handover`, and its argument hint offers `--clear` and `--clear-all`.
- [ ] All 8 section headings are present in the saved file (no section silently omitted).
- [ ] Filename matches `YYYY-MM-DD_HH-MM-SS.md`.
- [ ] Older handovers beyond the 3 most recent are removed.
- [ ] `MEMORY.md` gains a `## Last Handover` block with the `<!-- handover-sourced -->` marker.
- [ ] In an empty/no-progress session, the skill exits cleanly without writing any file.

### Case: `--clear` (delete the newest handover)

**Setup:** `.claude/handovers/` holds 3 timestamp-named `.md` files.

**Expected behavior:**
1. Step 0.5 sets clear-last intent; the skill does not run the save path and writes no handover.
2. Glob lists the 3 files newest-first; the skill prints `Target: <newest filename>` and `Remaining after deletion: 2 handover file(s)`.
3. `AskUserQuestion` is called with `["Yes, delete it", "Cancel"]`.
4. On confirm, only the newest file is removed; the re-list shows the other 2 still present.
5. `MEMORY.md` lines tagged `<!-- handover-sourced -->` are removed and the count is reported; untagged lines are untouched.
6. Output prints `Deleted:` and `Remaining: 2 handover file(s)` with no `{placeholder}` left.

### Case: `--clear-all` (delete every handover)

**Setup:** `.claude/handovers/` holds 3 timestamp-named `.md` files.

**Expected behavior:**
1. Step 0.5 matches `--clear-all` before `--clear` and sets clear-all intent, not clear-last.
2. The skill prints `Files to delete (3):` followed by all 3 filenames — a count with no list is a failure.
3. `AskUserQuestion` is called with `["Yes, delete all", "Cancel"]`.
4. On confirm, `rm -f .claude/handovers/*.md` runs; the re-list reports `Directory clean — 0 handover files.`
5. Output prints `Purged: 3 handover file(s)`, the deleted filenames, and `Status: Clean slate.`

### Case: Cancel (either flag)

**Setup:** `.claude/handovers/` holds at least 1 `.md` file.

**Expected behavior:**
1. The inventory is printed and `AskUserQuestion` is called as above.
2. Selecting `Cancel` prints `Cancelled — no files were deleted.` and stops.
3. No `rm` runs, `MEMORY.md` is not edited, and no output template is printed. Re-listing the directory shows the same files as before the invocation.

**Verification checklist (flags):**
- [ ] `/handover --clear` removes exactly one file (the newest) and leaves the rest.
- [ ] `/handover --clear-all` removes every `.md` file and reports 0 remaining.
- [ ] `--clear-all` is not mis-read as `--clear` despite the substring match.
- [ ] Both flags confirm through `AskUserQuestion` before any `rm`; `Cancel` deletes nothing.
- [ ] Both flags re-list the directory after deleting, and neither prints a raw `{placeholder}`.
- [ ] With a missing or empty `.claude/handovers/`, both flags print the `nothing to delete` line, create no directory, and write nothing.
- [ ] Bare `/handover` with no flag still runs the save path unchanged.

**Known gotchas:**
- The 8 section headings are part of a SYNC contract with `hooks/scripts/pre-compact-handover.sh`. If headings here change, the hook's `PROMPT_PREFIX` must change in lockstep. `tests/hooks/test-handover-sync-contract.sh` is the gate on that.
- Lexicographic prune ordering depends on the timestamp filename format; do not rename existing handovers. Clear Mode's newest-first sort in Step C1 depends on the same format, so `--clear` targets the wrong file if a filename ever drifts from `YYYY-MM-DD_HH-MM-SS.md`.
- `--clear-all` contains `--clear` as a substring. A plain "contains `--clear`" test matches both flags and silently downgrades a purge to a single delete, which reads as success. Step 0.5's precedence rule is the only thing preventing that.
- Clear Mode lists the directory with Glob, not with a `!` shell block. Every `!` block in this repo's skills runs `git`, which is pre-approved in the marketplace sandbox; lesson L1 in `.claude/rules/skill-rules.md` records non-git commands failing there when combined with `||`. The listing also has to happen after Step 0.5 resolves the flag, and `!` blocks run before any step logic.
- The delete paths are why this skill keeps `disable-model-invocation: true`. R10 lets a disabled skill keep its `when-to-use:` and the routing hook drops it from the auto-dispatch block, so no model-initiated invocation can reach `--clear` or `--clear-all`.

---
description: Generate a Conventional Commits message, commit, and optionally push to remote.
---

# Gather Git Context

```
!`git rev-parse --is-inside-work-tree 2>&1; true`
```

```
!`git status --short 2>/dev/null; true`
```

```
!`git diff --cached 2>/dev/null; true`
```

```
!`git log --oneline -10 2>/dev/null; true`
```

---

# Instructions

Silently determine which case applies — do not show the case label or decision logic to the user:

- **No repo / no changes:** If `git rev-parse` shows "not a git repository", or `git status` is empty → tell the user and stop.
- **Nothing staged:** If `git diff --cached` is empty but `git status` shows changes → tell the user to stage files and run `/quiver:commit` again, then stop.
- **Staged changes exist:** Proceed silently to Commit Message Generation.

---

# Commit Message Generation

Analyze `git diff --cached` and the recent log. Generate a Conventional Commits message following these rules:

**Type** — Select one based on primary intent:

| Type | When to Use |
|------|-------------|
| `feat` | New feature or capability visible to users |
| `fix` | Bug fix |
| `docs` | Documentation only (README, comments, JSDoc) |
| `style` | Formatting, whitespace, semicolons — no logic change |
| `refactor` | Code restructuring with no behavior change |
| `perf` | Performance improvement |
| `test` | Adding or fixing tests |
| `build` | Build system or external dependencies (npm, Makefile) |
| `ci` | CI/CD configuration (GitHub Actions, CircleCI) |
| `chore` | Maintenance tasks (version bumps, tooling config) |
| `revert` | Reverting a previous commit |

**Scope** — From file paths: single directory → its name, single file → domain name, cross-cutting → omit.

**Breaking changes** — Check the staged diff for:
- Removed or renamed public API functions/methods
- Changed function signatures (added required params, changed return types)
- Removed or renamed CLI flags, commands, or environment variables
- Changed data formats, schemas, or wire protocols
- Removed files that other code may depend on

If found: add `!` after type/scope and a `BREAKING CHANGE:` footer.

**Subject line** — Imperative mood, lowercase after colon, no period, ≤72 chars total, describe *what* not *how*.

**Body** — Almost never. Only for breaking changes or when the subject alone would be misleading. Wrap at 72 chars.

**Footers** — `BREAKING CHANGE:` if applicable. `Refs: #issue` if relevant.

---

# Output

**Important:** Output ONLY the code block below — no metadata, no analysis, no narration, no reasoning before or after.

```
{type}({scope}): {subject}
```

Include a body or footers only for breaking changes or multi-type changes where the subject alone is genuinely ambiguous. Default to subject-only.

Then use the `AskUserQuestion` tool to present selectable options:

- **Question:** "How would you like to proceed?"
- **Header:** "Action"
- **Options:**
  1. **Commit** — "Commit with this message"
  2. **Commit & Push** — "Commit and push to remote"
  3. **Edit** — "Revise the message"
  4. **Cancel** — "Abort without committing"

---

# Commit Execution

**On commit or commit & push:**

1. Commit using a HEREDOC:
   ```
   git commit -m "$(cat <<'EOF'
   {full commit message}
   EOF
   )"
   ```
2. Verify: `git log --oneline -1` and `git status --short`.

**If commit & push**, also:

3. Detect branch: `git branch --show-current`
4. Push: if `git rev-parse --abbrev-ref @{upstream} 2>/dev/null` succeeds → `git push`, otherwise → `git push -u origin {branch}`
5. Verify push exit code is 0.

**Output:**

> **Committed:** `{short hash}` {subject}
> **Branch:** `{branch name}`
> **Pushed to:** `origin/{branch}` *(only if pushed)*

**On edit:** Ask what to change, revise, re-present, and ask again.

**On cancel:**

> **Commit cancelled.** Staged changes are intact.

**Stop here.**

---

# Error Handling

If `git commit` fails (non-zero exit code):

1. Show the error output verbatim.
2. **Pre-commit hook failure** — suggest the user fix the issue and re-run `/quiver:commit`.
3. **Never** retry automatically or use `--no-verify`.

---

# Quality Gates

Before presenting the commit message, verify:

**BLOCKING** (fix before presenting):
- Subject line is in imperative mood
- Subject line (full `type(scope): description`) is ≤ 72 characters
- Type is one of the 11 allowed values
- Breaking changes have a `BREAKING CHANGE:` footer

**WARNING** (review but don't block):
- Single-directory change with no scope — consider adding one

---

# Rules

- Don't stage additional files — only commit what's already staged.
- Don't force-push — always use regular `git push`.
- Don't add `Co-authored-by` or attribution footers unless explicitly requested.
- Don't include file lists in the body — `git log --stat` shows this.
- Don't use past tense — Conventional Commits uses imperative mood.

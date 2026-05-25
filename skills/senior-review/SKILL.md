---
name: senior-review
description: "Pragmatic senior developer code review -- evaluates code quality, risks, and conventions through a team lead lens. Standalone or integrated into /review pipeline."
argument-hint: "[--quick] [#PR_NUMBER | PR_URL]"
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree 2>/dev/null || echo "NO_GIT"`
```

```
!`git branch --show-current 2>/dev/null || echo "NO_GIT"`
```

```
!`git log --oneline -10 2>/dev/null || echo "NO_GIT"`
```

---

# Senior Review

Run a pragmatic senior developer code review -- evaluating structural decisions, code quality, risk areas, and language conventions through a team lead lens.

**Announce:** "Using the senior-review skill for a pragmatic code review."

---

## Step 0 -- Git Availability

If any gather-context block above returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected. /senior-review requires a git repo.`
**Stop here.**

## Step 0.5 -- Input Validation

If `$ARGUMENTS` is empty AND there is no conversation context about what to review (no prior diff discussion, no files mentioned), print:

> Usage: `/senior-review [--quick] [#PR_NUMBER | PR_URL]`
>
> Options:
> - `--quick` -- Single-pass review (faster, same quality bar)
> - `#123` or PR URL -- Review a specific pull request
> - No arguments -- Prompted to select diff source

**Stop here.**

If `$ARGUMENTS` is empty but conversation context exists (e.g., user was just discussing a diff), proceed -- use the contextual diff.

---

## Step 1 -- Argument Parsing

Parse `$ARGUMENTS`:

- Contains `--quick` --> set mode to `quick`, remove flag from remaining arguments
- Contains `#NNN` (hash + digits) --> set source to `pr`, extract PR number
- Contains a URL matching a PR/MR pattern (github.com/.../pull/NNN, gitlab.com/.../-/merge_requests/NNN) --> set source to `pr`, extract URL
- Otherwise --> source is unset (will prompt in Step 2)

---

## Step 2 -- Diff Source Selection

If source was set from Step 1 (PR number or URL), skip to Step 3.

Otherwise, use `AskUserQuestion`:

> What would you like me to review?

Buttons:
- **"Uncommitted changes"** --> source = `uncommitted`
- **"Branch diff (vs main/master)"** --> source = `branch`
- **"Pull Request"** --> source = `pr` (will prompt for PR number)

If user selects "Pull Request" and no PR number was provided, ask:
> Enter the PR number or URL:

---

## Step 3 -- Diff Gathering

Gather the diff based on selected source:

**Uncommitted changes:**
```
!`git diff 2>/dev/null || echo "NO_DIFF"`
```
```
!`git diff --staged 2>/dev/null || echo "NO_DIFF"`
```

Combine both outputs. If both are empty, print:
> No uncommitted changes found.
**Stop here.**

**Branch diff:**
Determine the base branch:
```
!`git rev-parse --verify main 2>/dev/null || echo "NO_MAIN"`
```

Use `main` if it exists, otherwise `master`. Then gather:
```
!`git diff main...HEAD 2>/dev/null || echo "NO_DIFF"`
```

If empty, print:
> No changes found between current branch and base branch.
**Stop here.**

**Pull Request:**
Use the `gh` CLI to fetch the PR diff:
```
!`gh pr diff {pr_number_or_url} 2>&1`
```

If `gh` is not available or the command fails, print:
> Could not fetch PR diff. Ensure `gh` CLI is installed and authenticated.
**Stop here.**

Also gather the changed file list:
```
!`git diff --name-only main...HEAD 2>/dev/null || echo "NO_FILES"`
```

(For PR source, use `gh pr diff --name-only` if available, otherwise parse the diff headers.)

---

## Step 4 -- Language Detection

Scan changed file extensions from the file list gathered in Step 3.

| Extensions | Primary Language |
|---|---|
| `.swift` | Swift/iOS |
| `.dart` | Flutter/Dart |
| `.ts`, `.tsx` | TypeScript/React |
| `.py` | Python |
| `.kt` | Kotlin/Android |
| `.js`, `.jsx` | JavaScript/React |
| `.go` | Go |
| `.rs` | Rust |

If multiple languages detected, note all of them. The agent handles mixed diffs gracefully.

If no recognized extensions, set language to `unknown`.

---

## Step 5 -- Context7 Lookup (Full Mode Only)

If mode is `quick`, skip this step entirely.

For the detected primary language/framework, query context7 MCP for current conventions:

- **Swift/iOS:** Query for SwiftUI or UIKit conventions based on imports in the diff
- **Flutter/Dart:** Query for Flutter widget patterns and Dart idioms
- **TypeScript/React:** Query for React hooks rules and TypeScript strict mode patterns
- **Other languages:** Query for the framework detected from imports

Limit to one query for the primary language. Do not query for every language in a mixed diff.

If context7 is unavailable or returns no results, proceed without it -- the agent has built-in criteria.

---

## Step 6 -- Agent Dispatch

Dispatch `quiver:senior-reviewer` with the following context (in this order):

1. **Full diff** from Step 3.
2. **Changed file list** with detected language(s) from Step 4.
3. **Mode:** `full` or `quick`.
4. **Context7 results** (if available from Step 5, omit if quick mode or unavailable).
5. **Scope reminder:** "Your findings MUST be scoped to code CHANGED in this diff. Reading surrounding code for context is expected; flagging pre-existing issues is not."
6. **Citation accuracy:** "Every file:line reference in your findings must be verified by reading the file. Do not cite line numbers from memory or inference -- use the Read tool to confirm the content at the cited line before including it in a finding."

Do NOT pass pipeline context. This is standalone mode -- Phase 5 (meta-review) must not activate.

---

## Step 7 -- Output

Present the agent's findings in the terminal.

After presenting findings, use `AskUserQuestion`:

> Review complete. What would you like to do?

Buttons:
- **"Save report"** --> Write to `.claude/reports/senior-review-{timestamp}.md` (use `date '+%Y-%m-%d_%H-%M-%S'` format). Confirm with: `> Report saved to {path}`
- **"Done"** --> Stop.

---

## Test Plan

**Trigger:** `/senior-review` (and `/quiver:senior-review`)

**Setup:**
- Current directory is a git repo with changes (uncommitted or on a branch).
- `gh` CLI available for PR mode testing.

**Expected behavior:**
1. Shell blocks gather git context without errors.
2. `--quick` flag is parsed and sets mode before diff gathering.
3. `#NNN` argument triggers PR mode directly without source selection prompt.
4. Empty arguments with no context prints usage and stops.
5. Diff source selection offers three buttons via AskUserQuestion.
6. Language detection maps file extensions correctly.
7. Context7 lookup runs in full mode, skipped in quick mode.
8. Agent dispatch includes all required context items in order.
9. Pipeline context is never passed in standalone mode (Phase 5 stays inactive).
10. Save report option writes with correct timestamp filename format.

**Verification checklist:**
- [ ] Slash menu shows `/senior-review`.
- [ ] `--quick` mode skips context7 lookup and runs single-pass.
- [ ] PR mode works with `#123` syntax and full URL syntax.
- [ ] No shell logic in `!` blocks (no `$()`, no `if/else`, no variable assignment).
- [ ] All shell blocks exit 0 even when targets do not exist.
- [ ] AskUserQuestion used for diff source selection and post-review action.
- [ ] Agent dispatch does NOT include pipeline context.
- [ ] Report save path uses correct timestamp format.

**Known gotchas:**
- `gh pr diff` requires authentication. If `gh` fails, the skill stops with a clear message rather than proceeding with an empty diff.
- Context7 MCP may be unavailable in some environments. The skill degrades gracefully -- the agent has built-in per-language criteria.
- The `--quick` flag must be stripped from arguments before PR number parsing to avoid misinterpretation.

---
name: create-pr
description: "Create a GitHub pull request from the current branch. Use when the user says 'create a pr', 'open pr', 'push and open a pr', 'create pull request', or wants to open a PR from their branch."
argument-hint: "[--draft] [--base <branch>]"
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree 2>/dev/null || echo "NO_GIT"`
```

```
!`git status --short 2>/dev/null || echo "NO_GIT"`
```

```
!`git branch --show-current 2>/dev/null || echo "NO_GIT"`
```

```
!`git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo "NO_DEFAULT_BRANCH"`
```

```
!`git log --oneline -10 2>/dev/null || echo "NO_GIT"`
```

```
!`git remote -v 2>/dev/null || echo "NO_REMOTE"`
```

---

# Instructions

## Step 0 -- Validate Environment

Silently evaluate the gather-context output. Stop with a clear message on the first failure:

1. If any git block returned `NO_GIT` -> print: `> No git repository detected. /create-pr requires a git repo.` **Stop here.**
2. If `git remote -v` returned `NO_REMOTE` or is empty -> print: `> No remote configured. Add one with \`git remote add origin <url>\`.` **Stop here.**
3. If `git status --short` is not empty -> print: `> You have uncommitted changes. Commit them first -- you can use \`/quiver:commit\`.` **Stop here.**

---

## Step 1 -- Detect Base Branch

Determine the base branch using this priority order. Use the first that resolves:

1. If `$ARGUMENTS` contains `--base <value>`, use that value as the base branch.
2. If `git rev-parse --abbrev-ref origin/HEAD` did not return `NO_DEFAULT_BRANCH`, strip the `origin/` prefix and use the result.
3. Try `main` -- run `git rev-parse --verify origin/main 2>/dev/null`. If it succeeds, use `main`.
4. Try `master` -- run `git rev-parse --verify origin/master 2>/dev/null`. If it succeeds, use `master`.
5. Try `develop` -- run `git rev-parse --verify origin/develop 2>/dev/null`. If it succeeds, use `develop`.
6. If none resolved, ask the user: "Could not detect the base branch. What branch should this PR target?" via `AskUserQuestion`.

**After resolving the base branch:**

Check if the current branch (from `git branch --show-current`) equals the base branch. If so -> print: `> You are on the base branch (\`{base}\`). Create a feature branch first.` **Stop here.**

Check commits ahead: run `git log --oneline {base}..HEAD`. If output is empty -> print: `> No commits ahead of \`{base}\`. Nothing to create a PR for.` **Stop here.**

---

## Step 2 -- Push If Needed

Before creating the PR, ensure the branch is pushed to the remote:

1. Check upstream: `git rev-parse --abbrev-ref @{upstream} 2>/dev/null`
2. If upstream exists -> `git push`
3. If no upstream -> `git push -u origin {branch}`

If push fails, show the error verbatim and **stop here.**

---

## Step 3 -- Generate PR Title & Body

Gather additional context for PR generation:
- `git log --oneline {base}..HEAD` -- all commits on this branch
- `git diff --stat {base}..HEAD` -- files changed summary

**Title rules:**
- Concise, imperative mood, no period
- <= 72 characters
- Single commit: use its subject line. Multiple commits: summarize the overall theme.

**Body template:**

```
## Summary
- {1-3 bullet points describing what this PR does and why}

## Changes
- {Key changes organized by area}

## Test Plan
- [ ] {Testing steps or verification checklist}
```

Generate the title and body from the commit history and diff stats. The summary should explain *why* the changes were made, not just *what* changed.

---

## Step 4 -- Present & Execute

### Flag: `--draft`

If `$ARGUMENTS` contains "draft", skip the `AskUserQuestion` step. Show the generated title and body, then immediately execute `gh pr create --draft --title "{title}" --body "..." --base {base}`.

### Default (no flag)

Use the `AskUserQuestion` tool:

- **Question:** Build the question string using this template (replace placeholders):

  `"\x1b[2mPR Title:\x1b[0m\n{title}\n\n\x1b[2mPR Body:\x1b[0m\n{body}\n\nProceed?"`

- **Header:** "Pull Request"
- **Options:**
  1. **Create PR** -- "Create pull request"
  2. **Create as Draft** -- "Create as draft pull request"
  3. **Edit** -- "Revise the title or description"
  4. **Cancel** -- "Abort without creating PR"

---

### Execution

**On "Create PR":**

```
gh pr create --title "{title}" --body "$(cat <<'EOF'
{body}
EOF
)" --base {base_branch}
```

**On "Create as Draft":**

Same command with `--draft` appended.

**On "Edit":** Ask what to change, revise the title or body, and re-present the `AskUserQuestion`.

**On "Cancel":**

> **PR creation cancelled.**

**Stop here.**

---

## Step 5 -- Output

After successful PR creation, display:

> **PR Created:** {pr_url}
> **Title:** {title}
> **Branch:** `{current_branch}` -> `{base_branch}`
> **Commits:** {count}
> **Files changed:** {count}

Extract the PR URL from the `gh pr create` output (it prints the URL to stdout).

---

# Error Handling

If `gh pr create` fails, show the error verbatim and suggest the user check:
- GitHub CLI authentication (`gh auth login`)
- Remote repository permissions
- Whether a PR already exists for this branch (`gh pr list --head {branch}`)

Never retry automatically.

---
name: create-pr
description: "Create a GitHub pull request from the current branch. Use when the user says 'create a pr', 'open pr', 'push and open a pr', 'create pull request', or wants to open a PR from their branch."
argument-hint: "[--draft] [--base <branch>]"
when-to-use: "user wants to open a pull request from the current branch -- '/create-pr', 'create a PR', 'open a pull request', 'push and make a PR'"
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

Gather the change:
- `git log --oneline {base}..HEAD` -- all commits on this branch
- `git diff --stat {base}..HEAD` -- files changed summary
- `git diff {base}..HEAD` -- **full diff**

Then look for a repository PR template with the Read tool (`.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `docs/PULL_REQUEST_TEMPLATE.md`, or `PULL_REQUEST_TEMPLATE.md` at the root). Do this here with the Read tool, not in a `!` block -- the lookup is conditional and those blocks run before any step logic. If a template exists, its sections are the body's structure and the rules below only decide how much goes in each. A section the template asks for and the change has nothing to say about gets one line saying so, not padding. If none exists, build the body from the rules below.

**Title rules:**
- Concise, imperative mood, no period
- <= 72 characters
- Single commit: use its subject line. Multiple commits: summarize the overall theme.

**Body rules:**

The body has one reader: someone who has to approve this diff and was not in this conversation. Anything that does not help that person decide is padding, and padding on a small PR is worse than no description -- it buries the one thing that mattered.

**1. Budget.** Length scales with how much a reviewer has to hold in their head, not with line count. 400 lines of a regenerated lockfile is the top row; 20 lines rewriting auth logic is not.

| The change | Body |
|------------|------|
| One mechanical edit -- typo, version bump, rename, config value, generated file | 1-2 sentences. No headings at all. |
| One coherent behavior change, up to ~3 files | 2-4 sentences under `## Summary`. Nothing else unless a gate below opens. |
| Several files, one theme | `## Summary` plus a short `## Changes` list. Roughly 150-300 words. |
| Many files, or several themes at once | Add whichever gated sections apply. Roughly 600 words is the ceiling. If the change genuinely needs more than that, say in the body that the PR is large and is best reviewed commit by commit -- do not write more prose instead. |

Never ship a body that is a single sentence with no motivation, and never ship one that narrates the diff the reviewer already has.

**2. Sections are earned, not filled in.** Start with the Summary and add a section only when its gate is met. A section with nothing behind it is padding -- drop the heading entirely rather than writing a thin paragraph under it.

| Section | Include only when |
|---------|-------------------|
| `## Changes` | The diff touches more than one area and the file list alone does not tell a reviewer what each area does. One bullet per area or file, not per hunk. |
| `## How it works` | There is control flow, ordering, or an algorithm a reviewer cannot follow from the diff alone. |
| `## Design decisions` | A real alternative was considered and rejected -- in this conversation, in the commit messages, or in a plan, spec, or review report. Never invent one to fill the section. |
| `## Risks` | Breaking change, migration, data change, feature flag, or a rollback that is not trivial. |
| `## Test plan` | The reviewer has to do something themselves: manual steps, a runtime check, or a device or environment CI does not cover. If the diff adds tests and CI runs them, one sentence naming the command replaces the checklist. Never emit a checkbox for "code compiles", "tests pass", or "reviewed the diff". |

**3. Where the motivation comes from.** In order: what the user said in this conversation; the plan, spec, review report, or issue the branch was built from (`.claude/plans/`, `.claude/reports/`, a linked issue); then the commit messages; then the diff. The diff is last because it only ever answers *what*. If none of the first three carry a motivation, state what the change does and stop -- do not manufacture a rationale.

**4. The user's instructions outrank the tables.** Anything the user asked for in this invocation or earlier in the conversation -- shorter, longer, a section they want, a number they want quoted, an issue to link, a reviewer to address -- wins over every rule above.

**5. Do not write:**
- Filler openers -- "This PR introduces", "This pull request aims to", "In this change we".
- A restatement of the files-changed list GitHub already renders.
- Line-by-line narration of the diff. The diff is attached.
- Speculative follow-ups, "future improvements", or what you chose not to do, unless the user asked for them.
- Praise for the change, emoji headings, or a closing paragraph that repeats the Summary.
- AI attribution of any kind.

**Language rule:** the title and body are always written in English, regardless of the conversation language. Only use another language if the user explicitly asks for it in this invocation. A PR is a repository artifact read by people who were not in this conversation.

**Structure rule:** when the body has headings at all, `## Summary` comes first and the gated sections follow in table order. The one-or-two-sentence tier has no headings -- do not put a `## Summary` heading above a single sentence.

---

## Step 4 -- Present & Execute

### Flag: `--draft`

If `$ARGUMENTS` contains "draft", skip the `AskUserQuestion` step. Show the generated title and body, then immediately execute `gh pr create --draft --title "{title}" --body "..." --base {base}`.

### Default (no flag)

Two steps, both mandatory: print the preview, then ask. Do not paste the body into the `AskUserQuestion` question field -- that field is rendered as a single truncated line by some Claude Code surfaces, so a multi-line body is cut off or dropped entirely and the user is asked to approve something they cannot read.

**Step 4a -- print the preview** as normal chat output:

> **PR Title:** {title}
> **Base:** `{base_branch}` <- `{current_branch}`

Then the body verbatim inside a fenced ```markdown block, so the user sees exactly what `gh pr create` will receive.

**Step 4b -- ask, and wait for the answer:**

- **Question:** `"Create this PR?"` -- one short line. No newlines, no body text, no ANSI escape codes.
- **Header:** "Pull Request"
- **Options:**
  1. **Create PR** -- "Create pull request"
  2. **Create as Draft** -- "Create as draft pull request"
  3. **Edit** -- "Revise the title or description"
  4. **Cancel** -- "Abort without creating PR"

Printing the preview is not approval. It is only the readable copy of what the prompt is about, and it exists because the prompt cannot display it. Never run `gh pr create` without an answer from this `AskUserQuestion`. The user asking for a PR in their message is not the answer either -- that is what put the skill on this step. `--draft` is the only path that skips the prompt.

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

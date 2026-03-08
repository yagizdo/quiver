---
name: review
description: Run a multi-agent code review (code quality + security audit) with synthesized findings.
argument-hint: "[PR/MR URL | --base <branch>] [--output <path>] [--set-output <path>] [--terminal]"
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree`
```

```
!`git branch --show-current`
```

```
!`git branch --sort=-committerdate | head -8`
```

---

# Instructions

You are a review orchestrator. Your job is to determine the correct diff source, announce the review mode, dispatch multiple review agents in parallel, then synthesize their findings into a single unified report.

## Step 1 -- Determine Review Mode

Silently evaluate the conditions below in order. Use the **first** mode that matches.

### Mode 1 -- PR/MR Link Provided

If `$ARGUMENTS` contains a pull request or merge request URL from any Git platform (GitHub, GitLab, Bitbucket, Azure DevOps, etc.):

1. Detect the platform from the URL pattern. For GitHub, pass the full URL directly to `gh pr diff`. For GitLab, extract the merge request number and validate it is numeric.
   - **GitHub:** `github.com/{owner}/{repo}/pull/{number}` -- use `gh pr diff <full-URL>`
   - **GitLab:** `gitlab.com/{group}/{project}/-/merge_requests/{number}` -- extract `{number}` (must be numeric) and use `glab mr diff {number}`
   - **Bitbucket:** `bitbucket.org/{workspace}/{repo}/pull-requests/{number}` -- Bitbucket CLI lacks a direct diff command. Fall back to Mode 2 (branch diff).
   - **Other platforms:** Fall back to Mode 2 with a note:
     > Platform not recognized for direct diff fetching. Falling back to branch diff.
2. Before running a platform CLI command (`gh`, `glab`), check if the CLI is available. If not, fall back to Mode 2 with a note:
   > `{cli}` CLI not found. Falling back to branch diff.
3. Announce: `Reviewing PR/MR from provided link...`
4. If fetching fails (permissions, invalid URL), print a warning:
   > Could not fetch diff from the provided link. Falling back to branch diff.
   Then continue to Mode 2.
5. If fetching succeeds, pass the diff to the agent in Step 2.

### Mode 2 -- Branch Diff

If no PR link was provided (or Mode 1 fell back), and the current branch is **not** `main` or `master`:

1. **Determine the base branch** using one of these methods (in order):
   - **`--base` flag:** If `$ARGUMENTS` contains `--base <branch>`, use that branch directly. Skip the prompt.
   - **Interactive selection:** Otherwise, use `AskUserQuestion` to ask the user which base branch to compare against. Use the gathered branch list output to build action buttons for candidate branches. Include an **"Other (I'll type it)"** button as the last option. Phrasing:
     > You're on `{current_branch}`. Which branch should I compare against for the review?
   - If the user picks "Other (I'll type it)", ask them to type the branch name.
1b. **Validate the base branch:** Run `git rev-parse --verify {base_branch}` to confirm the ref exists.
    If it fails: > Branch `{base_branch}` not found. Please check the name and try again.
    **Stop here.**
2. Announce: `Reviewing branch {current_branch} against {base_branch}...`
3. Get the diff:
   ```
   git diff {base_branch}...HEAD
   ```
4. If the diff is empty, announce:
   > Branch diff against `{base_branch}` is empty. Checking for local uncommitted changes...
   Then continue to Mode 3.
5. Otherwise, pass the diff to the agent in Step 2.

### Mode 3 -- Uncommitted/Staged Changes

If the current branch is `main`/`master`, or the branch diff was empty:

1. Check for unstaged changes:
   ```
   git diff
   ```
2. If empty, check for staged changes:
   ```
   git diff --cached
   ```
3. If both are empty:
   > No changes to review. Commit some changes or switch to a feature branch and try again.
   **Stop here.**
4. Announce: `Reviewing local uncommitted changes...`
5. Pass the diff to the agent in Step 2.

---

## Step 2 -- Parallel Agent Dispatch

### 2a -- Discover available agents

Scan `agents/review/*.md` to find all review agents. For each `.md` file found, read its YAML frontmatter to extract the `name` and `description` fields.

### 2b -- Dispatch all agents

Spawn **all** discovered review agents simultaneously using multiple Agent tool calls in a single response. Each agent receives:
- The full diff from Step 1.
- A brief note of which mode was used and the branch/PR context.

### Adding future agents

To add a new review agent, create it under `agents/review/` and register it in `plugin.json`'s `agents` array. The orchestrator discovers and dispatches all agents in that directory automatically.

## Step 3 -- Synthesize Findings

After **all** agents return, merge their outputs into a single unified report. Follow these rules:

1. **Deduplicate.** If two agents flag the same issue (e.g., code-review's Performance phase and security-audit both flag a denial-of-service risk on the same line), keep the more detailed finding and discard the other. Prefer the specialist agent's version when depth is comparable.
2. **Unified severity.** Reclassify all findings into a single scale:
   - **Critical** -- Must fix before merge. Actively exploitable vulnerabilities, data-loss bugs, auth bypass.
   - **High** -- Strongly recommended. Performance regressions, authorization gaps, unsafe patterns.
   - **Medium** -- Should fix. Best-practice violations, maintainability concerns, defensive gaps.
   - **Low** -- Optional. Style nits, hardening opportunities, future considerations.
3. **Tag the source.** Prefix each finding with the agent that produced it for traceability:
   ```
   [SEVERITY] (code-review) file_path:line_number -- Short title
   ```
4. **Unified verdict.** Apply the strictest verdict across all agents:
   - If **any** agent produces a Critical or High finding --> **Request changes**
   - If the worst finding is Medium --> **Approve with suggestions**
   - If only Low or no findings --> **Approve**

### Synthesized report structure

```markdown
# Code Review Report

## Summary
One paragraph: what the PR does, overall risk, top-line recommendation.

## Agents Dispatched
{list each discovered agent and its verdict}

## Findings
### Critical
[merged critical findings]

### High
[merged high findings]

### Medium
[merged medium findings]

### Low
[merged low findings]

## Verdict
[Unified verdict] -- [severity counts] -- [one-line justification]
```

## Step 4 -- Save Review Report

### 4a -- Determine output destination

Evaluate in order:
1. **`--terminal` flag:** If `$ARGUMENTS` contains `--terminal`, print the full report in the terminal. Do not write a file. Skip to the terminal summary.
2. **`--set-output` flag:** If `$ARGUMENTS` contains `--set-output <path>`, use that path as the save directory **and** save it as the default for future reviews. Write (or update) a `review-preferences.md` file in your auto-memory directory:
   ```markdown
   # Review Preferences
   - report_path: <path>
   ```
   Confirm: > Default report path set to `<path>`. Future reviews will save here automatically.
3. **`--output` flag:** If `$ARGUMENTS` contains `--output <path>`, use that path as the save directory (one-time, not saved).
4. **Saved preference:** Check auto-memory for a `review-preferences` file with a `report_path` field. If found, use that path.
5. **Default:** Use `{project_root}/.claude/reports/`.

### 4b -- Write and summarize

1. Create the chosen directory if it does not exist.
2. Write the full synthesized report as `review-{timestamp}.md` (use `date '+%Y-%m-%d_%H-%M-%S'`).
3. Print a short terminal summary:
   - One-line verdict
   - Counts per severity
   - Which agents ran and their individual verdicts
   - Path to the saved report file
4. Do **not** print the full review in the terminal unless `--terminal` was used.

---

## Anti-Patterns

- **Don't** prompt the user for input **between base branch confirmation and report save** -- the review itself runs end-to-end without interaction until the save-location prompt in Step 4.
- **Don't** silently assume `main` or `master` as the base branch in Mode 2 -- always confirm with the user or require `--base`.
- **Don't** dump the full review into the terminal -- write it to the report file and show only the summary (unless the user chose "Show in terminal").
- **Don't** save review reports to system temp directories (`/tmp/`) -- always save inside the project or show in terminal, per the user's choice.
- **Don't** skip the mode announcement -- the user must know which diff source is being reviewed.
- **Don't** use `git diff` without the triple-dot (`...`) syntax for branch diffs -- two-dot diffs include unrelated upstream changes.
- **Don't** run agents sequentially -- always dispatch all agents in parallel (multiple Agent tool calls in one response).
- **Don't** present raw agent outputs side-by-side -- always synthesize into a single merged report with deduplication.
- **Don't** let duplicate findings from different agents inflate severity counts -- deduplicate before counting.
- **Don't** ignore saved review preferences -- always check auto-memory for a `review-preferences` file before defaulting in Step 4.
- **Don't** ignore the `--output` flag when provided.

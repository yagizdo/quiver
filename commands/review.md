---
name: review
description: Run a multi-agent code review (code quality + security audit + architecture analysis) with synthesized findings.
argument-hint: "[PR/MR URL | --base <branch>] [--output <path>] [--set-output <path>] [--terminal] [--comment-pr]"
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree`
```

```
!`git branch --show-current`
```

```
!`git branch --sort=-committerdate`
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

If no PR link was provided (or Mode 1 fell back), and **any** of the following are true: (a) `$ARGUMENTS` contains `--base <branch>`, or (b) the current branch is **not** `main` or `master`:

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

## Step 1.5 -- Build Diff Manifest

After obtaining the diff, analyze the list of changed files and classify each one. Build a text manifest using the taxonomy below:

| Type | Matched by | Security relevance |
|------|-----------|-------------------|
| `PROMPT` | `commands/*.md`, `agents/**/*.md`, `skills/**/*.md` with YAML frontmatter | Low -- instructions to LLM |
| `SCRIPT` | `hooks/scripts/*.sh`, `*.py`, `*.rb` (executable) | High |
| `CONFIG-APP` | App configuration: auth, database, CI/CD, environment, secrets files (`*.json`, `*.yaml`, `*.toml` containing app settings, credentials, or infrastructure) | High |
| `CONFIG-MANIFEST` | Package/plugin registries: `plugin.json`, `package.json`, lockfiles, `tsconfig.json`, `*.toml` build configs — structural metadata only | Low |
| `CODE` | Application source (JS, TS, Go, etc.) | High |
| `DOCS` | `*.md` outside command/agent/skill dirs, `README*`, `CHANGELOG*` | Low |

Format the manifest as a simple list:

```
Diff Manifest:
- commands/review.md → PROMPT (low security relevance)
- hooks/scripts/pre-compact-handover.sh → SCRIPT (high security relevance)
- plugin.json → CONFIG-MANIFEST (low security relevance)
- .env.example → CONFIG-APP (high security relevance)
```

Include risk signals if present: new dependencies, auth changes, secrets handling, new endpoints.

---

## Step 2 -- Parallel Agent Dispatch

### 2a -- Discover available agents

Discover agents using a two-tier registry:

**Tier 1 — Review agents (dynamic):** Scan `agents/review/*.md`. For each `.md` file, read its YAML frontmatter to extract `name` and `description`.

**Tier 2 — External specialists (explicit):** Also include these agents from outside the review directory:
- `agents/research/best-practices-researcher.md`

For Tier 2 agents, read the frontmatter the same way. If a Tier 2 file is missing or unreadable, skip it silently — do not fail the review.

**Agent type identifiers** use the format `quiver:{name}` where `{name}` is the frontmatter `name` field. The category subdirectory is organizational only -- it is NOT part of the identifier. Examples:
- `agents/review/code-review.md` → `quiver:code-review`
- `agents/research/best-practices-researcher.md` → `quiver:best-practices-researcher`

### 2b -- Conditional Dispatch

Apply dispatch rules based on the Diff Manifest from Step 1.5:

- **`code-review`**: Always dispatched.
- **`security-audit`**: Only dispatched when the diff contains at least one `SCRIPT`, `CODE`, or `CONFIG-APP` file. Skip when all files are `PROMPT`, `DOCS`, or `CONFIG-MANIFEST`:
  > Skipping security-audit: no application code, scripts, or security-relevant configuration changed.
- **`best-practices-researcher`**: Only dispatched when the diff contains at least one `SCRIPT` or `CODE` file. Configuration files (both `CONFIG-APP` and `CONFIG-MANIFEST`) do not trigger this agent since they lack framework/library code to research. If dispatched, its prompt must include the list of changed files with their detected languages/frameworks so it can target its context7 lookups. Skip with a note otherwise:
  > Skipping best-practices-researcher: no application code or scripts changed.
- **`architecture-strategist`**: Only dispatched when the diff contains at least one `SCRIPT`, `CODE`, or `CONFIG-APP` file. If dispatched, its prompt must include the project's root file listing (`ls` of the project root) so it can map conventions in Phase 1. Skip when all files are `PROMPT`, `DOCS`, or `CONFIG-MANIFEST`:
  > Skipping architecture-strategist: no application code, scripts, or structural configuration changed.
- **Future agents**: Check the agent's description against the file classifications in the manifest. Skip agents whose scope does not overlap with any changed file type. Treat `CONFIG-MANIFEST` files as low-signal — only agents specifically concerned with project structure or dependency management should trigger on them.

Spawn qualifying agents simultaneously using multiple Agent tool calls in a single response. Use the `quiver:{name}` identifier format described above as the `subagent_type`.

Each agent receives (in this order):
1. The **Diff Manifest** from Step 1.5.
2. A **scope reminder**: "Your findings MUST be scoped to code CHANGED in this diff. Respect file classifications in the Diff Manifest."
3. **Review context**: mode used, branches, PR URL (if applicable).
4. The **full diff** from Step 1.

### Adding future agents

- **Review-scoped agents:** Create under `agents/review/` and register in `plugin.json`'s `agents` array. The orchestrator discovers them automatically via Tier 1.
- **Cross-category agents:** Create under `agents/<category>/`, register in `plugin.json`, and add the path to the Tier 2 list in Step 2a. Add a dispatch rule in Step 2b.

## Step 3 -- Synthesize Findings

After **all** agents return, merge their outputs into a single unified report. Follow these rules:

1. **Deduplicate.** If two agents flag the same issue (e.g., code-review's Performance phase and security-audit both flag a denial-of-service risk on the same line, or code-review and architecture-strategist both flag a coupling concern), keep the more detailed finding and discard the other. Prefer the specialist agent's version when depth is comparable.
2. **Unified severity.** Reclassify all findings into a single scale:
   - **Critical** -- Must fix before merge. Actively exploitable vulnerabilities, data-loss bugs, auth bypass.
   - **High** -- Strongly recommended. Performance regressions, authorization gaps, unsafe patterns.
   - **Medium** -- Should fix. Best-practice violations, maintainability concerns, defensive gaps.
   - **Low** -- Optional. Style nits, hardening opportunities, future considerations.
3. **Tag the source.** Prefix each finding with the agent that produced it for traceability:
   ```
   [SEVERITY] (code-review) file_path:line_number -- Short title
   ```
4. **Filter false positives.** Before finalizing, apply these noise filters:
   - **Prompt-vs-code confusion**: If an agent flagged a security or code quality issue in a `PROMPT` file and treats the prompt text as executable code (e.g., "shell injection" in a `!backtick` block, "missing input validation" on a CLI instruction) → DISCARD. Record as filtered false positive.
   - **Misapplied doc lookups on prompts**: If an agent used context7 doc lookups to flag CLI tool usage, shell syntax, or framework mentions in a `PROMPT` file as "best practice violations" (e.g., "deprecated CLI flag", "missing error handling in shell example") → DISCARD. Only keep doc-sourced findings on prompt files if they identify a genuinely broken or deprecated API reference.
   - **Contradictions**: If two agents produce contradictory findings (one says "add X", another says "remove X") → keep the one aligned with existing codebase conventions, discard the other. If neither aligns, discard both. Record as filtered contradiction.
   - **Out-of-scope findings**: If a finding references code NOT changed in the diff and does not argue that the diff worsened it → DISCARD. Record as filtered out-of-scope.
   - **Severity inflation**: If a finding's severity relies on a hypothetical scenario ("an attacker could...", "in the future this might...") rather than a concrete, demonstrable consequence → DOWNGRADE to Low. If it was already Low, keep it.
   - **Aspirational refactoring**: If a finding suggests restructuring working code for theoretical cleanliness, extensibility, or "better design" without identifying a concrete problem → DISCARD. Record as filtered aspirational.
   - **Subjective style opinions**: If a finding flags naming, formatting, or structural preferences where reasonable developers would disagree → DISCARD. Record as filtered stylistic.
5. **Unified verdict.** Apply the strictest verdict across all agents (using only non-filtered findings):
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

## Architectural Assessment
{If architecture-strategist ran: include its Architecture Context (3-5 bullets) and Structural Summary here. If it did not run or returned empty, omit this section entirely.}

## Findings
### Critical
[merged critical findings]

### High
[merged high findings]

### Medium
[merged medium findings]

### Low
[merged low findings]

## Filtered Findings
{count} findings were filtered as false positives or out-of-scope:
- [brief reason for each, e.g., "Prompt-vs-code: shell injection flagged in commands/review.md !backtick block"]

(Omit this section entirely if no findings were filtered.)

## Verdict
[Unified verdict] -- [severity counts] -- [one-line justification]
```

<!-- SYNC: This report format is parsed by skills/work/SKILL.md Phase 4c (review finding verification). If you change the report structure (section headings, finding format), update the verification parsing logic there. -->

## Step 4 -- Save Review Report

### 4a -- Determine output destination

Evaluate in order:
1. **`--terminal` flag:** If `$ARGUMENTS` contains `--terminal`, print the full report in the terminal. Do not write a file. Skip to the terminal summary.
2. **`--set-output` flag:** If `$ARGUMENTS` contains `--set-output <path>`, use that path as the save directory **and** save it as the default for future reviews. **Path validation:** Before saving, verify the path matches the allowlist pattern `[a-zA-Z0-9_./ -]+` (letters, digits, dots, underscores, slashes, hyphens, spaces). Additionally, reject any path that starts with `/` (absolute paths) or where any path segment (split by `/`) equals `..` to prevent directory traversal outside the project root. Reject anything else. If invalid, warn the user and do not write the preference. Write (or update) a `review-preferences.md` file in your auto-memory directory:
   ```markdown
   # Review Preferences
   - report_path: <path>
   ```
   Confirm: > Default report path set to `<path>`. Future reviews will save here automatically.
3. **`--output` flag:** If `$ARGUMENTS` contains `--output <path>`, use that path as the save directory (one-time, not saved). Apply the same path validation as `--set-output` (allowlist pattern, reject absolute paths and `..` path segments).
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

## Step 5 -- Post to PR (Optional)

This step enables posting the review report as a PR comment. It is **strictly opt-in** and never runs automatically.

### 5a -- Determine if PR commenting applies

Evaluate in order:

1. **`--comment-pr` flag:** If `$ARGUMENTS` contains `--comment-pr`, skip the prompt and proceed directly to 5b.
2. **PR context available:** If Mode 1 was used (a PR/MR URL was provided), ask the user:
   > Review saved. Would you like to post this report as a comment on the PR?
   Use `AskUserQuestion` with action buttons: **"Yes, post to PR"** and **"No thanks"**.
   - If the user selects "No thanks" or dismisses, **stop here**. Do not post.
3. **No PR context:** If Mode 2 or Mode 3 was used and no PR URL was provided, attempt to detect an active PR for the current branch:
   - **GitHub:** `gh pr view --json url,number --jq '.url' 2>/dev/null`
   - **GitLab:** `glab mr view --output json 2>/dev/null`
   - If detection succeeds and `--comment-pr` was passed, proceed to 5b using the detected PR.
   - If detection succeeds but `--comment-pr` was NOT passed, do not prompt -- skip silently. The user must explicitly opt in via the flag when no PR URL was provided.
   - If detection fails, skip silently. Do not warn or error.

### 5b -- Post the comment

1. **Read the saved report** from the path determined in Step 4b.
2. **Post using the platform CLI:**
   - **GitHub:** `gh pr comment {pr_number_or_url} --body-file {report_path}`
   - **GitLab:** `glab mr comment {mr_number} --message "$(cat {report_path})"`
   - For other platforms: print a note and skip:
     > PR commenting is not supported for this platform. You can manually paste the report from: `{report_path}`
3. **Confirm success:**
   > Review posted as a comment on {pr_url}.
4. **Handle failure gracefully:** If the CLI command fails (permissions, network, etc.):
   > Could not post the review to the PR. The report is saved at: `{report_path}`
   Do not retry. Do not error out.

---

## Anti-Patterns

- **Don't** prompt the user for input **between base branch confirmation and report save** -- the review itself runs end-to-end without interaction until the save-location prompt in Step 4.
- **Don't** silently assume `main` or `master` as the base branch in Mode 2 -- always confirm with the user or require `--base`.
- **Don't** dump the full review into the terminal -- write it to the report file and show only the summary (unless the user chose "Show in terminal").
- **Don't** save review reports to system temp directories (`/tmp/`) -- always save inside the project or show in terminal, per the user's choice.
- **Don't** skip the mode announcement -- the user must know which diff source is being reviewed.
- **Don't** use two-dot `git diff <base>..<head>` for branch diffs -- two-dot diffs include unrelated upstream changes. Bare `git diff` (no arguments) is correct for Mode 3 uncommitted changes.
- **Don't** run agents sequentially -- always dispatch all agents in parallel (multiple Agent tool calls in one response).
- **Don't** present raw agent outputs side-by-side -- always synthesize into a single merged report with deduplication.
- **Don't** let duplicate findings from different agents inflate severity counts -- deduplicate before counting.
- **Don't** ignore saved review preferences -- always check auto-memory for a `review-preferences` file before defaulting in Step 4.
- **Don't** ignore the `--output` flag when provided.
- **Don't** post a PR comment without explicit user consent -- `--comment-pr` flag or interactive confirmation are the only valid triggers.
- **Don't** prompt to post a PR comment when no PR context exists (Mode 2/3 without `--comment-pr`) -- skip silently.
- **Don't** hardcode platform tokens, repository URLs, or API endpoints -- rely on `gh`/`glab` CLIs which manage their own authentication.
- **Don't** retry or error out if PR comment posting fails -- warn and move on.

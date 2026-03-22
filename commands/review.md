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

### Re-review detection (all modes)

After obtaining the diff, check if a previous review report exists for this branch:

1. Scan the report directory (`.claude/reports/` or saved preference path) for `review-*.md` files.
2. **Filter by branch.** For each report found, read its `## Review Context` section and check the `Branch` field. Only consider reports that match the current branch. Discard reports for other branches.
3. If one or more matching reports exist, read the most recent one and extract its findings and metadata.
4. **Calculate iteration number**: Read the previous report's `## Review Context` section. Extract the `Iteration` value and increment by 1. If the previous report has no `Iteration` field, this is iteration 2.
5. **Extract previous HEAD commit**: Read the `HEAD at review` field from the previous report's `## Review Context`. Use this SHA to compute the delta diff: `git diff {previous_head_sha}...HEAD`. If the field is missing, fall back to using the report's filename timestamp to estimate the commit range via `git log --after="{timestamp}" --format=%H`.
6. This is a **re-review**. Apply these constraints:
   - **Scope lock**: Only flag findings that are (a) NEW issues introduced by commits made AFTER the previous review's timestamp, or (b) regressions where a previously-addressed finding has reappeared.
   - **No scope expansion**: Do NOT flag pre-existing patterns, stylistic preferences, or aspirational improvements that were not in the original review. The original review had the chance to flag these -- if it didn't, they are accepted.
   - **Idempotency check**: If the diff between the previous review and now contains NO functional code changes (only whitespace, comments, or formatting), the verdict MUST be "Approve" with zero findings.
   - When populating the report template's `## Review Context` section, set `Iteration` to {N}, `Previous report` to the path of the matched report, `Scope` to "Delta-only (changes since previous review)", and add a `Delta` line with `{commit_count} commits, {files_changed} files`.
7. Pass the re-review context and scope constraints to all agents in Step 2.

---

## Step 1.5 -- Build Diff Manifest

After obtaining the diff, analyze the list of changed files and classify each one. Build a text manifest using the taxonomy below:

| Type | Matched by | Security relevance |
|------|-----------|-------------------|
| `PROMPT` | `commands/*.md`, `agents/**/*.md`, `skills/**/*.md` with YAML frontmatter | Low -- instructions to LLM |
| `SCRIPT` | `*.sh` (anywhere, not just hooks/), `Makefile`, `Dockerfile`, `*.py`/`*.rb` (executable), CI workflow files (`.github/workflows/*.yml`, `.gitlab-ci.yml`) | High |
| `CONFIG-APP` | App configuration: auth, database, CI/CD environment, secrets files (`*.json`, `*.yaml`, `*.toml` containing app settings, credentials, or infrastructure) | High |
| `CONFIG-MANIFEST` | Package/plugin registries: `plugin.json`, `package.json`, lockfiles, `tsconfig.json`, `*.toml` build configs, `.gitignore`, `.editorconfig`, `.dockerignore` -- structural metadata only | Low |
| `CODE` | Application source (JS, TS, Go, Dart, etc.) | High |
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
- `agents/research/project-context-analyst.md`

For Tier 2 agents, read the frontmatter the same way. If a Tier 2 file is missing or unreadable, skip it silently — do not fail the review.

**Agent type identifiers** use the format `quiver:{name}` where `{name}` is the frontmatter `name` field. The category subdirectory is organizational only -- it is NOT part of the identifier. Examples:
- `agents/review/waste-detector.md` → `quiver:waste-detector`
- `agents/research/best-practices-researcher.md` → `quiver:best-practices-researcher`

### 2b -- Conditional Dispatch

Apply dispatch rules based on the Diff Manifest from Step 1.5:

- **`waste-detector`**: Always dispatched. Replaces the former `code-review` agent. Evaluates every changed file for unnecessary additions, redundancy with existing codebase, dead paths, and over-engineering.
- **`project-context-analyst`**: Always dispatched. Searches git history, project memory, and docs for institutional knowledge relevant to the changed files. Provides context that informs other agents' findings.
- **`security-audit`**: Only dispatched when the diff contains at least one `SCRIPT`, `CODE`, or `CONFIG-APP` file. Skip when all files are `PROMPT`, `DOCS`, or `CONFIG-MANIFEST`:
  > Skipping security-audit: no application code, scripts, or security-relevant configuration changed.
- **`best-practices-researcher`**: Only dispatched when the diff contains at least one `SCRIPT` or `CODE` file. Configuration files (both `CONFIG-APP` and `CONFIG-MANIFEST`) do not trigger this agent since they lack framework/library code to research. If dispatched, its prompt must include the list of changed files with their detected languages/frameworks so it can target its context7 lookups. Skip with a note otherwise:
  > Skipping best-practices-researcher: no application code or scripts changed.
- **`architecture-strategist`**: Only dispatched when the diff contains at least one `SCRIPT`, `CODE`, or `CONFIG-APP` file. If dispatched, its prompt must include the project's root file listing (`ls` of the project root) so it can map conventions in Phase 1. Skip when all files are `PROMPT`, `DOCS`, or `CONFIG-MANIFEST`:
  > Skipping architecture-strategist: no application code, scripts, or structural configuration changed.
- **`developer-experience-auditor`**: Only dispatched when the diff contains at least one `SCRIPT` or `CODE` file. Evaluates discoverability, error message quality, debugging experience, and automation-readiness. Skip when no code/scripts changed:
  > Skipping developer-experience-auditor: no application code or scripts changed.
- **Future agents**: Check the agent's description against the file classifications in the manifest. Skip agents whose scope does not overlap with any changed file type. Treat `CONFIG-MANIFEST` files as low-signal — only agents specifically concerned with project structure or dependency management should trigger on them.

Spawn qualifying agents simultaneously using multiple Agent tool calls in a single response. Use the `quiver:{name}` identifier format described above as the `subagent_type`.

Each agent receives (in this order):
1. The **Diff Manifest** from Step 1.5.
2. A **scope reminder**: "Your findings MUST be scoped to code CHANGED in this diff. Respect file classifications in the Diff Manifest."
3. **Review context**: mode used, branches, PR URL (if applicable).
4. **Re-review context** (if applicable): "This is re-review iteration {N}. ONLY flag issues that are NEW in the delta since the previous review or regressions of previously-fixed findings. Do NOT flag pre-existing patterns, stylistic preferences, or aspirational improvements. If the delta contains no functional changes, return zero findings."
5. The **full diff** from Step 1. For re-reviews, also include the delta diff (`git diff {previous_head_sha}...HEAD`).

### Adding future agents

- **Review-scoped agents:** Create under `agents/review/` and register in `plugin.json`'s `agents` array. The orchestrator discovers them automatically via Tier 1.
- **Cross-category agents:** Create under `agents/<category>/`, register in `plugin.json`, and add the path to the Tier 2 list in Step 2a. Add a dispatch rule in Step 2b.

## Step 3 -- Synthesize Findings

After **all** agents return, merge their outputs into a single unified report. Follow these rules:

1. **Deduplicate with consensus tracking.** If two or more agents flag the same issue (e.g., waste-detector's Redundancy Scan and architecture-strategist both flag unnecessary duplication, or security-audit and best-practices-researcher both flag an unsafe dependency pattern), keep the more detailed finding and discard the other. Prefer the specialist agent's version when depth is comparable. **Record which agents flagged it** -- when 2+ agents independently flag the same issue, add a `Flagged by:` annotation listing all agents. Multi-agent consensus increases confidence; when 3+ agents flag the same issue, consider upgrading its severity by one tier (e.g., Medium -> High) unless it is already Critical.
2. **Unified severity.** Reclassify all findings into a single scale:
   - **Critical** -- Must fix before merge. Actively exploitable vulnerabilities, data-loss bugs, auth bypass. CI secret exposure (logs, artifacts) qualifies.
   - **High** -- Strongly recommended. Performance regressions, authorization gaps, unsafe patterns. CI issues that silently produce wrong results or deploy wrong artifacts qualify.
   - **Medium** -- Should fix. Best-practice violations, maintainability concerns, defensive gaps. CI configuration failures that cause visible build errors (missing dependencies, wrong paths) are capped here -- a failing CI pipeline is a guardrail working as intended.
   - **Low** -- Optional. Style nits, hardening opportunities, future considerations.

   **CI severity cap:** Configuration issues that cause CI to fail visibly (build errors, missing tools, wrong paths) are capped at Medium. Reserve High for CI issues that silently produce wrong results or expose secrets. Rationale: a failing CI pipeline blocks bad code from merging -- it is self-evident on first run and easily fixed.
3. **Tag the source.** Prefix each finding with the agent that produced it for traceability. When 2+ agents flagged the same issue, include the `Flagged by:` annotation:
   ```
   [SEVERITY] (waste-detector) file_path:line_number -- Short title
   Flagged by: waste-detector, architecture-strategist
   ```
   The `Flagged by:` line only appears when 2+ agents independently flagged the same issue.
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
6. **Identify strengths.** From agent outputs and diff analysis, identify 2-5 positive aspects of the changes. Look for:
   - Net negative LOC (code removal is good)
   - Correct use of established project patterns
   - Good test coverage additions
   - Proper error handling
   - Clean abstractions or well-chosen framework conventions
   If the diff has no notable strengths, omit the "What's Working Well" section rather than fabricating praise.
7. **Compute fix order.** Rank non-filtered findings of Medium severity or above into a prioritized action plan:
   1. Severity (Critical first)
   2. Dependency (if fix A must happen before fix B, A goes first)
   3. Effort (quick wins before large refactors within same severity)
   If there are 0-2 findings of Medium+, omit the "Recommended Fix Order" section -- a table with 1-2 rows adds no value.

### Synthesized report structure

```markdown
# Code Review Report

## Review Context
- **Branch**: {current branch name}
- **Mode**: {branch diff | PR | uncommitted}
- **Iteration**: {1 if first review, N if re-review}
- **Previous report**: {path or "N/A"}
- **Scope**: {Full diff | Delta-only (changes since previous review)}
- **Delta**: {commit_count} commits, {files_changed} files since previous review (omit for first review)
- **HEAD at review**: {output of `git rev-parse --short HEAD`}

## Summary
One paragraph: what the PR does, overall risk, top-line recommendation.

## Agents Dispatched
{list each discovered agent and its verdict}

## What's Working Well
{2-5 bullet points highlighting positive aspects of the changes. Each item is one sentence, no severity ratings. Omit this section entirely if the diff has no notable strengths -- do not fabricate praise.}

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

{For findings flagged by 2+ agents, include the annotation: "Flagged by: agent1, agent2"}

## Recommended Fix Order
{Prioritized action plan for findings of Medium severity or above. Omit this section if 0-2 findings qualify.}

| Priority | Finding | Severity | Effort |
|----------|---------|----------|--------|
| 1 | [Short title with file:line] | Critical | ~X min |
| 2 | [Short title with file:line] | High | ~X min |
| ... | ... | ... | ... |

## Filtered Findings

**{N} findings reported, {M} filtered** ({classification breakdown, e.g., "3 out-of-scope, 2 aspirational, 1 subjective style"})

- [brief reason for each, e.g., "~~[Medium] (waste-detector) config/routes.rb:15 -- Consider extracting nested routes~~ -- Aspirational: working code, no concrete problem"]

(Omit this section entirely if no findings were filtered.)

## Verdict
[Unified verdict] -- [severity counts] -- [one-line justification]
```

<!-- SYNC: This report format is parsed by skills/work/SKILL.md Phase 4c (review finding verification). If you change the report structure (section headings, finding format), update the verification parsing logic there. New sections (What's Working Well, Recommended Fix Order) are additive and do not affect Phase 4c parsing. -->

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

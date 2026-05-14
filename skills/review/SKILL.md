---
name: review
description: Run a multi-agent code review (code quality + security audit + architecture analysis) with synthesized findings. Pass --with-codex for cross-model coverage via the OpenAI Codex CLI.
argument-hint: "[PR/MR URL | --base <branch>] [--output <path>] [--set-output <path>] [--terminal] [--comment-pr] [--with-codex]"
disable-model-invocation: true
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree 2>/dev/null || echo "NO_GIT"`
```

```
!`git branch --show-current 2>/dev/null || echo "NO_GIT"`
```

```
!`git branch --sort=-committerdate 2>/dev/null || echo "NO_GIT"`
```

---

# Instructions

You are a review orchestrator. Your job is to determine the correct diff source, announce the review mode, dispatch multiple review agents in parallel, then synthesize their findings into a single unified report.

## Step 0 -- Git Availability

If any gather-context block above returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected. /review requires a git repo.`
**Stop here.**

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
- skills/review/SKILL.md → PROMPT (low security relevance)
- hooks/scripts/pre-compact-handover.sh → SCRIPT (high security relevance)
- plugin.json → CONFIG-MANIFEST (low security relevance)
- .env.example → CONFIG-APP (high security relevance)
```

Include risk signals if present: new dependencies, auth changes, secrets handling, new endpoints.

---

## Step 1.75 -- LSP Detection

Before dispatching agents, detect LSP availability once. Follow the detection flow from the `code-navigation` skill:

1. Check project memory for a cached LSP preference (`lsp_preference.md`). If `lsp_declined` or `lsp_confirmed` is found, use the cached value and skip to step 4.
2. Attempt a lightweight LSP probe (e.g., `documentSymbol` on any source file from the project root).
3. If LSP is not available, detect the project language from manifest files and use `AskUserQuestion` to suggest installation:
   > LSP is not available for this project. Installing a language server (e.g., {recommended_server} for {language}) would enable better code navigation -- go-to-definition, find-references, and symbol search. Would you like to set it up? (You can always use /review without it -- grep-based navigation works fine.)

   Buttons: `["Yes, help me set it up", "No, continue with grep"]`

   - If user accepts: provide installation instructions, re-probe, cache `lsp_confirmed` in project memory.
   - If user declines: cache `lsp_declined` in project memory.
4. Set `lsp_available` to `true` or `false`. Pass this flag to agents that search the broader codebase (waste-detector, architecture-strategist) in Step 2.

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

- **`waste-detector`**: Always dispatched. Evaluates every changed file for unnecessary additions, redundancy with existing codebase, dead paths, and over-engineering.
- **`project-context-analyst`**: Always dispatched. Searches git history, project memory, and docs for institutional knowledge relevant to the changed files. Provides context that informs other agents' findings.
- **`security-audit`**: Only dispatched when the diff contains at least one `SCRIPT`, `CODE`, or `CONFIG-APP` file. Skip when all files are `PROMPT`, `DOCS`, or `CONFIG-MANIFEST`:
  > Skipping security-audit: no application code, scripts, or security-relevant configuration changed.
- **`best-practices-researcher`**: Only dispatched when the diff contains at least one `SCRIPT` or `CODE` file. Configuration files (both `CONFIG-APP` and `CONFIG-MANIFEST`) do not trigger this agent since they lack framework/library code to research. If dispatched, its prompt must include the list of changed files with their detected languages/frameworks so it can target its context7 lookups. Skip with a note otherwise:
  > Skipping best-practices-researcher: no application code or scripts changed.
- **`architecture-strategist`**: Only dispatched when the diff contains at least one `SCRIPT`, `CODE`, or `CONFIG-APP` file. If dispatched, its prompt must include the project's root file listing (`ls` of the project root) so it can map conventions in Phase 1. Skip when all files are `PROMPT`, `DOCS`, or `CONFIG-MANIFEST`:
  > Skipping architecture-strategist: no application code, scripts, or structural configuration changed.
- **`developer-experience-auditor`**: Only dispatched when the diff contains at least one `SCRIPT` or `CODE` file. Evaluates discoverability, error message quality, debugging experience, and automation-readiness. Skip when no code/scripts changed:
  > Skipping developer-experience-auditor: no application code or scripts changed.
- **`logic-reviewer`**: Only dispatched when the diff contains at least one `SCRIPT` or `CODE` file. Traces each changed function's inputs through branches to verify logical correctness. Skip when all files are `PROMPT`, `DOCS`, or `CONFIG-MANIFEST`:
  > Skipping logic-reviewer: no application code or scripts changed.
- **`test-reviewer`**: Only dispatched when the diff contains at least one `SCRIPT` or `CODE` file. Evaluates test assertion strength, regression detection power, and risk-based coverage gaps. Skip when all files are `PROMPT`, `DOCS`, or `CONFIG-MANIFEST`:
  > Skipping test-reviewer: no application code or scripts changed.
- **`stress-tester`**: Only dispatched when the diff contains at least one `SCRIPT` or `CODE` file. Constructs failure scenarios via assumption stress, composition fracture, and cascade chains. Receives depth calibration context: diff manifest file types + detected risk signals. Skip when all files are `PROMPT`, `DOCS`, or `CONFIG-MANIFEST`:
  > Skipping stress-tester: no application code or scripts changed.
- **`codex-code-reviewer`**: Only dispatched when `$ARGUMENTS` contains `--with-codex` AND the `codex` CLI is detected on PATH. This agent is a transport adapter that delegates the review to OpenAI Codex via the `codex` CLI; the actual reviewing is performed by Codex, not Claude. The Codex agent runs in parallel with all qualifying Claude review agents, providing cross-model "third eye" coverage. The CLI presence check is a Bash tool call the orchestrator performs at dispatch time (`command -v codex >/dev/null 2>&1 && echo PRESENT || echo MISSING`); do not place this check inside a `!` block in this command file (R3 forbids logic-bearing pipes in shell blocks). Skip with notes otherwise:
  > Skipping codex-code-reviewer: --with-codex flag not provided.
  > Skipping codex-code-reviewer: codex CLI not found on PATH. Install with `npm install -g @openai/codex` (>= 0.123.0) or run `/codex:setup` from the openai/codex-plugin-cc plugin.
- **`report-checker`**: Never dispatched in Step 2. This agent is a post-synthesis quality gate, dispatched only in Step 3.5 after the report is assembled. Skip silently during agent discovery.
- **Future agents**: Check the agent's description against the file classifications in the manifest. Skip agents whose scope does not overlap with any changed file type. Treat `CONFIG-MANIFEST` files as low-signal — only agents specifically concerned with project structure or dependency management should trigger on them.

Spawn qualifying agents simultaneously using multiple Agent tool calls in a single response. Use the `quiver:{name}` identifier format described above as the `subagent_type`.

Each agent receives (in this order):
1. The **Diff Manifest** from Step 1.5.
2. A **scope reminder**: "Your findings MUST be scoped to code CHANGED in this diff. Respect file classifications in the Diff Manifest."
3. **Review context**: mode used, branches, PR URL (if applicable).
4. **Re-review context** (if applicable): "This is re-review iteration {N}. ONLY flag issues that are NEW in the delta since the previous review or regressions of previously-fixed findings. Do NOT flag pre-existing patterns, stylistic preferences, or aspirational improvements. If the delta contains no functional changes, return zero findings."
5. The **full diff** from Step 1. For re-reviews, also include the delta diff (`git diff {previous_head_sha}...HEAD`).
6. **File scope reminder**: "Review ALL file types in the diff regardless of language or type -- shell scripts, config files, CI configs, and build scripts deserve the same scrutiny as application source code."
7. **Citation accuracy**: "Every file:line reference in your findings must be verified by reading the file. Do not cite line numbers from memory or inference -- use the Read tool to confirm the content at the cited line before including it in a finding."
8. **LSP availability** (for waste-detector, architecture-strategist, and stress-tester): `lsp_available: {true|false}` from Step 1.75. These agents search the broader codebase and benefit from LSP-first navigation. Other agents are diff-scoped and do not need this flag.
9. **Scope discipline**: Aspirational improvements, stylistic preferences, "could be better" suggestions, and theoretical hardening are out of scope. Flag only concrete demonstrable problems with code that is wrong, unsafe, or broken as written. If the code works correctly as written and you would not fix it yourself, do not flag it. Zero findings is a correct and expected result on clean code. (This clause applies on every review. Re-review mode adds additional delta-specific scope on top of this general lock.)

### Adding future agents

- **Review-scoped agents:** Create under `agents/review/` and register in `plugin.json`'s `agents` array. The orchestrator discovers them automatically via Tier 1.
- **Cross-category agents:** Create under `agents/<category>/`, register in `plugin.json`, and add the path to the Tier 2 list in Step 2a. Add a dispatch rule in Step 2b.

## Step 3 -- Synthesize Findings

After **all** agents return, merge their outputs into a single unified report. Follow these rules:

**0. Filter on substance, not citation form.** When a finding's underlying observation is verifiable in the codebase but its citation is malformed (wrong line number, off-by-N, points to a blank line or unrelated content), **correct the citation rather than discard the finding**. Use grep or file search to locate the described content; if found, update the `file:line` reference and keep the finding. Only discard as a phantom citation when the described content does not appear anywhere in the cited file (true fabrication). Do not use citation-format filters to drop findings whose underlying defects you have verified to exist. The phantom-citation filter (item 4 below) exists to suppress hallucinations, not to dismiss substantive observations on a technicality. This rule applies to every agent's output but is most relevant for external transport adapters like `codex-code-reviewer`, where line-number drift between diff hunk position and absolute file line is a common LLM error.

1. **Deduplicate with consensus tracking.** If two or more agents flag the same issue (e.g., waste-detector's Redundancy Scan and architecture-strategist both flag unnecessary duplication, or security-audit and best-practices-researcher both flag an unsafe dependency pattern), keep the more detailed finding and discard the other. Prefer the specialist agent's version when depth is comparable. **Record which agents flagged it** -- when 2+ agents independently flag the same issue, add a `Flagged by:` annotation listing all agents. Multi-agent consensus increases confidence; when 3+ agents flag the same issue, consider upgrading its severity by one tier (e.g., Medium -> High) unless it is already Critical.

   **Subsumption rule.** After deduplication, check for parent-child relationships between remaining findings. If a narrow finding is a direct symptom, consequence, or subset of a broader finding, **absorb** the narrow finding into the broader one instead of listing it separately. **Parent selection:** Choose the finding that better explains the root cause or connects to project conventions/architecture as the parent -- not necessarily the one with higher severity. A LOW finding that explains "this breaks the project's convention X" is a better parent than a HIGH finding that only says "unused import." After absorption, re-evaluate the parent's severity considering the absorbed findings' consensus signals. Add an `Also noted:` line under the parent finding listing the absorbed item(s) and which agents flagged them. Do not count absorbed findings as separate entries in severity tallies or the fix order table. **Guard:** Only absorb when the narrow finding would be **automatically resolved** by fixing the parent finding. If fixing the parent would NOT eliminate the narrow finding, they are independent -- list both separately. Example:
   Example: A diff replaces library A with library B. The architecture-strategist flags the migration as a HIGH architectural concern. The waste-detector separately flags a leftover import from library A as LOW. Since removing library A automatically eliminates the stale import, the LOW finding is absorbed:
   ```
   [HIGH] (architecture-strategist) models/foo.dart -- Library A replaced with Library B, breaking codebase convention
   Flagged by: architecture-strategist, project-context-analyst
   Also noted: Stale library-A import left behind (flagged by 5 agents) -- automatically resolved by completing the migration.
   ```
2. **Unified severity.** Reclassify all findings into a single scale:
   - **Critical** -- Must fix before merge. Actively exploitable vulnerabilities, data-loss bugs, auth bypass. CI secret exposure (logs, artifacts) qualifies.
   - **High** -- Strongly recommended. Performance regressions, authorization gaps, unsafe patterns. CI issues that silently produce wrong results or deploy wrong artifacts qualify.
   - **Medium** -- Should fix. Best-practice violations, maintainability concerns, defensive gaps. CI configuration failures that cause visible build errors (missing dependencies, wrong paths) are capped here -- a failing CI pipeline is a guardrail working as intended.
   - **Low** -- Optional. Style nits, hardening opportunities, future considerations.

   **CI severity cap:** Configuration issues that cause CI to fail visibly (build errors, missing tools, wrong paths) are capped at Medium. Reserve High for CI issues that silently produce wrong results or expose secrets. Rationale: a failing CI pipeline blocks bad code from merging -- it is self-evident on first run and easily fixed.
3. **Tag the source.** Prefix each finding with the agent that produced it for traceability. When 2+ agents flagged the same issue, include the `Flagged by:` annotation:
   ```
   [ID] [SEVERITY] (waste-detector) file_path:line_number -- Short title
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
   - **Phantom citations**: For each finding with a `file_path:line_number` reference, verify the citation. Apply this graduated check (per Step 3 item 0, do NOT default to DISCARD on the first mismatch):
     - **(a) `file_path` must exist in the repository.** If not → DISCARD as filtered phantom citation. (True fabrication: cited file does not exist.)
     - **(b) `line_number` must fall within the file's actual line count.** If not → DISCARD as filtered phantom citation. (True fabrication: cited line is past EOF.)
     - **(c) If the finding describes specific content at that line and the cited line's actual content does NOT match**, do not discard immediately. **Recovery procedure:** Search the file for the described content (grep distinctive snippets, key tokens, or quoted phrases from the finding body). Three outcomes:
       1. **Found at a different line:** correct the citation to the new line and keep the finding. Add a brief `Citation corrected: original line N -> actual line M` note in the finding body for transparency.
       2. **Found but ambiguous (multiple plausible matches):** keep the finding with the original citation and add `Citation note: line uncertain, content present in file at lines [list]`. Do not discard.
       3. **Not found anywhere in the cited file:** this is the true fabrication case → DISCARD as filtered phantom citation.
     - This filter catches agent hallucinations where findings cite non-existent code or fabricated content. It does NOT catch findings whose underlying observation is real but whose line citation drifted; those are corrected per the recovery procedure above. Self-protective filtering — using citation drift as a pretext to drop substantive findings, especially against one's own earlier work — is the failure mode this rule prevents.

**4a. Proportional severity floor.** After applying the 8 false-positive filters above, apply a diff-shape filter to Low findings only. Medium, High, and Critical findings are never affected by this rule.

Compute the diff profile from the Diff Manifest (Step 1.5) and the diff line count:

- **Profile A** (strict floor): zero `CODE`/`SCRIPT`/`CONFIG-APP` files, OR diff has `CODE`/`SCRIPT` but is under ~100 changed lines AND contains no risk signals (auth, payments, secrets, CI workflow changes). **Rule:** drop all Low findings. Record each drop in Filtered Findings with reason "Proportional floor (strict)".
- **Profile B** (consensus floor): diff is 100-250 changed lines, no high-risk signals. **Rule:** keep Low findings only when 2+ agents flagged the same issue (use the `Flagged by:` consensus annotation from Step 3.1). Drop single-agent Lows. Record each drop in Filtered Findings with reason "Proportional floor (consensus)".
- **Profile C** (no floor): any high-risk signal is present (auth, payments, secrets, CI workflow changes), OR diff is over 250 changed lines. **Rule:** no filter applied. Current behavior preserved.

Risk signals are detected from the Diff Manifest: any `CONFIG-APP` file touching auth or secrets, any file under a `payments/` or `auth/` path, any CI workflow file (`.github/workflows/*.yml`, `.gitlab-ci.yml`), any file matching `secrets|credentials|keys|tokens` in its name.

The proportional floor runs AFTER subsumption (Step 3.1) and the existing 8 filters (Step 3.4) so that dropped findings have already been deduplicated. Dropped findings still appear in the Filtered Findings section with their drop reason, preserving transparency.

**No promotion to escape the floor.** Severity is assigned based on concrete consequence, not on whether a finding will survive the proportional floor. Do NOT reclassify a finding from Low to Medium solely because the current profile would drop Lows. If a finding is genuinely Low under the severity rubric, drop it (record in Filtered Findings) -- do not launder it into Medium to preserve it in the report. The floor is a synthesis-stage noise filter, not an incentive to inflate severity. Violating this rule reintroduces the exact noise pattern the floor exists to suppress. When in doubt, ask: "Would I assign this severity if no filter existed?" If the honest answer is Low, keep it Low.

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
8. **Populate findings overview.** After all filtering, deduplication, and severity assignment, count findings per severity tier. Write the totals into the `Findings overview` line in `## Review Context`. Use the format: `X Critical, Y High, Z Medium, W Low (N filtered)`. Omit tiers with zero findings (e.g., `2 High, 1 Medium (3 filtered)` instead of `0 Critical, 2 High, 1 Medium, 0 Low`).

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
- **Findings overview**: {X Critical, Y High, Z Medium, W Low} ({N filtered})

## Summary
One paragraph: what the PR does, overall risk, top-line recommendation.

## Agents Dispatched
{list each discovered agent and its verdict}

## What's Working Well
{2-5 bullet points highlighting positive aspects of the changes. Each item is one sentence, no severity ratings. Omit this section entirely if the diff has no notable strengths -- do not fabricate praise.}

## Architectural Assessment
{If architecture-strategist ran: include its Architecture Context (3-5 bullets) and Structural Summary here. If it did not run or returned empty, omit this section entirely.}

## Findings

Each finding gets a short ID: severity initial + sequence number (C1, C2... for Critical; H1, H2... for High; M1, M2... for Medium; L1, L2... for Low). These IDs are stable within a report and can be used to reference findings concisely (e.g., "except L1", "fix H2 first").

### Critical
[C1, C2, ... merged critical findings]

### High
[H1, H2, ... merged high findings]

### Medium
[M1, M2, ... merged medium findings]

### Low
[L1, L2, ... merged low findings]

{For findings flagged by 2+ agents, include the annotation: "Flagged by: agent1, agent2"}

## Recommended Fix Order
{Prioritized action plan for findings of Medium severity or above. Omit this section if 0-2 findings qualify.}

| Priority | ID | Finding | Severity | Effort |
|----------|----|---------|----------|--------|
| 1 | C1 | [Short title with file:line] | Critical | ~X min |
| 2 | H1 | [Short title with file:line] | High | ~X min |
| ... | ... | ... | ... | ... |

## Filtered Findings

**{N} findings reported, {M} filtered** ({classification breakdown, e.g., "3 out-of-scope, 2 aspirational, 1 subjective style"})

- [brief reason for each, e.g., "~~[M3] [Medium] (waste-detector) config/routes.rb:15 -- Consider extracting nested routes~~ -- Aspirational: working code, no concrete problem"]

(Omit this section entirely if no findings were filtered.)

## Verdict
[Unified verdict] -- [severity counts] -- [one-line justification]
```

<!-- SYNC: This report format is parsed by skills/work/SKILL.md:316 Phase 4c (review finding verification). If you change the report structure (section headings, finding format), update the verification parsing logic there. New sections (What's Working Well, Recommended Fix Order) are additive and do not affect Phase 4c parsing. Step 3.5 below may modify findings (remove, downgrade, rewrite) before Step 4 saves the report. -->

## Step 3.5 -- Report Quality Check

After synthesis, dispatch the `report-checker` agent for an independent quality audit. This step catches noise, false positives, and proportionality issues that survive the Step 3 filters.

1. **Dispatch.** Spawn `quiver:report-checker` with:
   - The full synthesized report (the markdown string from Step 3)
   - The original diff (same diff passed to agents in Step 2)
   - Do NOT pass individual agent outputs -- the checker evaluates the report as a reader would.

2. **Handle results:**
   - **Zero issues:** Print `Quality check passed -- report is ready.` Proceed to Step 4.
   <!-- SYNC: The apply-fixes procedure below (REMOVE/DOWNGRADE/REWRITE actions + recalculation steps) is duplicated in skills/report-check/SKILL.md Step 4 "Apply fixes" block. Keep both in sync. -->
   - **Issues found:** Apply the recommended actions:
     - REMOVE: Delete the finding from the report.
     - DOWNGRADE: Change the finding's severity and move it to the correct section.
     - REWRITE: Replace the finding's recommendation text with the corrected version.
   - After applying fixes, recalculate:
     - Findings overview counts in `## Review Context`
     - Severity section contents (move downgraded findings, remove deleted ones)
     - Recommended Fix Order table (remove entries for deleted/downgraded findings)
     - Verdict line (recompute based on remaining finding severities)
   - Print: `Quality check: {N} issues found and fixed.`

3. **Retry (max 1).** Re-dispatch `report-checker` with the corrected report.
   - **Zero issues on retry:** Proceed to Step 4.
   - **Issues remain on retry:** Proceed to Step 4 anyway. Do NOT retry again. Append a `## Quality Check Notes` section to the end of the report (before Verdict) listing the unresolved items with their QA IDs and descriptions.
   - Print: `Quality check: {N} items remain after correction. Proceeding with the report.`

4. The max iteration count (1 retry after initial check) is a hard limit. This prevents infinite correction loops. The same discipline that applies to the report-checker agent applies here: if the report is good enough after one correction pass, stop.

**Status messages (plain language, no rule codes):**
- Before dispatch: `Running quality check on the review report...`
- These messages are user-facing and are fully covered by the plain-language scan in Step 4b.

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
3. Draft a short terminal summary with these elements:
   - One-line verdict
   - Counts per severity
   - Which agents ran and their individual verdicts
   - Path to the saved report file
4. **Pre-print scan (mandatory gate).** Before printing the drafted summary, run the scan defined in the "Status Messages: Plain Language Required" section against the draft. The summary is a live chat-stream message and is fully covered by the plain-language rule -- it is not exempt because it appears at the end of the run. If the draft contains any rule code, hash prefix, bare commit SHA, or internal invariant name, rewrite it using the translation table and re-scan. Only print the summary after the scan passes.
5. Do **not** print the full review in the terminal unless `--terminal` was used.

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

## Status Messages: Plain Language Required

Every character of text the user sees in their terminal during or after a review run is read by a human who has not memorized this file's internal rule codes. This covers: mid-run status lines between tool calls, `AskUserQuestion` prompt bodies and button labels, the Step 4b terminal summary, the final verdict line, and any warning, confirmation, or error message. The review pipeline is dense with internal terms (rule codes, hash prefixes, invariant names) and it is tempting to narrate your work by referencing them directly. Resist that. A user running `/quiver:review` wants to know what is being checked and why, not which numbered rule in which internal document is being enforced.

**Rewrite rule:** before printing any chat-stream text, re-read it once. If it contains a rule code, a raw SHA or hash prefix, a commit SHA without plain-language context, or an internal invariant name, rewrite it. State what you are checking in plain English, and attach a short clause explaining why it matters -- the concrete problem the check prevents, not the rule that demands it. Being slightly more verbose is fine and preferred; two clear sentences beat one cryptic one.

**Pre-print scan (mandatory gate, not a suggestion).** Before any chat-stream output leaves you -- including the Step 4b terminal summary and the final verdict line, which are fully in scope -- scan your drafted text for the patterns below. If any match, rewrite and re-scan before printing. This is a gate. Text that has not passed the scan must not be printed.

- Rule codes: any `RA` followed by a digit, any `LA` followed by a digit, `R[0-9]` or `L[0-9]` references to hard rules, any "rule N" / "lesson N" phrasing that only makes sense if you have read the Quiver rule files.
- Hash material: any unbroken run of 8 or more hexadecimal characters (full SHAs, hash prefixes, `5fc168ad...` style truncations).
- Bare commit SHAs: any `[0-9a-f]{7,}` appearing without a short plain-language label ("the commit that added the status-message section" is fine; `337eab3` by itself is not).
- Internal invariant names: "canonical text", "byte-identical", "drift check", "drift-detection workflow", "exemption variant", "adversarial exemption", "research-shaped exemption", "subsumption rule", "proportional floor", "severity floor", "Profile A", "Profile B", "Profile C", "diff manifest", "discipline section", "stability test", "RA1-RA8", "LA1-LA4".
- Section references into the rule files that mean nothing to an outside reader: "Step 2 item 9", "sub-item 4a", "hard rule N", etc.

If you need a concept that appears on this list and you cannot find a plain-English version, omit the detail rather than leaking the jargon. A correct but shorter status line is better than a complete but cryptic one.

**Plain-language translation table.** When you would otherwise reach for one of the banned terms, use the replacement on the right. If a term is missing from this table and you cannot paraphrase it, drop the detail.

| Jargon | Plain-language replacement |
|--------|---------------------------|
| RA2 / canonical text / byte-identical | "the exact rule text that must appear in every agent word-for-word" |
| LA1 drift check / drift-detection workflow | "confirming the rule text has not silently diverged between agent files" |
| SHA256 hash, hash prefix | omit entirely -- hashes are never user-facing |
| bare commit SHA (`337eab3`) | "the commit that added X" or "the most recent commit on this branch" |
| RA3 exemption variant / adversarial exemption | "the adversarial agents use their own wording of the rule" |
| research-shaped exemption | "research agents are treated differently because they only report facts, not graded findings" |
| proportional severity floor | "a filter that drops low-severity findings on small diffs" |
| subsumption rule | "a narrower finding absorbed into a broader one it is a symptom of" |
| Profile A / Profile B / Profile C | "small / medium / large-or-risky diff" |
| diff manifest | "the classified list of changed files" |
| stability test / RA4 | "the 'would I still flag this cold tomorrow' check" |
| discipline section | "the top-of-file rules every review agent follows" |

**What stays technical:** file paths, agent names (`waste-detector`, `project-context-analyst`), line counts, file counts, finding severities (Critical/High/Medium/Low), commit counts in a delta. These are concrete and users expect them. The rule applies only to terms that only make sense if you have read the Quiver rules files.

**Example -- bad:**

> Before finalizing I'll verify the one concrete constraint worth checking: that the RA2 canonical text is byte-identical across the seven non-adversarial agents.
> All seven non-adversarial agents carry the byte-identical canonical RA2 text (SHA256 5fc168ad...), matching the baseline from commit d55d5fb. LA1 drift check passes.

**Example -- good:**

> One last check before I write the report. This PR copies the same "no speculation" rule text into seven different agent files. That kind of duplication drifts over time -- someone edits one copy, forgets the others, and the rule quietly splits into inconsistent variants. I'll hash all seven copies and confirm they are still word-for-word identical.
> All seven agent files carry the exact same rule text, matching the version the project has recorded as the baseline. No drift detected. Writing the report now.

**Scope:** this rule governs every chat-stream character printed during or after a review run, including mid-run status lines, `AskUserQuestion` prompt bodies, the Step 4b terminal summary, and the final verdict line. "Between tool calls" is not a loophole -- the Step 4b terminal summary and verdict line are fully covered even though they come after the last tool call. The only place rule codes, hashes, and internal invariant names are allowed is inside the saved report file on disk; that file is a persisted artifact that lives alongside the rules, not live conversation. If the text appears in the user's terminal, the ban applies.

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
- **Don't** narrate your work to the user using internal rule codes, SHA hashes, or invariant names -- every chat-stream status line must follow the "Status Messages: Plain Language Required" section above. The saved report body is the only place rule codes belong.

---

## Test Plan

**Trigger:** `/review` (with optional flags: PR URL, `--base <branch>`, `--output <path>`, `--set-output <path>`, `--terminal`, `--comment-pr`, `--with-codex`); `/quiver:review` should also work.

**Setup:**
- Current directory is a git repo with at least one diff source (PR URL, branch ahead of base, or uncommitted changes).
- `agents/review/*.md` and `agents/research/*.md` are present and registered in `.claude-plugin/plugin.json`.
- `gh` and/or `glab` CLI installed if testing PR Mode 1 path.

**Expected behavior:**
1. Skill picks the first matching review mode (PR/MR URL, branch diff, uncommitted) and announces it.
2. Skill builds the Diff Manifest (Step 1.5) classifying every changed file (`PROMPT`, `SCRIPT`, `CONFIG-APP`, `CONFIG-MANIFEST`, `CODE`, `DOCS`).
3. Skill runs LSP detection (Step 1.75) and dispatches all qualifying agents in a single response (parallel) with the agent context including Diff Manifest, scope reminders, and `lsp_available`.
4. Skill detects existing review reports for the same branch and switches to re-review mode with delta-only scope when a previous report is found.
5. Skill synthesizes findings (deduplicate, subsumption, severity normalization, false-positive filters, proportional floor) and writes `review-<timestamp>.md` to the configured output directory; with `--terminal`, prints inline instead.
6. Skill optionally posts the report as a PR comment when `--comment-pr` is set or the user opts in interactively.
7. All chat-stream output passes the Status-Messages plain-language gate (no rule codes, hashes, or invariant names in user-facing text).

**Verification checklist:**
- [ ] Slash menu shows `/review`.
- [ ] All qualifying agents are spawned in a single response (multiple Agent tool calls in one assistant turn).
- [ ] Re-review mode produces a `Delta` line and `Scope: Delta-only` in the saved report's `## Review Context`.
- [ ] Report path defaults to `.claude/reports/` and respects `--output`/`--set-output`/saved preference, with path validation rejecting absolute paths and `..` segments.
- [ ] `--with-codex` is silently skipped when the `codex` CLI is missing (does not error).
- [ ] No internal jargon (rule codes, hashes, invariant names) appears in the terminal summary; report file content may include them.

**Known gotchas:**
- Bitbucket/Azure DevOps PR URLs fall back to Mode 2 because there is no diff CLI; PR commenting also skips on those platforms with a manual-paste hint.
- Two-dot `git diff <base>..<head>` is wrong for branch diffs; the skill uses three-dot `git diff <base>...HEAD` instead.
- The synthesized report SYNC contract pairs with `skills/work/SKILL.md` Phase 4c parsing; changing section headings or finding-ID format requires updating the work skill verification logic.

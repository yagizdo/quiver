---
name: finish-it
description: "Scan a partial project for completion gaps, collect missing information via Q&A, and write a parseable completion manifest at docs/finish-it/<project>-manifest.md. A completed manifest can also be executed autonomously -- use /loop /finish-it --execute to implement resolved gaps one tick at a time. After execution, use /finish-it --verify to validate all gaps were addressed and produce a final report."
argument-hint: "[<project-path>] [--seed <brainstorm-spec.md>] [--resume] [--execute] [--verify]"
when-to-use: "user has a partial project and needs to find what is missing -- '/finish-it', 'scan for gaps', 'what is missing in this project', 'find incomplete parts', 'finish this project', 'what do I still need to build', 'gap analysis on my project', 'run the execution loop', 'autonomously finish the gaps', 'execute the completion manifest', 'verify my project', 'run verification', 'check if gaps are fixed', 'verify the gaps were addressed' (not: idea exploration -- use '/brainstorm' for that; not: executing a work plan -- use '/work' for that; '/finish-it --execute' executes a completion manifest, '/work' executes a work plan; '/finish-it --verify' validates completed execution, not a fresh gap scan)"
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree 2>/dev/null || echo "NO_GIT"`
```

```
!`git branch --show-current 2>/dev/null || echo "NO_GIT"`
```

```
!`git log --oneline -5 2>/dev/null || echo "NO_GIT"`
```

```
!`git status --short 2>/dev/null || echo "NO_GIT"`
```

```
!`git rev-parse --show-toplevel 2>/dev/null || echo "NO_GIT"`
```

---

# Instructions

You are a gap-analysis orchestrator. Your job is to scan a partial project, discover what is incomplete, ask targeted Q&A to collect missing information, and write a parseable completion manifest at `docs/finish-it/<project>-manifest.md`. You do NOT implement anything -- you scan, ask, and document.

## Step 0 -- Git Availability

If any gather-context block returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- using current working directory as project root.`
Proceed normally. Manifest Q&A works without git.

**Derive the project name:**
- If git available: take the last path segment from the `git rev-parse --show-toplevel` output (e.g., `/Users/alice/projects/my-app` -> `my-app`).
- If NO_GIT: use the basename of the current working directory from shell context.

Use `<project>` as the derived name throughout the skill.

## Step 0.5 -- Argument Parsing

Read `$ARGUMENTS` as plain text:

- If it contains `--execute`: set execution intent; skip interactive State Detection entirely and enter Execution Mode (see the `# Execution Mode` section after Manifest Finalization). Do not continue into Step 1.
- If it contains `--verify`: set verification intent; skip interactive State Detection entirely and enter Verification Mode (see the `# Verification Mode` section after Execution Mode). Do not continue into Step 1.
- If it contains `--resume`: jump directly to Step 1 Resume path (skip State Detection routing, act as if exactly one manifest was found and the user picked "Resume").
- **Precedence:** `--resume` > `--verify` > `--execute`. If `--resume` is present, clear all other intents and follow the Resume path. If `--verify` is present without `--resume`, clear execution intent and enter Verification Mode.
- If it contains `--seed <path>`: note the seed path. Read the spec file in Phase A (A1 fallback) and pre-populate detected categories from its "Stack", "Dependencies", or "Affected Areas" sections.
- If it contains a path that is not a flag (e.g., `/path/to/project`): treat it as the project root for all Glob and Read operations in this run. Derive `<project>` from this path's basename instead.
- If it is empty or contains only flags: proceed normally using the current directory.

## Step 1 -- State Detection

**Mode routing guard (check first, before any Glob):**
- If execution intent was set in Step 0.5 (`--execute`), do not run State Detection. Go directly to `# Execution Mode`. Never reach any `AskUserQuestion` from an autonomous tick.
- If verification intent was set in Step 0.5 (`--verify`), do not run State Detection. Go directly to `# Verification Mode`.

Truth table:
- `--execute` + manifest `status: complete` -> silent execution (Execution Mode runs the tick loop).
- `--execute` + partial or absent manifest -> clean termination with a printed message; no scheduling, no prompt.
- `--verify` + manifest with `execution:` block -> Verification Mode (guards checked inside Verification Mode Entry).
- `--verify` + no manifest or no `execution:` block -> error message + terminate (handled by Verification Mode Entry guards).
- bare `/finish-it` + existing manifest where `execution.status: verification-pending` -> print `> Execution complete. Starting verification...` and enter Verification Mode.
- bare `/finish-it` + existing manifest where `execution.status: verified` -> normal Resume / Start fresh / Inspect routing.
- bare `/finish-it` + existing manifest -> unchanged interactive routing below (Resume / Start fresh / Inspect).

Use the Glob tool to check for existing manifests: `docs/finish-it/*.md`.

**Zero manifests (first run):**
Proceed to Phase A.

**One manifest found:**
Read the manifest. Check `execution.status` in the `execution:` block (if present):

- If `execution.status: verification-pending`: print `> Execution complete. Starting verification...` and enter `# Verification Mode`. Do not show the routing dialog.
- If `execution.status: verified` or `execution.status` is any other value (or no `execution:` block exists): proceed to the routing dialog below.

Use `AskUserQuestion`:
> Found an existing completion manifest for this project. How would you like to proceed?

Buttons: `["Resume -- continue from where I left off", "Start fresh -- run a new gap scan", "Inspect -- show me the current manifest"]`

- **Resume:** Read the manifest. Set mode to `resume`. Skip Phase A and Phase B entirely. Proceed to Phase C with existing `pending` gaps only.
- **Start fresh:** Proceed to Phase A. The existing manifest will be replaced at the end of Phase B.
- **Inspect:** Print the full manifest contents. Then use `AskUserQuestion`:
  > What would you like to do next?
  Buttons: `["Resume -- continue from pending gaps", "Start fresh -- discard and rescan", "Cancel"]`
  - Cancel: stop immediately. Do nothing.
  - Resume: read the manifest and go to Phase C with pending gaps.
  - Start fresh: proceed to Phase A.

**Multiple manifests found (multi-project workspace):**
Use `AskUserQuestion`:
> Multiple completion manifests found. Which project would you like to work on?

List each manifest filename as a button label (up to 4; show the 4 most recently modified if more exist). Add a final button: `"Start a new project scan"`.

- Selecting an existing manifest: same routing as "One manifest found" above.
- Selecting "Start a new project scan": proceed to Phase A.

## Phase A: Stack Detection + Category Generation

### A1 -- Root Manifest Scan

Use the Glob tool to search for each pattern listed below. **Limit to the project root only** (no recursion into subdirectories -- a `package.json` inside `docs/examples/` is not a stack signal).

Patterns to check:
- `pubspec.yaml`
- `package.json`
- `Podfile`
- `*.xcodeproj`
- `*.xcworkspace`
- `build.gradle`
- `build.gradle.kts`
- `requirements.txt`
- `pyproject.toml`
- `Gemfile`
- `go.mod`
- `Cargo.toml`
- `composer.json`
- `*.csproj`

If `--seed <path>` was provided in `$ARGUMENTS`: read the seed spec file and extract any "Stack" or "Dependencies" sections. Use these as additional stack signals alongside the Glob results.

If no manifests found at all and no seed: print `> No stack manifests detected at project root. Running generic gap scan.` Generate a minimal set of categories based on the project's source directory structure (check for `src/`, `lib/`, `app/`, `test/` via Glob).

### A2 -- Dependency Extraction

For each manifest file found in A1, read it and extract:

1. **Runtime dependencies** -- third-party SDK or service names (e.g., `firebase_core`, `@supabase/supabase-js`, `RevenueCat`).
2. **Dev dependencies** -- testing frameworks, build tools (e.g., `jest`, `flutter_test`, `XCTest`).
3. **Platform targets** -- iOS, Android, Web, Desktop, Backend.
4. **Config files referenced** -- check which of the following exist via Glob (project root only): `.env`, `.env.example`, `google-services.json`, `GoogleService-Info.plist`, `Info.plist`, `.xcconfig`.

If multiple manifests are found (multi-platform project), combine and deduplicate all extracted values.

### A3 -- Category Generation

Generate gap categories from extracted dependencies. **Do not use a fixed list** -- categories emerge from what the project actually uses. Apply this mapping:

| Detected dependency or pattern | Categories to generate |
|-------------------------------|------------------------|
| Firebase, Supabase, Amplify, PocketBase | Config & Environment, SDK Initialization |
| Firebase Auth, Supabase Auth, Clerk, Auth0 | Auth |
| Firebase Analytics, Mixpanel, Amplitude, PostHog, Segment | Analytics |
| RevenueCat, StoreKit, BillingClient, In-App Purchases | Payments |
| React, Vue, Svelte, Angular, Flutter | UI Completeness |
| Tailwind, CSS-in-JS, styled-components, Material UI | UI Completeness |
| jest, pytest, XCTest, flutter_test, vitest, RSpec | Testing |
| GitHub Actions, Fastlane, Bitrise, GitLab CI | Deployment |
| Prisma, TypeORM, Drift, sqflite, Room, Core Data | Data Layer |
| Express, FastAPI, Django, Ktor, gin, Hono | API Layer |
| Firebase Messaging, APNS, FCM, OneSignal | Push Notifications |
| Stripe, Adyen, Braintree | Payments |
| Sentry, Crashlytics, Datadog, BugSnag | Error Monitoring |
| dotenv, missing `.env` file | Config & Environment |

Always include `Config & Environment` if any cloud SDK is detected (every project using a cloud service has config gaps).

Produce a final ordered category list. Default sort: Config & Environment, SDK Initialization, Auth, Data Layer, API Layer, Payments, Push Notifications, Analytics, UI Completeness, Testing, Error Monitoring, Deployment, then any remaining detected categories.

### A4 -- Manifest Scaffold Write

1. Derive `<project>` from Step 0.
2. Get the current timestamp using `date '+%Y-%m-%d_%H-%M-%S'` via Bash tool.
3. Write the initial manifest at `docs/finish-it/<project>-manifest.md`:

```
---
project: <project>
status: partial
created: <YYYY-MM-DD_HH-MM-SS>
updated: <YYYY-MM-DD_HH-MM-SS>
stack:
<detected stack entries as a YAML list, one per line with "  - " prefix>
gaps_total: 0
gaps_resolved: 0
gaps_skipped: 0
---

## Gaps

<category sections will be added during Phase B>

## Execution Order

<to be filled during Manifest Finalization>
```

4. Read the manifest back to verify it was written correctly.

### A5 -- Pre-fill Detection

Before dispatching scanner agents, scan the detected manifest files for values the user should not have to retype:

| Source file | Pre-fillable value | Label for Q&A |
|-------------|-------------------|---------------|
| `pubspec.yaml` | `name:` field | Flutter project name |
| `pubspec.yaml` | `environment.flutter:` | Flutter SDK version |
| `package.json` | `name:` field | Project name |
| `package.json` | `version:` field | Current version |
| `google-services.json` | `project_id` field | Firebase project ID |
| `GoogleService-Info.plist` | `BUNDLE_ID` value | iOS bundle identifier |
| `Info.plist` | `CFBundleIdentifier` value | iOS bundle identifier |
| `.xcconfig` | `PRODUCT_BUNDLE_IDENTIFIER` | iOS bundle identifier |

Store pre-filled values in memory. Use them as the default option description in the corresponding Q&A calls so the user can confirm rather than re-enter.

## Phase B: Scanner Dispatch

For each detected category, dispatch one read-only scanner Agent subagent.

**Codegraph check:** Before dispatching, use the Glob tool to check if `.codegraph/` exists at the project root. Set `codegraph_available` to `true` or `false` accordingly.

**Agent cap:** Maximum 8 parallel agents per batch. If more than 8 categories were detected, process categories in batches of 8. Dispatch the first 8, wait for results, process, then dispatch the next batch. Do not dispatch all batches simultaneously.

**Dispatch all agents in a batch in a single parallel Agent tool call block.** Each agent prompt must be fully self-contained -- agents have zero context from this conversation.

### Scanner Agent Prompt Template

For each category, construct the agent prompt by substituting the values in angle brackets:

```
You are a read-only gap scanner for the <category name> layer of a <detected stack comma-separated> project.

Context:
- Stack: <comma-separated list of detected stack items>
- Project root: <absolute path to project root>
- Category: <category name>
- Codegraph available: <true|false>
- LSP available: <true|false -- set true if LSP responded earlier this session, false otherwise>

Tool hierarchy (use in this order, stop when you have enough):
1. codegraph_search, codegraph_context (only if Codegraph available is true).
2. LSP goToDefinition, findReferences (only if LSP available is true).
3. Glob and grep (always available, use as fallback).

Your job:
Scan the project for gaps in the <category name> layer. A gap is something MISSING or INCOMPLETE in the current code. Concrete, present-tense defects only. Do not invent hypothetical future issues.

Category-specific checklist:
<inject the matching checklist from the Category Checklists section below>

Output format (strict -- nothing else):
Return ONLY lines matching this pattern, one gap per line:

GAP | <severity: blocking|important|nice-to-have> | <location: file:line or "missing"> | <one-sentence description>

If no gaps found in this category, output exactly:
NO_GAPS
```

### Category Checklists

Inject the matching checklist text into each agent's prompt under "Category-specific checklist":

**Config & Environment:**
- `.env` file absent or contains placeholder values like `your_key_here` or `REPLACE_ME`
- `google-services.json` absent from Android app folder
- `GoogleService-Info.plist` absent from iOS Runner folder
- Required environment variables not documented in README or `.env.example`
- API keys or tokens hardcoded in source files (grep for patterns like `sk_live_`, `AIza`, `AAAA`)

**SDK Initialization:**
- Firebase / Supabase / Amplify init call absent from app entry point
- Init called but not awaited when async
- Multiple init calls scattered across entry points
- SDK version in dependency manifest mismatches version expected by config file

**Auth:**
- Sign-in UI exists but no authentication method wired to it
- Sign-up flow missing email verification step
- Password reset flow missing or unreachable
- Auth state not persisted across app restarts
- Sign-out clears UI state but not local tokens or cached user data

**Analytics:**
- Analytics SDK initialized but zero events tracked anywhere in the codebase
- Key user actions (sign-up, first purchase, core feature use) have no tracking calls
- Event names are inconsistent across the codebase (mix of snake_case and camelCase)
- Analytics disabled in production builds (check build config flags)

**Payments:**
- Payment SDK initialized but products not fetched from store
- Purchase flow has no error handling for payment failures or cancellations
- Receipt validation absent after purchase
- Restore purchases flow not implemented
- Subscription status not checked at app launch

**UI Completeness:**
- Empty state screens missing for list or data views
- Loading states absent on async data-fetching operations
- Error states missing (blank screen shown on failure instead of an error message)
- Navigation dead ends: buttons or links with no associated action
- Placeholder text `TODO`, `PLACEHOLDER`, or lorem ipsum visible in UI source files

**Testing:**
- No test files exist anywhere in the project
- Test files exist but contain only placeholder tests with empty bodies
- Integration tests absent for critical paths such as auth or payments
- Test fixtures or seeds use hardcoded real credentials or production API keys

**Deployment:**
- No CI/CD workflow file found
- CI workflow file exists but build or test step is missing
- No separate production environment config (only staging or development config present)
- Release signing configuration absent for mobile targets

**Data Layer:**
- Database schema defined but migrations folder is empty or absent
- Data models defined but no CRUD operations implemented
- Offline or local caching planned (based on dependencies) but not implemented
- Input validation absent at the persistence boundary

**API Layer:**
- Routes defined but handlers return placeholder or empty responses
- Error responses are inconsistent (mix of HTTP status codes and formats)
- Authentication middleware not applied to routes marked as protected
- Input validation absent on data-mutating endpoints

**Push Notifications:**
- Permission request never called in app lifecycle
- Device token not registered with backend after permissions granted
- Foreground notification display handling absent
- Deep link routing for notification tap actions not implemented

**Error Monitoring:**
- Error monitoring SDK initialized but crash reporting disabled in config
- No breadcrumb calls around key operations
- User context (user ID, email) not attached to error reports

### Post-Dispatch Processing

After all agents in a batch return results:

1. **Parse output.** For each line starting with `GAP |`, extract: severity, location, description. Skip malformed lines silently.
2. **Deduplicate.** If two agents reported the same gap (same location and similar description), keep the more specific description.
3. **Assign IDs.** Assign sequential `gap-NNN` IDs across all categories (gap-001, gap-002, ...). Continue numbering from where the last batch left off.
4. **Append category sections to manifest** under `## Gaps`. For each category, write:

```
### <Category Name>

| ID | Severity | Gap | Location | Status | Notes |
|----|----------|-----|----------|--------|-------|
| gap-001 | blocking | <description> | <location> | pending | |
```

5. **Update frontmatter counters.** Increment `gaps_total` by the count of new rows. Leave `gaps_resolved` and `gaps_skipped` at 0.
6. **Read the manifest back to verify.**

Dispatch the next batch (if any) after processing the current batch.

## Phase C: Q&A Collection

For each category (in the sorted order from Phase A):

**Print a status line before the first question in each category:**
`> <Category Name>: <N> gaps found (<B> blocking, <I> important, <N2> nice-to-have)`

If N is 0: skip this category entirely. Move to the next.

### Question Generation

For each `pending` gap in the category, generate one question. Match the gap type to a question style:

| Gap type | Question style |
|----------|---------------|
| Missing value (API key, project ID, URL, bundle ID) | AskUserQuestion with the pre-filled value as the first option (if detected in A5), "Other -- I will enter this manually" as the second, "Skip -- I will handle this myself" as the last |
| Missing feature (events, screens, routes) | AskUserQuestion with multi-select: list detected partial implementations as options, plus "None of these apply", "Skip -- I will handle this myself" |
| Design decision (2-4 concrete alternatives exist) | AskUserQuestion with each alternative as a button, plus "Other -- I will describe", "Skip -- I will handle this myself" |
| Binary decision (yes/no toggle) | AskUserQuestion: "Yes -- add this now" and "No -- skip it" |

**Batch independent questions.** If multiple gaps in a category do not depend on each other, ask up to 4 in a single multi-question `AskUserQuestion` call. Only separate into sequential calls when the answer to one gap determines the options for the next.

**Every AskUserQuestion call must include "Skip -- I will handle this myself" as a selectable option.**

### After Each Category

After the user answers all questions for a category (or skips them):

1. Update each answered gap's row: set `Status` to `resolved`, write the answer into the `Notes` column.
2. Update each skipped gap's row: set `Status` to `skipped`.
3. Recalculate `gaps_resolved` and `gaps_skipped` from the manifest rows and update frontmatter.
4. Write the updated manifest.
5. Read the manifest back to verify.

## Manifest Finalization

After all categories are processed:

**Zero-gap shortcut:** If `gaps_total` is 0 (no gaps found in any category):
1. Set `status: complete` and update `updated:` timestamp in frontmatter.
2. Write `## Execution Order` as: `_No gaps detected -- nothing to execute._`
3. Write the manifest.
4. Print: `> Manifest complete: no gaps found. Nothing to execute.`
5. Stop here.

**Standard path (gaps exist):**

1. Set `status: complete` in frontmatter.
2. Update `updated:` timestamp using `date '+%Y-%m-%d_%H-%M-%S'` via Bash tool.
3. Recount by reading all rows in `## Gaps`: set `gaps_total`, `gaps_resolved`, `gaps_skipped` to actual counts.
4. Write `## Execution Order` -- an ordered list of categories. Sort rule:
   - **Tier 1 (first):** categories with at least one `blocking` gap.
   - **Tier 2 (second):** categories with at least one `important` gap and no `blocking` gaps.
   - **Tier 3 (last):** categories with only `nice-to-have` gaps.
   - **Within each tier, use dependency order:** Config & Environment -> SDK Initialization -> Auth -> Data Layer -> API Layer -> Payments -> Push Notifications -> Analytics -> UI Completeness -> Testing -> Error Monitoring -> Deployment -> any remaining categories.

   Example:
   ```
   1. Config & Environment
   2. SDK Initialization
   3. Auth
   4. Analytics
   5. UI Completeness
   6. Testing
   7. Deployment
   ```

5. Write the final manifest. Read it back to verify.
6. Print completion summary:
   `> Manifest complete: <gaps_total> gaps identified, <gaps_resolved> resolved, <gaps_skipped> skipped. Saved to docs/finish-it/<project>-manifest.md. Ready for execution loop.`

---

# Execution Mode

This mode consumes a completed manifest and implements its resolved gaps autonomously -- one gap per tick. It makes no user decisions. Consent for the entire run was given when the user invoked `/loop /finish-it --execute` (R6 single consent point). No `AskUserQuestion` is ever called from any tick path.

## Entry

1. Use the Glob tool to locate the manifest: `docs/finish-it/*.md`. If no file is found, print `> No manifest found. Run /finish-it first to generate a completion manifest.` and terminate (do not schedule a wakeup).
2. Read the manifest. Check the top-level `status` field in frontmatter.
   - If `status != complete`: print `> Manifest status is '<status>' -- Q&A is not complete. Finish the Q&A pass first, then run /loop /finish-it --execute.` Terminate without scheduling.
   - If `status == complete`: continue to State Initialization.

## State Initialization

**First-tick predicate:** a tick is the first tick when the manifest frontmatter contains no `execution:` block.

**On the first tick:** read-modify-write the manifest frontmatter to append a nested `execution:` block. Count the number of gap rows with `Status == resolved` for `tasks_pending`. Get the current timestamp via the Bash tool (`date '+%Y-%m-%d_%H-%M-%S'`). Record the current git HEAD commit SHA via the Bash tool (`git rev-parse HEAD`).

```
execution:
  status: running
  current_tick: 1
  tasks_completed: 0
  tasks_blocked: 0
  tasks_pending: <count of resolved gaps>
  last_tick_at: <timestamp>
  baseline_commit: <git rev-parse HEAD output>
  mcps_available: []
```

After writing, read the manifest back to verify (L3). Then run MCP Discovery (see MCP Discovery subsection).

**On every subsequent tick:** read the existing `execution:` block from frontmatter and load its values. Skip MCP Discovery (already done on tick 1).

**Read-only contract:** Execution mode never writes `gaps_total`, `gaps_resolved`, or `gaps_skipped`. Those counters are owned by Q&A (Phase C and Manifest Finalization) and are used as read-only inputs. Execution mode also never overwrites top-level `status` -- it stays `complete` as the permanent mode discriminator. All execution state goes in the `execution:` block exclusively. The `execution:` block contains no `tasks_skipped` field; read `gaps_skipped` from the flat frontmatter instead.

**Scaffolding-on-demand:** the `execution:` block is created lazily at the first tick, not in Phase A's A4 scaffold. Do not pre-create it.

## Tick Lifecycle

See the seven steps in the next subsection.

## MCP Discovery

Invoked once, at the first tick only (when the first-tick predicate is true).

Detect available platform MCPs by capability/marker check, mirroring the `.codegraph/` boolean pattern used in Phase B:

- Check for `.codegraph/` via Glob -> `codegraph_available: true/false`.
- Check for Flutter/Xcode MCP availability: if the xclaude-plugin MCPs are listed as available tools in the session, set `xcode_mcp: true`. Otherwise `false`.
- Check for browser MCP availability: if a Playwright/Puppeteer MCP is available, set `browser_mcp: true`. Otherwise `false`.

Record the discovered capabilities in `execution.mcps_available` as a list (e.g., `["codegraph", "xcode"]`). Write and read back the manifest.

If any discovered MCP's tools are deferred, load their schemas before use via `ToolSearch` ("select:<ToolName>[,<ToolName>]") -- mirroring the codegraph load pattern in `skills/plan/SKILL.md`. Load only before first use; do not reload each tick.

This is discovery, not installation. No MCP is required. When none are present, `execution.mcps_available` stays `[]` and Step 4 (Test) falls back to the test suite.

## Per-Tick Steps

Execute these steps in order for each tick. Each tick processes exactly one `resolved` gap.

### Step 1 -- Read Manifest and Select Gap

Re-read the manifest fresh at the start of every tick (each tick begins with clean context). Select the next gap by allowlist: the first row in `## Gaps` (following the `## Execution Order` sort) where `Status == resolved`.

- If no `resolved` gaps remain: set `execution.status: verification-pending`, write the manifest, read it back (L3), print `> Execution complete: <tasks_completed> gaps completed, <tasks_blocked> gaps blocked. Verification pending -- run /finish-it to verify.` and terminate without calling `ScheduleWakeup`. The loop ends here.
- If `pending` gaps exist: these signal incomplete Q&A. Leave them as `pending`. Do not select them for implementation. Do not set their Status to `skipped`. They are not eligible for this mode.

### Step 2 -- Plan Task

Resolve the gap's required change using the tool hierarchy:
1. `codegraph_context` / `codegraph_search` (only if `codegraph_available` is in `execution.mcps_available`).
2. LSP (`goToDefinition`, `findReferences`).
3. Glob and grep (always available).

Identify the exact files to create or modify. Apply the user answer stored in the gap's Notes column as the authoritative implementation directive.

### Step 3 -- Implement

Make the change with Edit/Write. Follow neighboring code patterns; apply manifest-provided values (keys, IDs, names) from the Notes column. Prefer targeted reads (specific line ranges) over whole-file reads for token efficiency.

### Step 4 -- Test

Detect the test command from the stack:
- Flutter: `flutter test`
- Node/npm: `npm test`
- Python: `pytest`
- Go: `go test ./...`
- Rust: `cargo test`
- Ruby: `bundle exec rspec`

Run the detected command via the Bash tool.

If a platform MCP is available (recorded in `execution.mcps_available`), also run a platform-level check: build verification or UI screenshot. Use the MCP tool for this. Otherwise, the test suite result is sufficient.

### Step 5 -- Commit

On test pass: stage the specific files modified in Step 3 only. Never stage the manifest. Never use `git add .`.

Commit with a Conventional Commits message scoped to the gap (e.g., `feat(auth): add email verification step`). No push. No AI attribution (R9).

### Step 6 -- Fix (Within-Tick Retry)

On test failure: read the error output, apply a targeted fix to the affected files, re-run tests. This counts as attempt 2.

If still failing: apply another fix and re-run. This counts as attempt 3.

If still failing after 3 attempts total: set the gap's `Status` to `blocked` and write `blocked after 3 attempts: <one-line error summary>` into its Notes column. Commit is skipped for this gap. Continue to Step 7.

### Step 7 -- Update State

Write the gap's final outcome:
- On success: update the gap row's `Status` to `completed`.
- On block: update the gap row's `Status` to `blocked` (already done in Step 6).

Recompute `execution` counters by scanning all gap rows:
- `tasks_completed`: count of rows where `Status == completed`.
- `tasks_blocked`: count of rows where `Status == blocked`.
- `tasks_pending`: count of rows where `Status == resolved` (remaining work).

Increment `execution.current_tick` by 1. Update `execution.last_tick_at` to the current timestamp.

Write the manifest. Read it back to verify (L3).

Then proceed to the Anti-Loop and Scheduling logic below.

**Gap state machine (ASCII):**

```
resolved --> completed  (Step 5: test passed, committed)
         \-> blocked    (Step 6: 3 failed attempts)

skipped  --> (never touched by Execution mode)
pending  --> (never touched by Execution mode -- signals incomplete Q&A)
```

**Execution status machine (ASCII):**

```
running --> verification-pending  (Step 1: no resolved gaps remain)
        \-> paused               (tick cap or no-progress cap)

verification-pending --> verified  (Verification Mode completes)
```

A tick is atomic: a gap moves from `resolved` to `completed` or `blocked` within one tick. There is no persisted `in_progress` state. If a tick is interrupted mid-execution (e.g., token budget), the gap stays at `resolved` and the next tick retries it cleanly.

## Strategic Parallelism

Before processing a category's gaps sequentially, scan the category's `resolved` gaps for independence using all three criteria:
- Different target files (no file overlap between the gaps).
- No data dependency (gap B's implementation does not depend on gap A's output).
- No ordering constraint (implementing A first is not required for B to be correct).

**If 3 or more gaps in the category are provably independent:** dispatch at most 3 agents in one parallel Agent tool call block. Each agent must have `isolation="worktree"` and a fully self-contained prompt carrying: the gap ID, severity, description, Notes answer, project root, stack, and `codegraph_available`. Each agent returns its modified files, test result, and a commit-ready diff.

Merge worktrees sequentially with `git merge --no-edit`. On any conflict: stop the batch immediately, mark all conflicting gaps' Status as `blocked` with `blocked: merge conflict in parallel batch` in Notes, report the conflict to the terminal, and do not auto-resolve. Produce one commit per successfully merged agent.

**Otherwise (fewer than 3 independent gaps, or any dependency exists):** fall back to the sequential tick lifecycle above.

## Anti-Loop, Scheduling, and Termination

### Anti-Loop Table

| Limit | Trigger | Action |
|-------|---------|--------|
| Per-gap retry | 3 failed test attempts in one tick | Mark gap `blocked`, move on to next gap |
| Total tick cap | 50 ticks total | Pause: set `execution.status: paused`, write manifest, print summary, terminate without `ScheduleWakeup` |
| No-progress cap | 3 consecutive ticks with no completion (all gaps either blocked or skipped) | Pause: same as tick cap |
| Token budget | Context approaching limit | Save state by writing manifest, terminate cleanly. User resumes with `/loop /finish-it --execute`; the next tick re-reads the manifest and continues |

**Circular dependency omission:** the locked 6-column schema (D4) carries no gap-to-gap dependency data, so cycle detection is impossible. The no-progress cap subsumes any mutual-block stall. This omission is deliberate, not a coverage gap.

### ScheduleWakeup Cadence

After Step 7, call `ScheduleWakeup` if and only if the loop is still running:

- **More `resolved` gaps remain and last tick completed successfully:** `ScheduleWakeup` with `delaySeconds: 60`. Cache stays warm; momentum continues.
- **Last gap was `blocked` or `tasks_pending` is low:** `ScheduleWakeup` with `delaySeconds: 270`. Stays within the 5-minute cache window; gives time for any blocked gap to be manually unblocked.
- **Pause or completion:** do NOT call `ScheduleWakeup`. The loop ends.

Pass the same `/loop /finish-it --execute` invocation back as the wakeup `prompt` parameter, so the next tick re-enters this mode. Cache-window rationale: 60s keeps the context cache warm; ~270s stays within the 5-minute TTL; avoid 300s (worst-of-both: pays the cache miss without amortizing it).

### Pause Behavior

On pause (tick cap, no-progress, or token budget):
1. Set `execution.status: paused`.
2. Write the manifest. Read it back (L3).
3. Print a progress summary: total ticks used, gaps completed, gaps blocked, gaps remaining.
4. Terminate. Do NOT call `AskUserQuestion`.

A user can edit the manifest manually: flip a `blocked` gap back to `resolved` (or set it to `skipped`) and resume with `/loop /finish-it --execute`. The next tick re-reads the manifest, so edits are picked up automatically.

### Completion Behavior

On completion (no `resolved` gaps remain):
1. Set `execution.status: verification-pending`.
2. Write the manifest. Read it back (L3).
3. Print: `> Execution complete: <tasks_completed> gaps completed, <tasks_blocked> gaps blocked. Verification pending -- run /finish-it to verify.`
4. Terminate. Do NOT call `ScheduleWakeup`.

---

# Verification Mode

This mode validates that the execution loop's work was effective. It walks every completed gap, runs build and test checks, dispatches agents for critical categories, and produces a timestamped final report. It never modifies gap status rows or Q&A counters.

## Entry

**Triggers:** `--verify` flag (set in Step 0.5) OR `execution.status: verification-pending` detected automatically in State Detection (Step 1).

**Guards (check in order -- fail any one and terminate):**
1. Use Glob to locate manifest at `docs/finish-it/*.md`. If not found: print `> No manifest found. Run /finish-it first to generate a completion manifest.` Terminate.
2. Read manifest. Check that an `execution:` block exists in frontmatter. If absent: print `> No execution record found. Run /loop /finish-it --execute first, then run /finish-it --verify.` Terminate.
3. Check that `execution.baseline_commit` is present. If absent: print `> No baseline commit recorded. This manifest was created before baseline tracking was added. Re-run the execution loop to record a baseline.` Terminate.

**State initialization (scaffolding-on-demand):** Create `execution.verification:` block nested inside `execution:`. Get timestamp via `date '+%Y-%m-%d_%H-%M-%S'` via Bash tool. Write manifest, read back (L3).

```
execution:
  ...
  verification:
    status: running
    started_at: <timestamp>
```

**Read-only contract:** Verification mode never modifies gap `Status` columns, `gaps_total`, `gaps_resolved`, `gaps_skipped`, or top-level `status`. All verification state lives in `execution.verification:` exclusively.

**Re-read MCP availability:** Load `execution.mcps_available` from manifest. Use this list for Steps 4-5.

## Step 1 -- Manifest Check

Walk each row in `## Gaps` where `Status == completed`.

For each completed gap:
1. Extract the file path from the `Location` column. If `Location` is "missing", classify as `unverified` and continue.
2. Run `git diff <execution.baseline_commit>..HEAD -- <location-file>` via Bash tool.
3. Check if the diff is non-empty (file was changed since baseline).
4. Grep the diff output for a key action term from the gap's `Gap` description column (e.g., if gap says "Firebase.initializeApp() call absent", grep for "initializeApp"). A rough match suffices -- this is a quick check.

**Classify each gap:**
- `verified`: diff non-empty AND grep match found.
- `unverified`: diff non-empty but grep match not found (file changed, action unclear).
- `missing`: diff empty (no change to this file since baseline).

Accumulate classifications in memory (`{gap_id, classification, file}`). Do NOT modify the manifest gap table.

## Step 2 -- Build Check

Detect build command from stack:

| Stack | Build command |
|-------|---------------|
| Flutter | `flutter build apk` |
| Node/npm | `npm run build` |
| Python | `python -m build` |
| Go | `go build ./...` |
| Rust | `cargo build` |
| Ruby | `bundle exec rake build` |

If no build command detectable: skip, record `build_result: skipped`.

Run command via Bash tool. Capture output.

- **Pass:** exit code 0 -> `build_result: pass`.
- **Fail:** non-zero exit or error lines -> `build_result: fail`. Store first 3 error lines as `build_error_summary`.

## Step 3 -- Test Suite

Detect test command from stack (same table as Execution Step 4):

| Stack | Test command |
|-------|-------------|
| Flutter | `flutter test` |
| Node/npm | `npm test` |
| Python | `pytest` |
| Go | `go test ./...` |
| Rust | `cargo test` |
| Ruby | `bundle exec rspec` |

If no test command detectable: skip, record `test_result: skipped`.

Run command via Bash tool. Parse output for pass/fail/skip counts. Record:
- `test_result: pass | fail | skipped`
- `test_pass_count: <N>`
- `test_fail_count: <N>`
- `test_skip_count: <N>`

## Step 4 -- Critical Category Agents

Check completed gaps from Step 1 against these triggers:

| Trigger | Agent role | Dispatch when |
|---------|-----------|--------------|
| Any `completed` gap with `Severity == blocking` | Config Validator | At least one blocking gap completed |
| Any `completed` gap in a category matching `UI*` | UI Coherence Checker | Completed gaps include UI Completeness category |
| Any `completed` gap in a category matching `Auth*` or `Security*` | Security Spot Check | Completed gaps include Auth or Security category |

If no triggers match: print `> No critical categories require agent verification.` Skip to Step 5.

**Dispatch all triggered agents in a single parallel Agent tool call block.** Each agent prompt must be fully self-contained.

Config Validator prompt template:
```
You are a Config Validator. Read-only scan -- do not modify any files.

Context:
- Project root: <absolute path>
- Stack: <comma-separated stack>
- Blocking gaps that were completed: <list of gap IDs, descriptions, and Notes answers>
- Baseline commit: <execution.baseline_commit>

Your job:
1. Read the files referenced in gap Notes columns.
2. Run git diff <baseline>..HEAD for each referenced file via Bash tool.
3. Verify: config values are set (no placeholder text like REPLACE_ME or your_key_here remaining), no obviously missing required values.

Output format: one line per issue: "ISSUE | <severity: high|medium|low> | <file:line> | <description>". If no issues: output exactly "NO_ISSUES".
```

UI Coherence Checker prompt template:
```
You are a UI Coherence Checker. Read-only scan -- do not modify any files.

Context:
- Project root: <absolute path>
- Stack: <comma-separated stack>
- UI gaps that were completed: <list of gap IDs, descriptions, and Notes answers>
- Baseline commit: <execution.baseline_commit>
- MCPs available: <execution.mcps_available>

Your job:
1. Read the UI files referenced in gap Notes columns.
2. Run git diff <baseline>..HEAD for each referenced file via Bash tool.
3. Check: navigation links wired to real destinations, no broken imports, no placeholder TODO or lorem ipsum text remaining.

Output format: "ISSUE | <severity> | <file:line> | <description>". If no issues: "NO_ISSUES".
```

Security Spot Check prompt template:
```
You are a Security Spot Check agent. Read-only scan -- do not modify any files.

Context:
- Project root: <absolute path>
- Stack: <comma-separated stack>
- Auth/security gaps that were completed: <list of gap IDs, descriptions, and Notes answers>
- Baseline commit: <execution.baseline_commit>

Your job:
1. Read the auth/security files referenced in gap Notes columns.
2. Run git diff <baseline>..HEAD for each referenced file via Bash tool.
3. Check: auth flow complete (no missing wiring), no credentials hardcoded in diffs, input validation present at auth endpoints.

Output format: "ISSUE | <severity> | <file:line> | <description>". If no issues: "NO_ISSUES".
```

After agents return: parse all `ISSUE |` lines. Collect findings for the Step 6 report.

## Step 5 -- UI Smoke Test

Check `execution.mcps_available`:
- Contains `xcode`: use xclaude-plugin MCPs.
- Contains `browser`: use browser MCP.
- Empty or neither present: print `> UI smoke test skipped: no UI MCP available.` Record `ui_smoke_result: skipped`. Skip to Step 6.

**If MCP available:**
1. Build and launch the app using the appropriate MCP tool.
2. Navigate main flows: launch screen, home/main screen, key feature screens identified from manifest categories.
3. Take a screenshot at each step using the MCP screenshot tool.
4. Flag screens showing: placeholder text (TODO, Coming Soon, lorem ipsum), blank screens, visible error messages, or crash dialogs.

Record `ui_smoke_result: pass | issues-found`. Store any flagged issues for the report.

## Step 6 -- Final Report + Termination

**Generate report:**

1. Get timestamp via `date '+%Y-%m-%d_%H-%M-%S'` via Bash tool.
2. Derive `<project>` from Step 0 (same as manifest filename stem without `-manifest`).
3. Write to `docs/finish-it/<project>-report-<timestamp>.md`:

```
---
name: <project>-finish-report
created: <timestamp>
manifest: docs/finish-it/<project>-manifest.md
---

# Finish-It Report: <project>

## Summary

- **Total gaps:** <gaps_total>
- **Completed:** <count completed> (verified: <N>, unverified: <N>, missing: <N>)
- **Blocked:** <count blocked>
- **Skipped:** <count skipped>
- **Build:** <pass | fail | skipped>
- **Tests:** <pass_count>/<pass_count+fail_count> passing (<fail_count> failures, <skip_count> skipped)

## Verification Results

### Passing

| # | Gap | Category | Verification |
|---|-----|----------|-------------|
<rows for verified gaps>

### Issues Found

| # | Gap | Category | Issue | Severity |
|---|-----|----------|-------|----------|
<rows from agent ISSUE lines + missing/unverified gaps>

## Blocked

| # | Gap | Reason |
|---|-----|--------|
<rows for blocked gaps with their Notes content>

## Skipped

| # | Gap | Reason |
|---|-----|--------|
<rows for skipped gaps with their Notes content>

## Action Items

<numbered list ordered by severity: high first. Format: [Severity] Description (gap #ID)>

## What's Next

<1-3 sentences: summary of remaining work. If all verified and build/tests pass, note the project appears complete.>
```

4. Read the report back to verify it was written (L3).

**Termination:**

1. Determine overall status: no agent issues, no missing gaps, build pass or skipped, tests pass or skipped -> `passed`. Otherwise -> `issues-found`.
2. Count `issues_total`: number of `ISSUE |` lines from agents + count of `missing` and `unverified` gaps.
3. Update `execution.verification:` block:
   - `status: passed | issues-found`
   - `completed_at: <timestamp>`
   - `build_result: <value>`
   - `test_result: <value>`
   - `issues_total: <count>`
4. Set `execution.status: verified`.
5. Write manifest, read back (L3).
6. Print: `> Verification complete. Report: docs/finish-it/<project>-report-<timestamp>.md. <issues_total> issues found.`

---

## Test Plan

**Trigger:** `/finish-it` and `/quiver:finish-it` (Q&A mode); `/loop /finish-it --execute` and `/loop /quiver:finish-it --execute` (Execution mode)

**Setup (Q&A mode):** A Flutter+Firebase project with known gaps: missing `.env` file, `Firebase.initializeApp()` absent from `main.dart`, zero analytics tracking calls, no empty-state screens. Run from the project root.

**Setup (Execution mode):** A project whose manifest is `status: complete` and contains at least two `resolved` gaps and one `skipped` gap.

**Expected behavior:**
1. Shell blocks all exit 0 in both git and non-git directories.
2. Stack detection finds `pubspec.yaml` and `google-services.json` at root; generates categories including Config & Environment, SDK Initialization, Analytics, UI Completeness.
3. Scanner agents dispatch in a single parallel Agent tool call block (one batch of 4 agents for this scenario); each returns `GAP | ...` lines.
4. Q&A groups gaps by category, prints a summary line per category, uses AskUserQuestion for all user prompts -- no plain-text questions.
5. Manifest saves after each category. Inspecting `docs/finish-it/<project>-manifest.md` mid-run shows partial progress.
6. A second run on the same project finds the existing manifest and offers Resume / Start fresh / Inspect.
7. Resume mode reads pending gaps and skips Phase A and Phase B.
8. A project with no third-party SDKs and no missing files produces `status: complete`, `gaps_total: 0`, and `## Execution Order: _No gaps detected_`.
9. `/finish-it --execute` on a `status: complete` manifest enters Execution Mode silently; no AskUserQuestion is called.
10. Bare `/finish-it` on a `status: complete` manifest **where `execution.status` is not `verification-pending`** still shows the interactive Resume / Start fresh / Inspect routing unchanged.
11. Each completed gap produces exactly one atomic commit with a Conventional Commits message; the manifest is never staged.
12. A gap whose fix fails all 3 within-tick attempts is set to `blocked` with a reason in its Notes column; the loop continues to the next gap.
13. The loop pauses (sets `execution.status: paused`, no ScheduleWakeup) after 3 consecutive no-progress ticks or 50 total ticks.
14. The manifest accurately reflects the `execution:` block state after each tick.

**Setup (Verification mode):** A project whose manifest is `status: complete` and whose `execution:` block contains `status: verification-pending`, `baseline_commit: <SHA>`, at least two `completed` gaps (one blocking, one UI), and one `blocked` gap. Run `/finish-it --verify` from the project root.

**Expected behavior (Verification mode):**
15. `/finish-it --verify` with no manifest terminates with `> No manifest found.` No ScheduleWakeup, no AskUserQuestion.
16. `/finish-it --verify` with a manifest but no `execution:` block terminates with `> No execution record found.`
17. `/finish-it --verify` with a manifest whose `execution:` block lacks `baseline_commit` terminates with `> No baseline commit recorded.`
18. Bare `/finish-it` on a manifest with `execution.status: verification-pending` auto-enters Verification Mode, printing `> Execution complete. Starting verification...` without showing the routing dialog.
19. Verification Step 1 classifies completed gaps as verified/unverified/missing. The manifest gap table is never modified during verification.
20. Verification Step 4 dispatches agents only when triggers match. A manifest with no blocking/UI/auth-security completed gaps prints `> No critical categories require agent verification.` and skips agents.
21. Report generated at `docs/finish-it/<project>-report-<timestamp>.md`. A second `/finish-it --verify` run creates a new timestamped report without overwriting the first.
22. After verification completes, `execution.status: verified` is set. Subsequent bare `/finish-it` shows the normal Resume / Start fresh / Inspect routing dialog.

**Verification checklist:**
- [ ] `/finish-it` and `/quiver:finish-it` both appear in the slash command menu after plugin reload.
- [ ] All five shell blocks exit 0 in a git repo; all five exit 0 (with NO_GIT output) in a non-git directory.
- [ ] No plain-text questions to the user -- every user prompt uses AskUserQuestion (R5).
- [ ] No AskUserQuestion reachable from any Execution-mode tick path (R5 / D6).
- [ ] Manifest scaffold at `docs/finish-it/<project>-manifest.md` exists before Phase C begins.
- [ ] Scanner agents dispatched in one parallel Agent tool call block per batch, not one at a time.
- [ ] Manifest read back after every write (L3 verification) -- including after each tick's Step 7 state update.
- [ ] Second run on a project with a `partial` manifest routes through State Detection and offers Resume / Start fresh / Inspect.
- [ ] Skipped gaps appear in manifest with `Status: skipped` and no Notes entry.
- [ ] Execution Order section present in final manifest with categories sorted: blocking tier first, dependency order within tiers.
- [ ] Zero-gap manifest: `status: complete`, `gaps_total: 0`, no numbered Execution Order items.
- [ ] Execution-mode commit stages specific files only; manifest never staged; no `git add .` (D7).
- [ ] No push and no AI attribution in Execution-mode commits (R9).
- [ ] Flat Q&A counters (`gaps_total`, `gaps_resolved`, `gaps_skipped`) never mutated by Execution mode (D5).
- [ ] `execution:` block in frontmatter contains no `tasks_skipped` field (D5).
- [ ] `--execute` on a partial or absent manifest terminates with a message; no ScheduleWakeup, no prompt.
- [ ] `--execute` + `--resume` together: `--resume` wins; Q&A resume path runs.
- [ ] No `CLAUDE_PLUGIN_ROOT` references in this file (R4).
- [ ] No Unicode characters or emoji in this file (R8).
- [ ] No new inline `!` shell blocks added to Execution Mode (R3).
- [ ] `when-to-use:` field is a single-line double-quoted string (R10).
- [ ] All `!` shell blocks use git commands only; no `||` with non-git commands (L1).
- [ ] `--verify` flag routes to Verification Mode; State Detection skipped.
- [ ] `--verify` + `--resume` together: `--resume` wins, Q&A resume path runs.
- [ ] Bare `/finish-it` on `execution.status: verification-pending` manifest auto-enters Verification Mode without routing dialog.
- [ ] Verification Mode never writes to gap `Status` columns (read-only contract enforced).
- [ ] `execution.verification:` block created lazily at Entry, not in A4 scaffold.
- [ ] Report saved at `docs/finish-it/<project>-report-<timestamp>.md` with timestamp in filename.
- [ ] Re-running verification creates a new timestamped report, not overwriting previous one.
- [ ] `execution.status: verified` set after Verification Mode Step 6 completes.
- [ ] `execution.baseline_commit` present in `execution:` block after first execution tick.

**Known gotchas:**
- Plugin auto-discovery requires a plugin reload after the skill is first installed. `/finish-it` will not appear in the slash menu until the plugin reloads.
- The Glob check for `docs/finish-it/*.md` returns empty on the first run -- the skill must not abort on this empty result.
- Scanner agent prompts must be fully self-contained: they carry zero context from the parent conversation. Stack, project root, and tool-availability flags must all be embedded in each agent's prompt string.
- `docs/finish-it/<project>-manifest.md` lives inside `docs/`, which is gitignored. The manifest is intentionally not committed to version control.
- When categories exceed 8, the second dispatch batch begins only after the first batch results are merged and written to the manifest. Both batches must not be dispatched simultaneously.
- The `--resume` flag bypasses State Detection routing entirely -- use it when you know a manifest exists and want to skip the routing dialog.
- `--execute` on a partial manifest must terminate, not hang. The termination path must NOT call ScheduleWakeup; omitting the call ends the loop.
- Parallel batches in Execution mode cap at 3 agents and merge sequentially; a conflict marks affected gaps `blocked` and stops the batch without auto-resolution.
- ScheduleWakeup at exactly 300s is wrong: it pays the cache miss without amortizing it. Use 60s (momentum) or 270s (blocked/low-progress) only.
- `execution.baseline_commit` is only recorded by the updated /finish-it version. Manifests created before this field was added will trigger the "No baseline commit recorded" guard in Verification Mode -- re-run the execution loop to generate a new manifest.
- Verification report files live in `docs/finish-it/`, which is gitignored (same as manifest files). Reports are intentionally local only.
- Timestamped report filenames (`<project>-report-<YYYY-MM-DD_HH-MM-SS>.md`) are intentional -- each verification run produces a new file. Do not change to a fixed filename; history would be lost.
- The `execution.verification:` block is nested inside `execution:` in YAML frontmatter. Read and write it as a nested block. Flattening it to top-level keys would break the read-only contract separation.
- Verification dispatches agents for blocking/UI/auth-security categories only. Running agents for all categories would be wasteful and is not part of this mode.

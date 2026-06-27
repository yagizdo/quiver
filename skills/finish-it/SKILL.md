---
name: finish-it
description: "Scan a partial project for completion gaps, collect missing information via Q&A, and write a parseable completion manifest at docs/finish-it/<project>-manifest.md. Use when you have a partial implementation and need to find what is missing before executing."
argument-hint: "[<project-path>] [--seed <brainstorm-spec.md>] [--resume]"
when-to-use: "user has a partial project and needs to find what is missing -- '/finish-it', 'scan for gaps', 'what is missing in this project', 'find incomplete parts', 'finish this project', 'what do I still need to build', 'gap analysis on my project' (not: idea exploration -- use '/brainstorm' for that; not: executing a plan -- use '/work' for that)"
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

- If it contains `--resume`: jump directly to Step 1 Resume path (skip State Detection routing, act as if exactly one manifest was found and the user picked "Resume").
- If it contains `--seed <path>`: note the seed path. Read the spec file in Phase A (A1 fallback) and pre-populate detected categories from its "Stack", "Dependencies", or "Affected Areas" sections.
- If it contains a path that is not a flag (e.g., `/path/to/project`): treat it as the project root for all Glob and Read operations in this run. Derive `<project>` from this path's basename instead.
- If it is empty or contains only flags: proceed normally using the current directory.

## Step 1 -- State Detection

Use the Glob tool to check for existing manifests: `docs/finish-it/*.md`.

**Zero manifests (first run):**
Proceed to Phase A.

**One manifest found:**
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

## Test Plan

**Trigger:** `/finish-it` and `/quiver:finish-it`

**Setup:** A Flutter+Firebase project with known gaps: missing `.env` file, `Firebase.initializeApp()` absent from `main.dart`, zero analytics tracking calls, no empty-state screens. Run from the project root.

**Expected behavior:**
1. Shell blocks all exit 0 in both git and non-git directories.
2. Stack detection finds `pubspec.yaml` and `google-services.json` at root; generates categories including Config & Environment, SDK Initialization, Analytics, UI Completeness.
3. Scanner agents dispatch in a single parallel Agent tool call block (one batch of 4 agents for this scenario); each returns `GAP | ...` lines.
4. Q&A groups gaps by category, prints a summary line per category, uses AskUserQuestion for all user prompts -- no plain-text questions.
5. Manifest saves after each category. Inspecting `docs/finish-it/<project>-manifest.md` mid-run shows partial progress.
6. A second run on the same project finds the existing manifest and offers Resume / Start fresh / Inspect.
7. Resume mode reads pending gaps and skips Phase A and Phase B.
8. A project with no third-party SDKs and no missing files produces `status: complete`, `gaps_total: 0`, and `## Execution Order: _No gaps detected_`.

**Verification checklist:**
- [ ] `/finish-it` and `/quiver:finish-it` both appear in the slash command menu after plugin reload.
- [ ] All five shell blocks exit 0 in a git repo; all five exit 0 (with NO_GIT output) in a non-git directory.
- [ ] No plain-text questions to the user -- every user prompt uses AskUserQuestion (R5).
- [ ] Manifest scaffold at `docs/finish-it/<project>-manifest.md` exists before Phase C begins.
- [ ] Scanner agents dispatched in one parallel Agent tool call block per batch, not one at a time.
- [ ] Manifest read back after every write (L3 verification).
- [ ] Second run on a project with a `partial` manifest routes through State Detection and offers Resume / Start fresh / Inspect.
- [ ] Skipped gaps appear in manifest with `Status: skipped` and no Notes entry.
- [ ] Execution Order section present in final manifest with categories sorted: blocking tier first, dependency order within tiers.
- [ ] Zero-gap manifest: `status: complete`, `gaps_total: 0`, no numbered Execution Order items.
- [ ] No `CLAUDE_PLUGIN_ROOT` references in this file (R4).
- [ ] No Unicode characters or emoji in this file (R8).
- [ ] `when-to-use:` field is a single-line double-quoted string (R10).
- [ ] All `!` shell blocks use git commands only; no `||` with non-git commands (L1).

**Known gotchas:**
- Plugin auto-discovery requires a plugin reload after the skill is first installed. `/finish-it` will not appear in the slash menu until the plugin reloads.
- The Glob check for `docs/finish-it/*.md` returns empty on the first run -- the skill must not abort on this empty result.
- Scanner agent prompts must be fully self-contained: they carry zero context from the parent conversation. Stack, project root, and tool-availability flags must all be embedded in each agent's prompt string.
- `docs/finish-it/<project>-manifest.md` lives inside `docs/`, which is gitignored. The manifest is intentionally not committed to version control.
- When categories exceed 8, the second dispatch batch begins only after the first batch results are merged and written to the manifest. Both batches must not be dispatched simultaneously.
- The `--resume` flag bypasses State Detection routing entirely -- use it when you know a manifest exists and want to skip the routing dialog.

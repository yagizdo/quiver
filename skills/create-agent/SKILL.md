---
name: create-agent
description: Scaffold a new Claude Code agent with smart defaults from a natural language description or interactive Q&A.
argument-hint: "[description] e.g. \"a security reviewer that checks OWASP top 10\" or run without arguments for guided setup"
disable-model-invocation: true
---

# Create Agent

Scaffold a focused, high-quality Claude Code agent file ready to use immediately -- no placeholders, no filler, no generic advice. This skill bundles the workflow (Parse / Resolve / Generate / Save) at the top and the agent-authoring reference (frontmatter, body structure, quality gates) at the bottom; cross-references are in-document section links, not external file loads.

**Before starting**, gather project context silently (do not show results to the user):
1. Glob `agents/**/*.md` -- existing agent files
2. Read `.claude-plugin/plugin.json` -- plugin manifest
3. Read `CLAUDE.md` (first 30 lines) -- project conventions

Treat missing files as empty. Proceed regardless.

You are an agent architect. Use the [Agent Authoring Reference](#agent-authoring-reference) below as the structural and stylistic source of truth -- it owns the field specs, model guide, body structure, quality gates, and anti-patterns.

```
+-------------------------------+     +-------------------------------+     +-------------------------------+     +-------------------------------+
| 1. PARSE                      | --> | 2. RESOLVE                    | --> | 3. GENERATE                   | --> | 4. SAVE & REPORT              |
| Check $ARGUMENTS              |     | Fill in missing fields        |     | Write agent body using         |     | Create directory & file        |
| Detect project context        |     | Ask user if ambiguous         |     | reference below                |     | Verify & output summary        |
+-------------------------------+     +-------------------------------+     +-------------------------------+     +-------------------------------+
```

---

## Phase 1: Parse

Silently determine which case applies:

### Branch A -- Argument Provided

If `$ARGUMENTS` is not empty, extract as much as possible from the natural language description:
- **Name**: Derive a kebab-case name from the description.
- **Category**: Infer from the agent's purpose (review, research, workflow, design, docs, or custom). See [Category Definitions](#category-definitions).
- **Model**: Default to `inherit` unless the description implies lightweight work (-> `haiku`) or deep analysis (-> `opus`). See [Model Selection Guide](#model-selection-guide).
- **Persona**: Infer the domain expertise and role from the description.
- **Methodology**: Infer the key checks/steps the agent should perform.

Proceed to Phase 2 with inferred values.

### Branch B -- No Arguments

If `$ARGUMENTS` is empty, proceed to Phase 2 with no inferred values. All fields will be gathered interactively.

---

## Phase 2: Resolve

For each required field, check whether it was inferred (Branch A) or needs to be asked (Branch B). Ask the user only for fields that are missing or genuinely ambiguous.

**Required fields to resolve (in this order):**

1. **Purpose** -- What does this agent do? (Skip if clear from argument.)
2. **Name** -- Kebab-case identifier. Suggest one derived from purpose; let user override.
3. **Category** -- One of: `review`, `research`, `workflow`, `design`, `docs`, or a custom name. See [Category Definitions](#category-definitions).
4. **Model** -- `inherit` (default), `haiku`, `sonnet`, or `opus`. See [Model Selection Guide](#model-selection-guide). Only ask if the user's description suggests a non-default choice.
5. **Persona style** -- What expertise or perspective should the agent embody? Only ask if not obvious from purpose.

**Asking rules:**
- Ask one question at a time using `AskUserQuestion` with multiple-choice options when applicable.
- If a field has an obvious answer from context, state your inference and move on -- don't ask.
- If the argument provided enough detail for all fields, present a summary for confirmation instead of asking field-by-field.

**Summary confirmation (when most fields are inferred):**

Present all resolved fields and ask the user to confirm or adjust:

> **Agent Summary:**
> **Name:** `{name}`
> **Category:** `{category}`
> **Model:** `{model}`
> **Persona:** {one-line persona description}
> **Key responsibilities:** {bulleted list of 3-5 things the agent will check/do}
>
> Proceed with this configuration?

Use `AskUserQuestion` with options: Proceed / Adjust / Cancel.

---

## Phase 3: Generate

Using the resolved fields and the [Agent Authoring Reference](#agent-authoring-reference) below, generate the full agent file content.

**Generation rules:**
- Follow the agent body structure: examples block, role statement, methodology, output format. See [Agent Body Structure](#agent-body-structure).
- Every section must be specific to THIS agent's domain -- no generic content.
- The examples block should have 2-3 realistic trigger scenarios.
- The role statement should establish domain expertise in the first sentence.
- Methodology sections should contain actionable, domain-specific checks ordered by impact.
- Output format should match the agent's purpose (e.g., severity-based for reviewers, structured findings for auditors).
- Run [Quality Gates](#quality-gates) before proceeding to save.
- **Code navigation hint:** If the agent's purpose involves searching or exploring the broader codebase (not just reading files it already knows about), copy the Code Navigation Strategy block verbatim from `skills/code-navigation/SKILL.md` (the section starting with `## Code Navigation Strategy`) into the generated agent file. Add a comment above it:
  ```
  <!-- This agent searches the codebase. The Code Navigation Strategy block
       (from skills/code-navigation/SKILL.md) is included below. The dispatching
       skill must pass codegraph_available and lsp_available context. -->
  ```

---

## Phase 4: Save & Report

### 1. Create directory and write file

```bash
mkdir -p agents/{category}
```

Write the generated agent to: `agents/{category}/{name}.md`

**Verify:** Read back the file and confirm it matches the generated content.

### 2. Context-aware next-steps guidance

Silently detect the project context from Phase 1 data:

- **Plugin project** (plugin.json exists): Check if `"./agents/"` is already in the `skills` array. If not, note that the user should add it. Then, auto-register the new agent path in plugin.json's `agents` array using `./agents/{category}/{name}.md` format. If the `agents` field doesn't exist yet, create it. Skip if the exact path is already present.
- **General project** (no plugin.json): Note that the user can reference the agent from their CLAUDE.md or project configuration.

### 3. Update README.md

After the agent file is saved and plugin.json is updated, automatically add the new agent to the project's README.md.

**Procedure:**

1. Read `README.md` from the project root. If it does not exist, log a warning and skip this step entirely.
2. Look for HTML comment markers in the agents section:
   - `<!-- agents:{category}-start -->` / `<!-- agents:{category}-end -->` for existing category sections
   - `<!-- agents-start -->` / `<!-- agents-end -->` for the overall agents block
3. **If category markers exist** (e.g., `<!-- agents:review-start -->`):
   - Find the `<!-- agents:{category}-end -->` marker
   - Insert a new table row immediately before that marker: `| \`{name}\` (\`quiver:{name}\`) | {description (without the "Use when" prefix -- use the user-facing summary)} |`
4. **If category markers do NOT exist** but `<!-- agents-end -->` exists:
   - Insert a new category subsection immediately before `<!-- agents-end -->`:
     ```
     ### {Category (title case)}
     <!-- agents:{category}-start -->

     | Agent | Description |
     |-------|-------------|
     | `{name}` (`quiver:{name}`) | {description} |

     <!-- agents:{category}-end -->

     ```
5. **If no markers are found at all**: Log a warning ("README.md does not have agent injection markers -- skipping auto-update. Add `<!-- agents-start -->` / `<!-- agents-end -->` markers to enable this.") and skip.
6. Update the Components table: find the `| Agents | {N} |` row and increment the count by 1.

**Rules:**
- Never delete or rewrite existing table rows -- only append.
- Preserve exact spacing and formatting of surrounding content.
- If any step fails (missing markers, malformed table), warn and skip rather than corrupting the file.

### 4. Output

> **Agent created:** `agents/{category}/{name}.md`
>
> | Field | Value |
> |-------|-------|
> | **Name** | `{name}` |
> | **Category** | `{category}` |
> | **Model** | `{model}` |
> | **Sections** | {count of body sections generated} |
> | **Lines** | {line count} |
>
> {context-aware next steps -- only show the relevant one:}
>
> **Next steps (plugin project):**
> Agent registered in `plugin.json` `agents` array automatically.
> Test by spawning the agent with the Agent tool.
>
> **Next steps (general project):**
> Reference the agent in your project's CLAUDE.md or load it via your plugin/skill configuration.
> Then test by spawning the agent with the Agent tool.

---

## Workflow Anti-Patterns

- **Don't** generate placeholder sections like "TODO: add methodology" -- ask the user or infer from the description.
- **Don't** create agents with generic personas like "You are a helpful assistant" -- every agent needs domain-specific expertise.
- **Don't** skip the summary confirmation when fields were inferred -- the user should validate before file creation.
- **Don't** modify plugin.json beyond adding the new agent path to the `agents` array -- no other fields or files should be touched.
- **Don't** generate agents longer than 200 lines -- focus on the highest-impact methodology steps.

---

# Agent Authoring Reference

This section contains the specification and best practices for authoring Claude Code agent files. The Phase 3 generation step uses these subsections directly.

## Agent File Specification

Every agent is a single Markdown file with YAML frontmatter followed by prompt content.

### Frontmatter Specification

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `name` | Yes | string | Kebab-case identifier. Must match filename without `.md`. |
| `description` | Yes | string | Quoted string. Must include "Use when [trigger condition]." clause. |
| `model` | Yes | string | `inherit` (default -- uses parent model), `haiku` (lightweight/cost-sensitive tasks), `sonnet` (balanced), `opus` (complex reasoning). |
| `color` | No | string | UI accent color. Options: `yellow`, `violet`, `purple`, `cyan`, `blue`, `green`, `red`. |

### Model Selection Guide

| Model | Use When |
|-------|----------|
| `inherit` | Default choice. Agent needs same capability as the invoking context. Most agents use this. |
| `haiku` | Fast, cheap tasks: linting, simple lookups, file listing, lightweight validation. |
| `sonnet` | Balanced tasks: code review, documentation generation, moderate analysis. |
| `opus` | Complex reasoning: architecture analysis, security audits, multi-file refactoring. |

**Rule:** When in doubt, use `inherit`. Only override when there is a clear cost/performance reason.

## Category Definitions

Agents are organized into category directories. Use the most specific match.

| Category | Purpose | Examples |
|----------|---------|----------|
| `review` | Code review, pattern checking, quality enforcement | Security auditor, style checker, architecture reviewer |
| `research` | Information gathering, documentation lookup, codebase exploration | Docs researcher, git history analyzer, dependency auditor |
| `workflow` | Process automation, CI/CD, repetitive tasks | PR comment resolver, linter, test runner |
| `design` | UI/UX, visual review, design system enforcement | Design reviewer, accessibility checker |
| `docs` | Documentation generation and maintenance | README writer, API doc generator, changelog builder |
| Custom | Any domain not covered above | Use a descriptive kebab-case directory name |

**Rule:** If none of the predefined categories fit, create a custom category directory with a descriptive name.

## Agent Body Structure

After frontmatter, the agent body follows this section order. All sections are optional -- include only those that add value for the specific agent.

### 1. Examples Block (Recommended)

XML-formatted trigger examples that help the orchestrating system know when to spawn this agent.

```xml
<examples>
<example>
Context: [scenario where this agent is useful]
user: "[what the user said]"
assistant: "[how the agent would be invoked]"
<commentary>[why this agent is the right choice]</commentary>
</example>
</examples>
```

**Rules:**
- Include 2-3 examples covering different trigger scenarios.
- Examples should be realistic and specific, not generic.
- The `<commentary>` explains the reasoning for choosing this agent.

### 2. Role/Persona Statement (Recommended)

A strong opening paragraph that establishes the agent's identity and expertise.

**Effective patterns:**
- Domain expert: "You are a senior security engineer specializing in web application vulnerabilities..."
- Named persona: "You are a meticulous code reviewer who prioritizes readability over cleverness..."
- Mission-driven: "Your mission is to catch data integrity issues before they reach production..."

**Rules:**
- Be specific about the domain and expertise level.
- State the primary goal or mission in the first sentence.
- Avoid generic roles like "You are a helpful assistant."

### 3. Methodology/Process Sections

The core instructions organized into logical phases or checklists.

**Effective patterns:**
- Numbered phases for sequential workflows: "## Phase 1: Scan", "## Phase 2: Analyze", "## Phase 3: Report"
- Checklists for parallel checks: `- [ ] Check for SQL injection`, `- [ ] Verify input sanitization`
- Decision trees for conditional logic: "If X, do Y. If Z, do W."

**Rules:**
- Be specific and actionable -- "Check for hardcoded credentials in config files" not "Review security."
- Include the reasoning behind each check when it is non-obvious.
- Order steps from highest-impact to lowest-impact.

### 4. Output Format (Recommended)

Explicit specification of how the agent should structure its response.

**Effective patterns:**
- Severity-based reporting: Critical / Warning / Info sections
- Structured findings: File path, line number, issue, suggestion
- Summary + details: Executive summary followed by detailed findings

**Rules:**
- Define the exact headings and structure the agent should use.
- Specify what constitutes each severity level if using severity-based reporting.
- Include an example of a well-formatted finding.

## Quality Gates

Before finalizing any generated agent, verify:

**BLOCKING:**
- `name` field matches the filename (without `.md`)
- `description` includes a "Use when..." trigger clause
- `model` field is present and valid
- Role statement is specific to the agent's domain (not generic)
- At least one methodology section with actionable instructions

**WARNING:**
- No examples block -- most agents benefit from 2-3 trigger examples
- Agent file exceeds 200 lines -- consider trimming methodology to essentials
- Methodology steps are generic enough to apply to any agent -- make them domain-specific

## Authoring Anti-Patterns

- **Don't** write vague personas like "You are a helpful code reviewer" -- specify the domain, the standards, and the philosophy.
- **Don't** create agents that duplicate existing tool functionality -- an agent should provide judgment, not just run a command.
- **Don't** include methodology steps that any developer would already know -- focus on non-obvious checks and domain expertise.
- **Don't** mix multiple responsibilities in one agent -- keep each agent focused on a single domain. Create separate agents instead.
- **Don't** use `haiku` model for agents that need deep reasoning or multi-file analysis -- they will produce shallow results.

---

## Test Plan

**Trigger:** `/create-agent <description>` or `/create-agent` for guided setup; `/quiver:create-agent` should also work.

**Setup:**
- Working directory is a project root with optional `agents/` directory and `.claude-plugin/plugin.json` (Quiver plugin) or any project layout (general project).

**Expected behavior:**
1. Skill silently globs existing agents, reads `plugin.json`, and reads the first 30 lines of `CLAUDE.md`.
2. Phase 1 parses `$ARGUMENTS` (Branch A) or proceeds with no inference (Branch B), inferring `name`, `category`, `model`, persona, and methodology when possible.
3. Phase 2 asks only for genuinely missing or ambiguous fields via `AskUserQuestion` and presents a summary before generation when most fields were inferred.
4. Phase 3 generates the agent body using the in-doc Authoring Reference (Examples Block, Role/Persona, Methodology, Output Format) and runs the Quality Gates before saving.
5. Phase 4 writes `agents/<category>/<name>.md`, registers the path in `.claude-plugin/plugin.json` (plugin project only), and updates `README.md` between the documented HTML comment markers when present.
6. Final output prints the field summary table and category-specific next-steps block.

**Verification checklist:**
- [ ] Slash menu shows `/create-agent`.
- [ ] Generated frontmatter has `name`, `description` (with `Use when…` clause), and `model`; `name` matches the filename stem.
- [ ] Plugin project: new agent path appears in `plugin.json` `agents` array; existing entries are untouched.
- [ ] General project: no `plugin.json` mutations; user gets the "general project" next-steps block.
- [ ] README is updated only when the documented markers exist; missing-marker case warns and skips without corruption.
- [ ] Agent file is read back after writing to verify contents.

**Known gotchas:**
- The Authoring Reference (frontmatter, model guide, body structure, quality gates) is the single source of truth -- the workflow phases reference it via in-doc anchors instead of loading a separate file.
- README auto-update relies on `<!-- agents-start -->` / `<!-- agents-end -->` (and optional per-category) markers; without them the skill does NOT silently invent a section.
- Agent body length over 200 lines triggers a WARNING quality gate; do not silently bypass it -- trim or surface the warning.

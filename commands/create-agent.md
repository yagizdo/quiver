---
description: Scaffold a new Claude Code agent with smart defaults from a natural language description or interactive Q&A.
argument-hint: [description] e.g. "a security reviewer that checks OWASP top 10" or run without arguments for guided setup
---

# Gather Project Context

```
!`ls -1 agents/ 2>/dev/null; true`
```

```
!`find agents -mindepth 1 -maxdepth 1 -type d 2>/dev/null; true`
```

```
!`cat .claude-plugin/plugin.json 2>/dev/null; true`
```

```
!`head -30 CLAUDE.md 2>/dev/null; true`
```

---

# Instructions

You are an agent architect. Your goal is to produce a focused, high-quality Claude Code agent file that is ready to use immediately -- no placeholders, no filler, no generic advice.

Before generating anything, load the `create-agent` skill for agent authoring reference (template structure, field specs, model guide, anti-patterns).

```
+-------------------------------+     +-------------------------------+     +-------------------------------+     +-------------------------------+
| 1. PARSE                      | --> | 2. RESOLVE                    | --> | 3. GENERATE                   | --> | 4. SAVE & REPORT              |
| Check $ARGUMENTS              |     | Fill in missing fields         |     | Write agent body using         |     | Create directory & file        |
| Detect project context        |     | Ask user if ambiguous          |     | skill reference                |     | Verify & output summary        |
+-------------------------------+     +-------------------------------+     +-------------------------------+     +-------------------------------+
```

---

# Phase 1: Parse

Silently determine which case applies:

### Branch A -- Argument Provided

If `$ARGUMENTS` is not empty, extract as much as possible from the natural language description:
- **Name**: Derive a kebab-case name from the description.
- **Category**: Infer from the agent's purpose (review, research, workflow, design, docs, or custom).
- **Model**: Default to `inherit` unless the description implies lightweight work (-> `haiku`) or deep analysis (-> `opus`).
- **Persona**: Infer the domain expertise and role from the description.
- **Methodology**: Infer the key checks/steps the agent should perform.

Proceed to Phase 2 with inferred values.

### Branch B -- No Arguments

If `$ARGUMENTS` is empty, proceed to Phase 2 with no inferred values. All fields will be gathered interactively.

---

# Phase 2: Resolve

For each required field, check whether it was inferred (Branch A) or needs to be asked (Branch B). Ask the user only for fields that are missing or genuinely ambiguous.

**Required fields to resolve (in this order):**

1. **Purpose** -- What does this agent do? (Skip if clear from argument.)
2. **Name** -- Kebab-case identifier. Suggest one derived from purpose; let user override.
3. **Category** -- One of: `review`, `research`, `workflow`, `design`, `docs`, or a custom name. Suggest based on purpose.
4. **Model** -- `inherit` (default), `haiku`, `sonnet`, or `opus`. Only ask if the user's description suggests a non-default choice.
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

# Phase 3: Generate

Using the resolved fields and the `create-agent` skill reference, generate the full agent file content.

**Generation rules:**
- Follow the agent body structure from the skill: examples block, role statement, methodology, output format.
- Every section must be specific to THIS agent's domain -- no generic content.
- The examples block should have 2-3 realistic trigger scenarios.
- The role statement should establish domain expertise in the first sentence.
- Methodology sections should contain actionable, domain-specific checks ordered by impact.
- Output format should match the agent's purpose (e.g., severity-based for reviewers, structured findings for auditors).
- Run quality gates from the skill before proceeding to save.

---

# Phase 4: Save & Report

### 1. Create directory and write file

```bash
mkdir -p agents/{category}
```

Write the generated agent to: `agents/{category}/{name}.md`

**Verify:** Read back the file and confirm it matches the generated content.

### 2. Context-aware next-steps guidance

Silently detect the project context from Phase 1 data:

- **Plugin project** (plugin.json exists): Check if `"./agents/"` is already in the `skills` array. If not, note that the user should add it.
- **General project** (no plugin.json): Note that the user can reference the agent from their CLAUDE.md or project configuration.

### 3. Output

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
> Add `"./agents/"` to the `skills` array in `plugin.json` if not already present.
> Then test by spawning the agent with the Agent tool.
>
> **Next steps (general project):**
> Reference the agent in your project's CLAUDE.md or load it via your plugin/skill configuration.
> Then test by spawning the agent with the Agent tool.
>
> **Tip:** Review the generated persona and methodology before first use. `/quiver:agents-md` to generate an AGENTS.md for this project.

---

# Anti-Patterns

- **Don't** generate placeholder sections like "TODO: add methodology" -- ask the user or infer from the description.
- **Don't** create agents with generic personas like "You are a helpful assistant" -- every agent needs domain-specific expertise.
- **Don't** skip the summary confirmation when fields were inferred -- the user should validate before file creation.
- **Don't** modify plugin.json or any registry file -- only create the agent file and provide guidance.
- **Don't** generate agents longer than 200 lines -- focus on the highest-impact methodology steps.

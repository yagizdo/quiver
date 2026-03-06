---
name: create-agent
description: Agent authoring knowledge base -- template structure, field specifications, and best practices for creating Claude Code agents.
disable-model-invocation: true
---

# Agent Authoring Reference

This skill contains the specification and best practices for authoring Claude Code agent files. It is used by the `/create-agent` command.

## Agent File Specification

Every agent is a single Markdown file with YAML frontmatter followed by prompt content.

### Frontmatter Fields

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

## Anti-Patterns

- **Don't** write vague personas like "You are a helpful code reviewer" -- specify the domain, the standards, and the philosophy.
- **Don't** create agents that duplicate existing tool functionality -- an agent should provide judgment, not just run a command.
- **Don't** include methodology steps that any developer would already know -- focus on non-obvious checks and domain expertise.
- **Don't** mix multiple responsibilities in one agent -- keep each agent focused on a single domain. Create separate agents instead.
- **Don't** use `haiku` model for agents that need deep reasoning or multi-file analysis -- they will produce shallow results.

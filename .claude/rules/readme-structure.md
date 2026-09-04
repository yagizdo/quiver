# README Structure Template

Reference: https://github.com/EveryInc/compound-engineering-plugin/tree/main/plugins/compound-engineering

## Structure Order

1. **Title + one-liner** — what the plugin does in one sentence
2. **Status note** (optional) — development status callout via blockquote
3. **Quick Start** — marketplace add + plugin install + first slash example
4. **Installation** — Plugin Install (recommended) as standalone section
5. **Components table** — inventory of all component types with counts
6. **What Do I Use?** — scenario-based grouped tables; internal reference skills (code-navigation, orchestrate-agents, using-quiver, visual-companion) are excluded from user-facing docs
7. **Hooks** — table with hook name, event, and description
8. **Agents** (when added) — grouped by category (e.g. Review, Research, Workflow)
9. **MCP Servers** (when added) — table with server name and description, plus tool details
10. **How It Works** — bullet list of key features/mechanics
11. **Setup** (optional) — any required config like .gitignore entries
12. **Known Issues** (optional)
13. **Uninstall**
14. **Contributing** -- one paragraph, links to `CONTRIBUTING.md`
15. **License**

## Formatting Rules

### Component Inventory Table

Always at the top, shows what the plugin contains at a glance:

```markdown
## Components

| Component | Count |
|-----------|-------|
| Skills | 16 |
| Hooks | 1 |
| Agents | 10 |
```

- Only list component types that exist
- Update counts when adding new components

### Grouping Skills/Agents

Never use a single flat table for all items. Group by scenario with H3 headings. Use the `Situation | Command | What happens` column format for the skills section:

```markdown
## What Do I Use?

### Building Something

| Situation | Command | What happens |
|-----------|---------|--------------|
| I have a vague idea | `/brainstorm` | ... |

### Git & Shipping

| Situation | Command | What happens |
|-----------|---------|--------------|
| Changes ready to commit | `/commit` | ... |
```

Slash-invocable skills are listed by their `/<name>` invocation. Internal reference skills (code-navigation, orchestrate-agents, using-quiver, visual-companion) are excluded from user-facing docs entirely -- they are never listed in the README.

This exclusion list is documentation-scoped and deliberately wider than the runtime `user-invocable: false` field, which is set only on `code-navigation`.

### Hooks Table

Include three columns — name, event trigger, and description:

```markdown
## Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `pre-compact-handover` | PreCompact | ... |
```

### Agent Categories

Group agents by role. Current categories:
- **Review** — code review, security, performance
- **Research** — docs, git history, best practices
- **Workflow** — automation, linting, bug reproduction

```markdown
## Agents

### Review

| Agent | Description |
|-------|-------------|
| `agent-name` | ... |
```

## Checklist — When Updating README

- [ ] Component inventory counts match actual files (`ls -d skills/*/ | wc -l`, agent count from `agents/**/*.md`)
- [ ] All slash-invocable skills (skills with frontmatter that are not reference-only) are listed under `## What Do I Use?`
- [ ] Internal reference skills (code-navigation, orchestrate-agents, using-quiver, visual-companion) are excluded from user-facing docs
- [ ] All hooks in `hooks/hooks.json` are listed
- [ ] Skills/agents are grouped by category, not flat
- [ ] Descriptions are concise (one line)
- [ ] No placeholder entries for components that have shipped

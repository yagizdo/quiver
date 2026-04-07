# README Structure Template

Reference: https://github.com/EveryInc/compound-engineering-plugin/tree/main/plugins/compound-engineering

## Structure Order

1. **Title + one-liner** — what the plugin does in one sentence
2. **Status note** (optional) — development status callout via blockquote
3. **Quick Start** — marketplace add + plugin install + first command example
4. **Installation** — Plugin Install (recommended) as standalone section
5. **Components table** — inventory of all component types with counts
6. **Commands** — grouped by category (not one flat list)
7. **Hooks** — table with hook name, event, and description
8. **Skills** (when added) — grouped by category
9. **Agents** (when added) — grouped by category (e.g. Review, Research, Workflow)
10. **MCP Servers** (when added) — table with server name and description, plus tool details
11. **How It Works** — bullet list of key features/mechanics
12. **Setup** (optional) — any required config like .gitignore entries
13. **Known Issues** (optional)
14. **Uninstall**
15. **License**

## Formatting Rules

### Component Inventory Table

Always at the top, shows what the plugin contains at a glance:

```markdown
## Components

| Component | Count |
|-----------|-------|
| Commands | 11 |
| Hooks | 1 |
| Skills | 6 |
| Agents | 6 |
```

- Only list component types that exist
- Update counts when adding new components

### Grouping Commands/Skills/Agents

Never use a single flat table for all items. Group by category with H3 headings:

```markdown
## Commands

### Session Handover

| Command | Description |
|---------|-------------|
| `/quiver:handover` | ... |
| `/quiver:load-handover` | ... |

### Git

| Command | Description |
|---------|-------------|
| `/quiver:commit` | ... |
```

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

### Skills Categories

Group by domain:

```markdown
## Skills

### Category Name

| Skill | Description |
|-------|-------------|
| `skill-name` | ... |
```

## Checklist — When Updating README

- [ ] Component inventory counts match actual files
- [ ] All commands in `commands/` are listed
- [ ] All hooks in `hooks/hooks.json` are listed
- [ ] Commands/skills/agents are grouped by category, not flat
- [ ] Descriptions are concise (one line)
- [ ] No placeholder entries for components that have shipped

# Agent Capability Rules

Hard rules and learned lessons for the capability contract carried by every file under `agents/`: which tools an agent is denied, how much reasoning budget it gets, and how the two stay in sync with `tests/agents/test-capability-profile-contract.sh`.

For skill authoring rules, see `skill-rules.md`. For review-agent discipline, see `review-agent-rules.md`. For CLI overlay rules, see `cli-overlay-rules.md`.

**Scope:** The contract is enforced at runtime on Claude Code only. `.cursor-plugin/plugin.json` registers 10 of the 20 agents and `.codex-plugin/plugin.json` and `gemini-extension.json` register none, so on those CLIs the `disallowedTools` and `effort` fields are documentation rather than enforcement. This is a coverage limitation of the overlays, not a violation of the contract -- the same values ship to every CLI, and no overlay forks them. The verifier checks text, not behavior: it proves the frontmatter matches the assignment, not that the runtime honored it. Behavioral confirmation is a manual `/review --deep` transcript read.

Nothing runs the verifier automatically. There is no CI in this repo and every test under `tests/` is a documented manual run. Automatic enforcement is deferred to the hook layer of sub-project B; until that ships, the verifier is a manual gate and drift between runs is possible.

---

## Hard Rules

Non-negotiable. Every agent file must satisfy all of these, and the verifier fails the tree when one is broken.

**CP1. Every agent declares a profile.** Every file under `agents/` appears in the `## Assignments` table below with a profile and an effort tier. An agent absent from the table fails the verifier, and a table row with no matching agent file fails it too.

**CP2. The canonical string is copied verbatim.** The `disallowedTools` value in an agent's frontmatter is byte-identical to its profile's canonical string in the `## Profiles` table, after quote-stripping and comma-whitespace normalization. The string lives in two places by construction; the verifier is what keeps the copies honest.

**CP3. Denylist only, never an allowlist.** Agents set `disallowedTools`, never `tools`. An allowlist that names an unavailable tool is a launch failure, and `disallowedTools` emptying a `tools` list launches a subagent with zero tools and no refusal from Claude Code.

**CP4. No `mcp__` pattern in any profile.** context7 and codegraph are load-bearing for 10 agents, and an `mcp__*` entry in `disallowedTools` removes every MCP tool from every server, not just the one named.

**CP5. Field spelling is per artifact type.** Agents use camelCase `disallowedTools`. Skills use kebab-case `disallowed-tools`. A wrong-case key produces no warning, no error, and applies no restriction. Never document the two as one string.

Measured on Claude Code 2.1.233: `claude plugin validate ./ --strict` does not inspect agent markdown frontmatter. With `disallowedTools` deliberately misspelled as kebab-case `disallowed-tools` in `agents/workflow/plan-reviewer.md`, validate passed in both modes -- marketplace-manifest mode (chosen when `.claude-plugin/marketplace.json` is present) and plugin-manifest mode. It reports on the JSON manifest only. `tests/agents/test-capability-profile-contract.sh` is therefore the sole gate against this trap, and it catches the kebab-case spelling by reporting the camelCase field as absent.

**CP6. Value format is a comma-separated string.** YAML list form is documented for the `--agents` JSON flag and the SDK, not for agent markdown frontmatter. Use `Edit, Write, NotebookEdit` -- unquoted, one space after each comma.

**CP7. `effort` is per agent, never per profile.** Profiles carry the tool contract only. Folding budget into the profile forces profile proliferation (`read-only-cheap`, `read-only-expensive`) the moment one agent needs different tuning. `disallowedTools` has a right answer per profile; `effort` is per-agent tuning with no right answer.

**CP8. `maxTurns` is banned on any agent whose output feeds a synthesis step.** An agent that hits the cap terminates with result subtype `error_max_turns` and returns no text at all, not a partial report. A synthesizer cannot distinguish that from a legitimate zero-findings result. This covers every current Quiver agent.

**CP9. `disallowedTools` resolves before `tools`.** If a future agent sets both, the deny list is applied first and the allow list resolves against what remains. A tool named in both is removed.

---

## Profiles

| Profile | Canonical `disallowedTools` |
|---------|------------------------------|
| `read-only` | `Edit, Write, NotebookEdit, AskUserQuestion, WebSearch, WebFetch` |
| `read-only-web` | `Edit, Write, NotebookEdit, AskUserQuestion` |
| `adapter` | `AskUserQuestion, WebSearch, WebFetch` |

`read-only` reads code and git history and emits findings. It has no reason to modify files, prompt the user from a subagent, or reach the network. context7 and codegraph stay available because they are MCP tools, not web tools, and CP4 keeps them out of every denylist.

`read-only-web` is `read-only` with `WebSearch` and `WebFetch` restored. It exists for `best-practices-researcher`, whose stated job is validating library versions against upstream release notes that context7 does not always carry. It has one member; denying web access to that specific agent is the risky direction of an unverified change, so the profile is kept. Revisit it if a second member never appears.

`adapter` belongs to `codex-code-reviewer`, which shells out to the Codex CLI and persists the wrapped reviewer's raw output. It is the only agent that writes, and it writes a transcript, not source.

`Bash` stays in all three profiles. Frontmatter denies tools by name and cannot scope a command pattern, and read-only agents need `git diff`, `git log`, and `git blame`. `AskUserQuestion` is denied everywhere because a subagent that tries to prompt the user stalls instead of returning a result.

---

## Assignments

Effort tiers: `low` = mechanical lookup or single-pass parsing with no hypothesis and no branching. `medium` = one analysis pass over a bounded input where conclusions follow from what was read. `high` = multiple competing hypotheses, adversarial construction, or cross-file reasoning that must hold together.

| Agent | Profile | Effort |
|-------|---------|--------|
| `waste-detector` | `read-only` | `medium` |
| `security-audit` | `read-only` | `high` |
| `architecture-strategist` | `read-only` | `high` |
| `developer-experience-auditor` | `read-only` | `medium` |
| `logic-reviewer` | `read-only` | `high` |
| `test-reviewer` | `read-only` | `medium` |
| `stress-tester` | `read-only` | `high` |
| `codex-code-reviewer` | `adapter` | `medium` |
| `report-checker` | `read-only` | `medium` |
| `senior-reviewer` | `read-only` | `high` |
| `best-practices-researcher` | `read-only-web` | `medium` |
| `project-context-analyst` | `read-only` | `medium` |
| `code-navigator` | `read-only` | `medium` |
| `code-locator` | `read-only` | `low` |
| `code-tracer` | `read-only` | `medium` |
| `log-analyzer` | `read-only` | `low` |
| `regression-finder` | `read-only` | `medium` |
| `environment-checker` | `read-only` | `medium` |
| `fix-reviewer` | `read-only` | `medium` |
| `plan-reviewer` | `read-only` | `medium` |

---

## Learned Lessons

No lessons recorded yet. Add `LC1`, `LC2`, ... as issues surface, following the `*Prevention:*` format used in the other rules files.

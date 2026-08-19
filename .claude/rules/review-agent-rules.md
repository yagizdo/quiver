# Review Agent Rules

Hard rules and learned lessons for writing agents that participate in `/quiver:review`.

**Scope:**
- Everything under `agents/review/` is covered by the full rule set (RA1-RA8) without exception.
- Cross-category research agents dispatched by `skills/review/SKILL.md` (currently `agents/research/best-practices-researcher.md` and `agents/research/project-context-analyst.md`) are a research-shaped exemption class, analogous to RA3's adversarial-agent exemptions. They MUST carry RA2 (hypothetical ban) in its canonical form, and SHOULD carry an RA1-equivalent discipline section, an RA5 zero-findings clause, an RA7 relevance/diff-scoping clause, and an RA8-equivalent citation rule. RA4 (stability test) and RA6 (severity earned, not assigned) do not apply because these agents surface context and facts rather than severity-graded findings -- the stability and severity-tier framings have no target to act on. When writing or editing a research agent, name this exemption explicitly in its discipline section so reviewers do not treat the missing rules as drift.
- Transport-adapter agents (currently `agents/review/codex-code-reviewer.md`) are an adapter-shaped exemption class. These agents do NOT review the diff -- they relay another reviewer's findings verbatim (e.g., the OpenAI Codex CLI). Because the agent emits no judgment of its own, RA1-RA8 review-discipline rules have no target and do not apply: there is no discipline section governing trace methodology (the agent traces nothing), no hypothetical-language ban applicable to passthrough output, no stability test on findings the agent did not author, no severity-tier rubric on severities the agent did not assign. The adapter's own discipline -- a passthrough contract forbidding interpretation, summarization, filtering, or rephrasing of the wrapped reviewer's output -- replaces the standard review discipline. When writing a transport-adapter agent, the agent file MUST contain a top-level "Adapter Discipline" section that names this exemption explicitly, so reviewers do not treat the missing review-discipline rules as drift. If a future adapter starts emitting its own analysis on top of the wrapped reviewer's findings, the exemption no longer holds and RA1-RA8 apply automatically.

For skill authoring rules, see `skill-rules.md`. For agent capability profiles, see `agent-capability-rules.md`.

---

## Hard Rules

Non-negotiable. Every review agent must follow all of these.

**RA1. Discipline section required.** Every review agent must have a top-level `## {Domain} Review Discipline` (or equivalent) section immediately after the role paragraph, before any phase/technique subsections. The section contains numbered rules that override phase-specific guidance.

**RA2. Hypothetical-language ban rule required.** Every review agent's discipline section must contain the canonical hypothetical-language ban rule (or a domain-specific exemption variant). The canonical text is:

> **N. Hypothetical language is banned.** Do not emit findings containing "could potentially", "might", "in the future", "consider", or "it would be better if". These phrases mark the finding as speculative. Do not emit findings whose severity relies on hypothetical future callers, hypothetical refactors, or unspecified future requirements. If you cannot state the problem as a present-tense concrete defect or risk with demonstrable consequences on current code, discard the finding. Speculation is not a finding.

Insert after any "concrete evidence required" rule and before the "stability test" rule if both exist. The canonical text must be byte-identical across all agents that use it. Use `shasum` or equivalent to verify after editing.

**RA3. Exemption variants for adversarial agents.** Agents whose core method is hypothetical reasoning (constructing attack scenarios, failure chains, what-if analyses) must use an exemption variant instead of the canonical text. The exemption names the allowed adversarial pattern explicitly. Two variants exist in the codebase:

- `stress-tester.md` uses a "constructible scenario" variant: speculation banned, but "if X happens then Y breaks" reasoning is allowed when paired with a specific trigger sequence.
- `security-audit.md` uses an "attack scenario" variant: speculation banned, but "an attacker could exploit this" is allowed when paired with a concrete exploit path (inputs, traversal, outcome).

When adding a new adversarial agent, draft an exemption variant that names its allowed hypothetical pattern. Do not weaken the ban; name what is allowed.

**RA4. Stability test rule required.** Every review agent must have a "stability test" rule: "Before reporting a finding, ask: 'Would I flag this exact issue if I reviewed the same diff cold tomorrow?' If the answer is 'maybe' -- discard it."

**RA5. Zero findings is success rule required.** Every review agent must state that zero findings is a valid and expected outcome on clean code. This exists to suppress the "produce findings to appear thorough" pressure.

**RA6. Severity earned, not assigned.** Every agent must document what earns each severity tier (Critical/High/Medium/Low), tied to concrete consequences, not feel.

**RA7. Diff-scoped findings.** Findings must target code changed in the diff. Reading surrounding code is allowed for context; flagging pre-existing issues is not, unless the diff worsens them or makes them newly reachable.

**RA8. Citation verification rule.** Every agent must have a "cite what you read, not what you assume" rule that requires reading the file before including a `file:line` reference. This catches phantom citations.

---

## Learned Lessons

**LA1. Copy-paste drift across agent files is real.**
When the same rule text is inserted into multiple agent files, future edits drift unless actively verified. `skills/review/SKILL.md` Task 14 of the 2026-04-10 calibration plan observed this.
*Prevention:* After inserting shared rule text into multiple files, hash the rule body (stripping the leading `N.` number prefix) across all files and verify a single identical hash. Example command:
```
for f in agents/.../*.md; do grep "{unique phrase}" "$f" | sed -E 's/^[[:space:]]*[0-9]+\. //' | shasum -a 256; done
```

**LA2. Discipline rules compose with orchestrator-level scope clauses.**
The review orchestrator (`skills/review/SKILL.md` Step 2 item 9) injects a general aspirational-lock clause into every agent prompt, and the Step 1 re-review block adds a delta-specific scope lock on top. Agent-level discipline rules must not contradict these orchestrator-level locks -- they must compose cleanly.
*Prevention:* When drafting a new discipline rule, re-read `skills/review/SKILL.md` Step 1 (Re-review detection) and Step 2 (per-agent context item 9) and verify the new rule does not contradict either. If a contradiction exists, the orchestrator-level clause wins; revise the agent rule.

**LA3. The synthesis stage filters hedged findings a second time.**
Even if an agent emits a hedged finding that violates its discipline, `skills/review/SKILL.md` Step 3 sub-item 4a (Proportional severity floor) and the existing 8 false-positive filters catch it at synthesis. This is a backstop, not a primary defense. Agent-level bans are the primary defense because they prevent the finding from existing in the first place; synthesis filters are the secondary net.
*Prevention:* Do not rely on synthesis filters to compensate for a weak agent-level discipline. If an agent produces noisy findings, fix the discipline rules in the agent file first.

**LA4. Research-agent exemptions depend on output shape, not identity.**
The research-shaped exemption in the preamble (research agents are exempt from RA4 stability test and RA6 severity-earned) is grounded in a specific fact about these agents' current output: they surface validated context, citations, and facts rather than severity-graded findings. RA4's "would I flag this exact issue cold tomorrow" framing has no target to act on when the output is a factual constraint; RA6's severity-tier rubric has nothing to grade when no severity is emitted. If a research agent evolves to emit severity-tiered findings (for example, a future version of `best-practices-researcher` that grades deprecation findings as Critical/High/Medium), the exemption no longer holds -- RA4 and RA6 apply automatically because their preconditions are now met. The exemption is conditional on output shape, not a permanent grant tied to the `agents/research/` directory.
*Prevention:* When editing a research agent's output to include severity tiers, stop and revisit RA4/RA6 applicability before merging. Add stability-test and severity-earned clauses to the agent's discipline section, or document why they still do not apply. Do not silently ship severity-tiered output with the old exemption in place.

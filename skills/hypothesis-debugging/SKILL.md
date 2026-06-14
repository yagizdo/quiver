---
name: hypothesis-debugging
description: "Hypothesis-first debugging -- collects symptoms, generates and tests hypotheses with conditional agent dispatch, falls back to adaptive exploration, and proposes reviewed fixes."
argument-hint: "<bug description, error message, or 'help me debug X'>"
when-to-use: "user wants to debug an error, bug, or failure -- '/hypothesis-debugging', 'debug this', 'fix this bug', 'why is this failing', 'help me debug', 'investigate this error'"
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree 2>/dev/null || echo "NO_GIT"`
```

```
!`git branch --show-current 2>/dev/null || echo "NO_GIT"`
```

```
!`git log --oneline -20 2>/dev/null || echo "NO_GIT"`
```

---

# Debug

Hypothesis-first debugging orchestrator. Investigates bugs systematically -- generating hypotheses, testing them against the codebase, and proposing reviewed fixes.

You are a senior debugging partner. You investigate bugs systematically -- generating hypotheses, testing them against the codebase, and proposing reviewed fixes. You think like a developer: hypothesize first, explore when hypotheses fail, and always verify before concluding.

## Step 0 -- Git Availability

If any gather-context block above returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- skipping git-dependent features (regression analysis, recent changes scan).`
Proceed to Step 0.5. Git-dependent features (regression-finder agent, recent changes scan) are skipped.

## Step 0.5 -- Input Validation

If the argument is empty and the conversation has no prior bug context:
> Usage: `/hypothesis-debugging <bug description, error message, or 'help me debug X'>`
>
> Provide an error message, log snippet, bug description, or just describe what's going wrong.

**Stop here.**

If the argument is present: use it as the initial bug description and proceed to Step 0.7.

## Step 0.7 -- Navigation Detection

Run once before any codebase searching. Cache results for the session.

1. **CodeGraph:** Check if `.codegraph/` directory exists at project root. If yes: `codegraph_available=true`. If no: `codegraph_available=false`. No user prompt.
2. **LSP:** Detect using the LSP Detection Flow from `skills/code-navigation/SKILL.md`. Cache as `lsp_available=true|false`.

These flags govern all codebase navigation in this skill -- both your own searches (Steps 1, 3, 4) and dispatched agent prompts (Step 3c).

### Navigation tier (use in all codebase searches)

When `codegraph_available: true`: call ToolSearch with query `"select:mcp__codegraph__codegraph_search,mcp__codegraph__codegraph_context,mcp__codegraph__codegraph_callers,mcp__codegraph__codegraph_callees,mcp__codegraph__codegraph_impact,mcp__codegraph__codegraph_node"` to load schemas. Then use `codegraph_search` for symbol lookups, `codegraph_context` for task-relevant files, `codegraph_callers`/`codegraph_callees` for call chains. Fall through to LSP then grep if codegraph returns insufficient results. For file discovery and pattern matching: always use Grep/Glob regardless.

When `codegraph_available: false` and `lsp_available: true`: use LSP `goToDefinition`/`findReferences`/`documentSymbol` first, grep as fallback.

When both unavailable: use Grep, Glob, and Read.

## Step 1 -- Symptom Collection

Gather all available context about the bug:

1. **Parse user input.** Extract: error messages, file paths, function names, stack trace fragments, log snippets, and behavioral descriptions. If the input contains error messages, stack traces, or log snippets, extract them verbatim as `raw_error_output` (preserve formatting). If no structured error output is present, note `raw_error_output: none`.

2. **Search the codebase** using the navigation tier from Step 0.7. Based on extracted keywords:
   - When `codegraph_available`: use `codegraph_search` for function/class names, `codegraph_context` with the bug description to find task-relevant files. Fall back to grep for error strings and text patterns.
   - When codegraph unavailable: search for error strings, function names, and file references via LSP or grep.
   - Read relevant files found by the search.

3. **Recent changes (git only).** If git is available:
   - List recently changed files: `git diff HEAD~5 --name-only`
   - Note which recently changed files overlap with the bug's affected area.

4. **Summarize.** Present findings to the user in 3-5 sentences: what was found in the codebase related to the issue, which files are involved, and what the initial observations suggest. Do NOT show raw grep output or file listings.

## Step 2 -- Hypothesis Generation

Based on symptoms from Step 1, generate 2-4 ranked hypotheses. Each hypothesis:

- **Statement:** One sentence -- what might be wrong.
- **Evidence:** Supporting observations from Step 1.
- **Test:** What to check to confirm or refute this hypothesis.

Present hypotheses to the user as a brief summary. This is NOT a blocking gate -- share thinking and move forward. The user can redirect ("skip hypothesis 2, I already checked that") or let the skill proceed.

Use `AskUserQuestion` ONLY if the skill genuinely needs critical input to proceed (e.g., "I found 3 possible entry points for this error -- which one are you seeing?"). Otherwise, proceed directly to testing.

## Step 3 -- Hypothesis Testing

Test each hypothesis in order (highest likelihood first).

### 3a -- Determine what to check

For each hypothesis, identify what investigation is needed: file reads, call chain tracing, log parsing, git history analysis, config inspection, or direct code inspection.

### 3b -- Agent dispatch decision tree

Evaluate for each hypothesis:

```
Is the hypothesis about multi-file control flow or a call chain?
  YES -> dispatch code-tracer agent
  NO  -> continue

Did the user provide log output, stack traces, or error dumps?
  YES -> dispatch log-analyzer agent
  NO  -> continue

Is this a regression ("used to work") or does hypothesis point to a recent change?
  YES, and git available -> dispatch regression-finder agent
  NO  -> continue

Does hypothesis involve dependencies, config, or environment setup?
  YES -> dispatch environment-checker agent
  NO  -> continue

None of the above?
  -> Handle directly using the navigation tier from Step 0.7
     (codegraph_search/codegraph_context when available, then LSP, then grep/Read)
```

### 3c -- Dispatch qualifying agents

Dispatch qualifying agents in parallel (multiple Agent tool calls in a single response). Each agent prompt must be self-contained and include:
- The specific hypothesis being tested
- Relevant file paths from Step 1
- User's original bug description
- Symptom summary from Step 1.4 (the curated synthesis of codebase findings -- not the raw bug description)
- Recent changes context from Step 1.3 (recently changed files and their overlap with the bug area) -- include only if git is available
- Raw error/log output extracted in Step 1.1 (verbatim stack traces, error messages, log snippets) -- include only if present
- `codegraph_available` and `lsp_available` flags from Step 0.7

Pass both flags to each dispatched agent. Agents that search the codebase (code-tracer, regression-finder, environment-checker) carry the Code Navigation Strategy block from `skills/code-navigation/SKILL.md` and will call ToolSearch to load codegraph tools when `codegraph_available: true`.

For simple single-file checks: handle directly without agent dispatch. Read the file, inspect the relevant code, and evaluate the hypothesis.

### 3d -- Evaluate results

After agent results (or direct investigation) return:

- Hypothesis **confirmed**: root cause found. Skip remaining hypotheses, go to Step 5.
- Hypothesis **refuted**: move to next hypothesis.
- Hypothesis **inconclusive**: note the unknown, move to next hypothesis.

## Step 4 -- Adaptive Exploration

Triggered when: all hypotheses are refuted, or symptoms are too vague for meaningful hypotheses.

1. **Ask targeted questions** via `AskUserQuestion` to narrow the search. Derive questions from the specific bug context -- not from templates. Examples of the kind of questions to ask:
   - "Can you reproduce this consistently, or is it intermittent?"
   - "When did this last work correctly?"
   - "Does this happen in all environments or just [specific]?"

2. **Explore** based on user's answers using the navigation tier from Step 0.7. When codegraph is available, use `codegraph_context` with refined search terms and `codegraph_callers`/`codegraph_callees` to trace related code paths. Fall back to grep/Read when codegraph returns insufficient results.

3. **Generate new hypotheses** from exploration findings.

4. **Return to Step 3** with new hypotheses.

**Bound:** Maximum 2 exploration rounds. After 2 rounds without a confirmed root cause:
- Report what was investigated and ruled out.
- Suggest alternative strategies: adding logging at specific points, creating a minimal reproduction case, or checking external dependencies.
- Stop.

## Step 5 -- Root Cause + Fix Proposals

Once root cause is confirmed:

### 5a -- Present root cause

- **What** is wrong (one paragraph)
- **Where** it happens (file:line references)
- **Why** it happens (the mechanism)

### 5b -- Generate fix proposals

Generate 1-3 fix proposals (simplest first):
- Each proposal: what changes, which files, why it fixes the root cause, trade-offs (if any).
- First proposal MUST be the minimal correct fix.
- Additional proposals only if genuinely different approaches exist (not cosmetic variations).

## Step 6 -- Mandatory Fix Review

Dispatch the `fix-reviewer` agent with:
- Root cause description from Step 5a
- All fix proposals from Step 5b with their descriptions
- File paths and relevant project context (existing patterns in the affected area)

Integrate agent feedback:
- Proposals flagged as OVERENGINEERING or WORKAROUND: revise or drop.
- Proposals with SIDE_EFFECT flags: add the side effect to the proposal's trade-offs.
- Proposals that pass: present to user as-is.

## Step 7 -- Fix Application

Present reviewed proposals to user via `AskUserQuestion`:
- One button per approved proposal (label: proposal name)
- Final button: "None -- keep the diagnosis, skip the fix"

If user selects a proposal:
1. Apply the code changes using Edit tool.
2. Read back modified files to verify changes.
3. Suggest verification: "Run tests with [command]" or "Check [specific behavior] manually."

If user selects "None": stop with a summary of the root cause.

---

## Anti-Patterns

- Don't ask more than 1 clarifying question per exploration round -- keep forward momentum
- Don't show raw agent output to the user -- synthesize into plain language
- Don't dispatch agents for simple single-file checks -- handle them directly
- Don't generate more than 3 fix proposals -- decision fatigue kills momentum
- Don't present unreviewed fixes -- every proposal goes through fix-reviewer
- Don't apply fixes without user approval
- Don't show internal routing decisions ("Dispatching code-tracer because...") -- implementation detail
- Don't continue debugging indefinitely -- 2 exploration rounds max before reporting partial findings

---

## Test Plan

**Trigger:** `/hypothesis-debugging <description>` (and `/quiver:hypothesis-debugging`)

**Setup:**
- Any git repository with source code.
- A bug to investigate (real or simulated).

**Expected behavior:**
1. Skill gathers git context and parses user's bug description.
2. Skill generates 2-4 hypotheses based on symptoms and codebase scan.
3. Skill tests hypotheses, dispatching agents conditionally (only when their specialization adds value).
4. If hypotheses fail, skill enters adaptive exploration (max 2 rounds) with targeted user questions via AskUserQuestion.
5. On confirmed root cause, skill generates fix proposals (simplest first) and dispatches fix-reviewer.
6. After fix review, skill presents approved proposals to user via AskUserQuestion.
7. On user selection, skill applies the fix and suggests verification steps.

**Verification checklist:**
- [ ] Slash menu shows `/debug`.
- [ ] Simple single-file bugs resolve without any agent dispatch.
- [ ] Complex multi-file bugs trigger code-tracer dispatch.
- [ ] Log/stack trace input triggers log-analyzer dispatch.
- [ ] Regression scenarios trigger regression-finder dispatch.
- [ ] Environment/config bugs trigger environment-checker dispatch.
- [ ] Every fix proposal passes through fix-reviewer before user sees it.
- [ ] No fix applied without user confirmation via AskUserQuestion.
- [ ] Adaptive exploration bounded to 2 rounds.
- [ ] All user decision points use AskUserQuestion, not plain text.

**Known gotchas:**
- Agent dispatch decision tree runs once per hypothesis, not once globally. A single debugging session may dispatch different agents for different hypotheses.
- The fix-reviewer is dispatched in Step 6 (after proposals are ready), not in Step 3 (during hypothesis testing). Do not confuse the two dispatch points.
- LSP detection happens once (Step 3, first agent dispatch) and is cached for the session.

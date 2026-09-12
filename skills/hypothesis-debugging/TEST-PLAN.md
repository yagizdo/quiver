# Test Plan -- /hypothesis-debugging

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
7. On user selection, skill writes a reproducing test and prints its `red:` line, applies the fix, runs the resolved test command and reports its evidence line -- or names the reason once when no command resolves.
8. If the run after the fix fails, skill reverses the code change, records the root cause as refuted, and re-enters Step 2 once; a second failure ends the run with the ruled-out list and, when the refutations point at one, a named design assumption with its evidence.

**Verification checklist:**
- [ ] Slash menu shows `/debug`.
- [ ] Simple single-file bugs resolve without any agent dispatch.
- [ ] Complex multi-file bugs trigger code-tracer dispatch.
- [ ] Log/stack trace input triggers log-analyzer dispatch.
- [ ] Regression scenarios trigger regression-finder dispatch.
- [ ] Environment/config bugs trigger environment-checker dispatch.
- [ ] Every fix proposal passes through fix-reviewer before user sees it.
- [ ] No fix applied without user confirmation via AskUserQuestion.
- [ ] After a fix, the skill prints an evidence line with an exit code, or a none reason -- never a bare "run the tests".
- [ ] Before the fix is applied, a `red:` line names the reproducing test; after it, a pass line follows -- or one `skipped:` reason covers both when no command resolves.
- [ ] Adaptive exploration bounded to 2 rounds.
- [ ] A failed post-fix run never gets a second patch on top of the first; the first change is reversed and the root cause is re-examined, at most once.
- [ ] The stop report names a design assumption only together with the evidence that undercuts it, never as a bare label.
- [ ] All user decision points use AskUserQuestion, not plain text.

**Known gotchas:**
- Agent dispatch decision tree runs once per hypothesis, not once globally. A single debugging session may dispatch different agents for different hypotheses.
- The fix-reviewer is dispatched in Step 6 (after proposals are ready), not in Step 3 (during hypothesis testing). Do not confuse the two dispatch points.
- LSP detection happens once (Step 3, first agent dispatch) and is cached for the session.

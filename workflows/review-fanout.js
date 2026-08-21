/**
 * review-fanout -- the deterministic dispatch path for /quiver:review Step 2.
 *
 * The skill decides WHICH review this is; this script decides which agents that review
 * dispatches, hands each one the same context the prompt path hands it, and (in deep mode)
 * puts every finding in front of independent refuters before it reaches synthesis.
 *
 * The script runs no shell, touches no file, and loads no module. Every value it needs is
 * either a literal below or arrives through `args`, and `args` is undefined when the caller
 * omits it. Read `.claude/rules/workflow-rules.md` (WF1-WF9) before editing.
 *
 * ---------------------------------------------------------------------------
 * args contract
 * ---------------------------------------------------------------------------
 * This list is the same one documented at the call site in `skills/review/SKILL.md` Step 2
 * under "**`args` payload.**". The two must agree; a field added here without being added
 * there arrives undefined on every real run.
 *
 * Required -- the run terminates with a logged message when any of these is absent:
 *
 *   manifest   array   The Diff Manifest from Step 1.5 as structured data, one entry per
 *                      changed file: { path: <string>, class: <string> }. Pass the data,
 *                      not the rendered text. The class vocabulary is exactly:
 *                        PROMPT, SCRIPT, CONFIG-APP, CONFIG-MANIFEST, CODE, DOCS
 *                      SCRIPT, CODE and CONFIG-APP are the three classes any gate names.
 *                      PROMPT, DOCS and CONFIG-MANIFEST satisfy no class gate: a diff made
 *                      only of those dispatches the unconditional agents and nothing else.
 *   agents     array   The agents discovered in Step 2a. Each entry is either the agent's
 *                      frontmatter `name` as a plain string, or an object carrying a `name`
 *                      property. The name is what builds the `quiver:<name>` agent type;
 *                      the category subdirectory is not part of the identifier.
 *   mode       string  'fast' or 'deep', from `review_mode`. Anything else terminates.
 *   diff       string  The full diff obtained in Step 1.
 *
 * Optional -- each one is omitted from the assembled prompts when absent:
 *
 *   risk_signals                  string | array  Risk signals detected in Step 1.5 (new
 *                                 dependencies, auth changes, secrets handling, new
 *                                 endpoints). Feeds stress-tester's depth calibration here
 *                                 and returns in the envelope for the Step 3 severity floor.
 *   delta_diff                    string  `git diff <previous_head_sha>...HEAD`, on a
 *                                 re-review only.
 *   review_context                string | object  Branches compared, diff source used, and
 *                                 the PR/MR URL when Mode 1 supplied one.
 *   iteration                     number  Re-review iteration. Present only on a re-review;
 *                                 its presence is what adds context item 4.
 *   codegraph_available           boolean  From Step 1.75.
 *   lsp_available                 boolean  From Step 1.75.
 *   root_listing                  string  The `ls` of the project root that
 *                                 architecture-strategist maps conventions against.
 *   changed_files_with_languages  string | array  Changed files tagged with detected
 *                                 languages and frameworks, which best-practices-researcher
 *                                 uses to target its lookups.
 *   codex_requested               boolean  `$ARGUMENTS` contained `--with-codex`.
 *   codex_on_path                 boolean  `command -v codex` found the CLI.
 *   codex_diff_within_limit       boolean  The diff is 2000 lines or fewer.
 *                                 The three codex booleans are resolved by the caller
 *                                 because none of them is manifest-expressible and this
 *                                 script cannot run a shell.
 *
 * ---------------------------------------------------------------------------
 * returned envelope
 * ---------------------------------------------------------------------------
 * {
 *   ok:           boolean   false only when the run terminated before dispatching.
 *   reason:       string    Present only when ok is false.
 *   mode:         string    The mode the run applied.
 *   dispatched:   array     Agent names that were dispatched, in gate-evaluation order.
 *   reports:      array     One entry per agent that returned: { agent, report, kept,
 *                           refuted }. `report` is markdown in the same per-agent shape
 *                           Step 3 consumes on the prompt path, so synthesis sees the same
 *                           input either way.
 *   dispatch_log: array     One entry per agent that was NOT dispatched:
 *                           { agent, exclusion, note, reduced_requested_coverage }.
 *                           `exclusion` is 'mode', 'file-type' or 'precondition' -- every
 *                           entry carries its class, because the skill applies a different
 *                           rule to each:
 *                             'mode'         note is null by construction. Never printed.
 *                                            Step 2b forbids skip notes for agents excluded
 *                                            by mode.
 *                             'file-type'    note is printed in the chat stream at dispatch
 *                                            time and is NOT listed in the report; Step 4b
 *                                            calls these routine.
 *                             'precondition' note is printed in the chat stream, and listed
 *                                            in the report only when
 *                                            reduced_requested_coverage is true -- Step 4b
 *                                            lists only skips that cut coverage the user
 *                                            explicitly asked for.
 *                           Agents whose canonical gate is NEVER produce no entry at all:
 *                           they are not Step 2 participants and counting them as skipped
 *                           is the bug this distinction prevents.
 *   ungated:      array     Agent names with no row in the canonical gate table. They were
 *                           dispatched anyway -- the fan-out fails open rather than dropping
 *                           a reviewer -- and each one is named in a log() line.
 *   refuted:      array     Deep mode only. One entry per finding the refutation quorum
 *                           dropped: { agent, severity, location, title, refute_count,
 *                           refuter_count }.
 *   risk_signals: any       Echoed back verbatim for the Step 3 proportional severity floor.
 * }
 */

export const meta = {
  name: 'review-fanout',
  description: 'Gate, dispatch and refute the /quiver:review agent fan-out deterministically',
  whenToUse: 'Called by the /quiver:review skill when --workflow is passed and the Workflow tool is available. Applies the canonical dispatch gates, assembles the same nine context items the prompt path assembles, and in deep mode puts every finding through an independent refutation quorum. Every value it needs arrives in args; it reads nothing from disk.',
  phases: [
    { title: 'Dispatch', detail: 'gate each discovered agent, then fan the survivors out' },
    { title: 'Verify', detail: 'deep mode only -- independent refuters per finding' },
  ],
};

// ---------------------------------------------------------------------------
// Dispatch gates
// ---------------------------------------------------------------------------
// SYNC: `.claude/rules/review-agent-rules.md` `## Dispatch Gates` is canonical. This table
// is a copy of it, `skills/review/SKILL.md` Step 2b prose is the other copy, and
// `tests/skills/test-review-dispatch-contract.sh` is the binding that fails when a copy
// drifts. Change the canonical table first, then both copies, then run the verifier.
//
// The format below is load-bearing, not styling. The verifier extracts this block with awk
// between the DISPATCH_GATES declaration below and the line that closes it with `};`, matches
// each key on the single quotes and the following colon, and takes only the FIRST match per
// line. One key per line, single-quoted. Double-quoted keys extract zero rows and the
// comparison passes vacuously; two keys on one line silently drops the second.
const DISPATCH_GATES = {
  'waste-detector': { gate: 'UNCONDITIONAL', modes: ['fast', 'deep'] },
  'project-context-analyst': { gate: 'UNCONDITIONAL', modes: ['fast', 'deep'] },
  'security-audit': { gate: 'SCRIPT, CODE, CONFIG-APP', modes: ['fast', 'deep'] },
  'logic-reviewer': { gate: 'SCRIPT, CODE', modes: ['fast', 'deep'] },
  'best-practices-researcher': { gate: 'SCRIPT, CODE', modes: ['fast', 'deep'] },
  'architecture-strategist': { gate: 'SCRIPT, CODE, CONFIG-APP', modes: ['deep'] },
  'developer-experience-auditor': { gate: 'SCRIPT, CODE', modes: ['deep'] },
  'test-reviewer': { gate: 'SCRIPT, CODE', modes: ['deep'] },
  'stress-tester': { gate: 'SCRIPT, CODE', modes: ['deep'] },
  'codex-code-reviewer': { gate: 'PRECONDITION', modes: ['deep'] },
  'report-checker': { gate: 'NEVER', modes: [] },
  'senior-reviewer': { gate: 'NEVER', modes: [] },
};

// The four agents Step 1.75 names as searching the broader codebase. Only these receive
// context item 8; the others are diff-scoped and do not need the navigation flags.
const NAVIGATION_AGENTS = [
  'waste-detector',
  'architecture-strategist',
  'stress-tester',
  'project-context-analyst',
];

// Step 1.5's taxonomy, used only to render the manifest the way the prompt path renders it.
const CLASS_SECURITY_RELEVANCE = {
  'PROMPT': 'low',
  'SCRIPT': 'high',
  'CONFIG-APP': 'high',
  'CONFIG-MANIFEST': 'low',
  'CODE': 'high',
  'DOCS': 'low',
};

// Verbatim from each agent's bullet in skills/review/SKILL.md Step 2b. These are the notes
// a file-type-gate exclusion carries; the skill prints them at dispatch time.
const FILE_TYPE_SKIP_NOTES = {
  'security-audit': 'Skipping security-audit: no application code, scripts, or security-relevant configuration changed.',
  'best-practices-researcher': 'Skipping best-practices-researcher: no application code or scripts changed.',
  'architecture-strategist': 'Skipping architecture-strategist: no application code, scripts, or structural configuration changed.',
  'developer-experience-auditor': 'Skipping developer-experience-auditor: no application code or scripts changed.',
  'logic-reviewer': 'Skipping logic-reviewer: no application code or scripts changed.',
  'test-reviewer': 'Skipping test-reviewer: no application code or scripts changed.',
  'stress-tester': 'Skipping stress-tester: no application code or scripts changed.',
};

// The three codex-code-reviewer precondition notes, verbatim from the same bullet. The third
// one reads "({actual_count} lines)" in the skill; the count is not part of the args
// contract, so it is derived from the diff below rather than left as an unfilled placeholder.
const CODEX_NOT_REQUESTED_NOTE = 'Skipping codex-code-reviewer: --with-codex flag not provided.';
const CODEX_NOT_ON_PATH_NOTE = 'Skipping codex-code-reviewer: codex CLI not found on PATH. Install with `npm install -g @openai/codex` (>= 0.123.0) or run `/codex:setup` from the openai/codex-plugin-cc plugin.';
const CODEX_DIFF_TOO_LARGE_PREFIX = 'Skipping codex-code-reviewer: diff exceeds 2000 lines (';
const CODEX_DIFF_TOO_LARGE_SUFFIX = ' lines). Codex review is skipped for large diffs to avoid excessive token consumption and timeouts.';

// Refutation quorum. Both numbers are constants so the first real deep run can move them:
// three skeptics told to default to refuted will drop a correct finding whose evidence is
// subtle, and that trade is meant to be re-tuned against measured output, not argued about.
const REFUTER_COUNT = 3;
const REFUTATION_MAJORITY = Math.floor(REFUTER_COUNT / 2) + 1;
const REFUTER_PASSES = Array.from({ length: REFUTER_COUNT }, (unusedValue, offset) => offset + 1);

const REQUIRED_ARGS = ['manifest', 'agents', 'mode', 'diff'];

// ---------------------------------------------------------------------------
// Structured output schemas
// ---------------------------------------------------------------------------
// Inside the documented subset: no $schema, additionalProperties false on every object, a
// complete `required` list, enum on the closed field, and no length or count keywords --
// those are not supported and drop the whole schema back to non-strict validation. What
// they would have said is said in the per-field descriptions instead.
const AGENT_FINDINGS_SCHEMA = {
  type: 'object',
  description: 'One review agent\'s result on the diff it was given.',
  properties: {
    summary: {
      type: 'string',
      description: 'The summary paragraph your agent definition asks for, in its own words. One paragraph, no findings list.',
    },
    verdict: {
      type: 'string',
      description: 'The verdict line your agent definition asks for, worded the way that definition words it.',
    },
    findings: {
      type: 'array',
      description: 'One entry per finding you stand behind after applying your own discipline rules. An empty array is a correct and expected result on clean code -- do not pad it.',
      items: {
        type: 'object',
        description: 'A single finding.',
        properties: {
          severity: {
            type: 'string',
            enum: ['Critical', 'High', 'Medium', 'Low'],
            description: 'The severity your agent definition earns for this finding, not the one that makes it look important.',
          },
          title: {
            type: 'string',
            description: 'The short title from your finding header line. One line, no severity marker, no file path.',
          },
          location: {
            type: 'string',
            description: 'The file:line reference for this finding, formatted as path/to/file.ext:123 -- a repository-relative path, a colon, and the line number you confirmed by reading the file. Use the first relevant line when the finding spans a range.',
          },
          body: {
            type: 'string',
            description: 'The agent\'s native finding block verbatim -- every labelled line your agent definition specifies (evidence, recommendation, scenario, and so on) exactly as you would have written it in prose, minus the header line whose three parts are carried in severity, title and location.',
          },
        },
        required: ['severity', 'title', 'location', 'body'],
        additionalProperties: false,
      },
    },
  },
  required: ['summary', 'verdict', 'findings'],
  additionalProperties: false,
};

const REFUTATION_SCHEMA = {
  type: 'object',
  description: 'One independent skeptic\'s ruling on one finding.',
  properties: {
    refuted: {
      type: 'boolean',
      description: 'true when the finding does not hold as written, including when you are uncertain. false only when you tried to break it and could not.',
    },
    reason: {
      type: 'string',
      description: 'One or two sentences naming what you checked and what you found there. Cite the line you read.',
    },
  },
  required: ['refuted', 'reason'],
  additionalProperties: false,
};

// ---------------------------------------------------------------------------
// Rendering helpers
// ---------------------------------------------------------------------------

function renderValue(value) {
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value === 'string') {
    return value;
  }
  if (Array.isArray(value)) {
    return value
      .map((entry) => (typeof entry === 'string' ? '- ' + entry : '- ' + JSON.stringify(entry)))
      .join('\n');
  }
  return JSON.stringify(value, null, 2);
}

// Counts lines the way `wc -l` counts them, so a number rendered here agrees with the number
// the caller measured when it resolved codex_diff_within_limit.
function lineCount(text) {
  if (typeof text !== 'string' || text.length === 0) {
    return 0;
  }
  return text.split('\n').length - 1;
}

function agentName(entry) {
  if (typeof entry === 'string') {
    return entry.trim();
  }
  if (entry !== null && typeof entry === 'object' && typeof entry.name === 'string') {
    return entry.name.trim();
  }
  return '';
}

function classOf(entry) {
  if (entry === null || typeof entry !== 'object') {
    return '';
  }
  const raw = typeof entry.class === 'string' ? entry.class : entry.type;
  return typeof raw === 'string' ? raw.trim().toUpperCase() : '';
}

function pathOf(entry) {
  if (entry !== null && typeof entry === 'object' && typeof entry.path === 'string') {
    return entry.path;
  }
  return '(unnamed file)';
}

function has(table, key) {
  return Object.prototype.hasOwnProperty.call(table, key);
}

function renderManifest(entries) {
  const lines = ['Diff Manifest:'];
  entries.forEach((entry) => {
    const cls = classOf(entry);
    if (cls === '') {
      lines.push('- ' + pathOf(entry) + ' -> (class not supplied)');
      return;
    }
    const relevance = has(CLASS_SECURITY_RELEVANCE, cls) ? CLASS_SECURITY_RELEVANCE[cls] : 'unknown';
    lines.push('- ' + pathOf(entry) + ' -> ' + cls + ' (' + relevance + ' security relevance)');
  });
  return lines.join('\n');
}

// The gate is a comma-separated alternation, never a conjunction: one CODE file satisfies
// "SCRIPT, CODE, CONFIG-APP" on its own.
function gateSatisfied(gate, presentClasses) {
  return gate
    .split(',')
    .map((token) => token.trim())
    .filter((token) => token.length > 0)
    .some((token) => presentClasses.indexOf(token) !== -1);
}

// ---------------------------------------------------------------------------
// Prompt assembly
// ---------------------------------------------------------------------------
// The nine context items below are the ones skills/review/SKILL.md Step 2 lists, in the
// order it lists them. Items 2, 6, 7 and 9 are fixed strings lifted from that list and must
// stay byte-identical to it: two paths that dispatch the same agents under different
// instructions are worse than one slow path. Item 4 appears only on a re-review, item 8 only
// for the four agents that search beyond the diff. The item numbers are printed rather than
// renumbered, so an omitted item leaves a visible gap instead of silently shifting the rest.
function buildAgentPrompt(name, ctx) {
  const parts = [];

  parts.push(
    'You are the `' + name + '` agent, dispatched by /quiver:review to review one diff.',
    'Follow your own agent definition for methodology, discipline rules and severity rubric.',
    'Everything below is orchestrator-supplied context, identical to what the standard fan-out supplies.',
    ''
  );

  parts.push('### Context item 1 -- Diff Manifest', '', ctx.manifestText, '');

  parts.push(
    '### Context item 2 -- Scope reminder',
    '',
    'Your findings MUST be scoped to code CHANGED in this diff. Respect file classifications in the Diff Manifest.',
    ''
  );

  parts.push('### Context item 3 -- Review context', '');
  parts.push(ctx.reviewContextText === '' ? 'Not supplied by the orchestrator.' : ctx.reviewContextText);
  parts.push('');

  if (ctx.isReReview) {
    parts.push(
      '### Context item 4 -- Re-review context',
      '',
      'This is re-review iteration ' + ctx.iteration + '. ONLY flag issues that are NEW in the delta since the previous review or regressions of previously-fixed findings. Do NOT flag pre-existing patterns, stylistic preferences, or aspirational improvements. If the delta contains no functional changes, return zero findings.',
      ''
    );
  }

  parts.push('### Context item 5 -- Full diff', '', '[BEGIN FULL DIFF]', ctx.diff, '[END FULL DIFF]', '');
  if (ctx.deltaDiff !== '') {
    parts.push('Delta since the previous review:', '', '[BEGIN DELTA DIFF]', ctx.deltaDiff, '[END DELTA DIFF]', '');
  }

  parts.push(
    '### Context item 6 -- File scope reminder',
    '',
    'Review ALL file types in the diff regardless of language or type -- shell scripts, config files, CI configs, and build scripts deserve the same scrutiny as application source code.',
    ''
  );

  parts.push(
    '### Context item 7 -- Citation accuracy',
    '',
    'Every file:line reference in your findings must be verified by reading the file. Do not cite line numbers from memory or inference -- use the Read tool to confirm the content at the cited line before including it in a finding.',
    ''
  );

  if (NAVIGATION_AGENTS.indexOf(name) !== -1) {
    parts.push(
      '### Context item 8 -- Navigation availability',
      '',
      'codegraph_available: ' + String(ctx.codegraphAvailable),
      'lsp_available: ' + String(ctx.lspAvailable),
      '',
      'You search the broader codebase, so follow the code-navigation strategy: CodeGraph first when codegraph_available is true, LSP next when lsp_available is true, grep last.',
      ''
    );
  }

  parts.push(
    '### Context item 9 -- Scope discipline',
    '',
    'Aspirational improvements, stylistic preferences, "could be better" suggestions, and theoretical hardening are out of scope. Flag only concrete demonstrable problems with code that is wrong, unsafe, or broken as written. If the code works correctly as written and you would not fix it yourself, do not flag it. Zero findings is a correct and expected result on clean code. (This clause applies on every review. Re-review mode adds additional delta-specific scope on top of this general lock.)',
    ''
  );

  if (name === 'architecture-strategist' && ctx.rootListingText !== '') {
    parts.push(
      '### Agent context -- project root listing',
      '',
      'Map the project conventions in your first phase against this listing.',
      '',
      ctx.rootListingText,
      ''
    );
  }

  if (name === 'best-practices-researcher' && ctx.changedFilesText !== '') {
    parts.push(
      '### Agent context -- changed files with detected languages and frameworks',
      '',
      'Target your documentation lookups at these languages and frameworks.',
      '',
      ctx.changedFilesText,
      ''
    );
  }

  if (name === 'security-audit' && ctx.mode === 'fast') {
    parts.push(
      '### Agent context -- fast mode check',
      '',
      'FAST MODE CHECK: For state management and interactive flows, verify every user-initiated process has a guaranteed termination path (timeout, cancel handler, forced cleanup). Missing exit conditions on partial user actions create livelock -- flag as High.',
      ''
    );
  }

  if (name === 'stress-tester') {
    parts.push(
      '### Agent context -- depth calibration',
      '',
      'Calibrate scenario depth against the file classes in the Diff Manifest above and the risk signals below.',
      '',
      'Risk signals: ' + (ctx.riskSignalsText === '' ? 'none detected' : ''),
      ctx.riskSignalsText,
      ''
    );
  }

  parts.push(
    '### Return format',
    '',
    'Return your result through the structured output schema attached to this call, not as prose.',
    '- summary: your summary paragraph.',
    '- verdict: your verdict line.',
    '- findings: one entry per finding you stand behind. Split each finding header into severity, title and location; put the rest of the finding block in body, worded exactly as you would have written it. Zero findings is a correct result -- return an empty list rather than padding it.',
    ''
  );

  return parts.join('\n');
}

function buildRefutePrompt(name, finding, pass, ctx) {
  return [
    'You are an independent skeptic. One finding produced by the `' + name + '` review agent is below.',
    'Your job is to REFUTE it, not to confirm it. This is refutation pass ' + pass + ' of ' + REFUTER_COUNT + ';',
    'the other passes are running without your reasoning and you are not meant to agree with them.',
    '',
    '### Finding under challenge',
    '',
    'Severity: ' + finding.severity,
    'Location: ' + finding.location,
    'Title: ' + finding.title,
    '',
    finding.body,
    '',
    '### How to rule',
    '',
    '- Read the cited file at the cited location before ruling. A citation you cannot confirm is a refutation.',
    '- The finding survives only when the defect it describes is present in the code as written and its consequence is demonstrable on that code today.',
    '- A finding resting on a caller that does not exist, a requirement nobody stated, or a sequence you cannot construct from this diff is refuted.',
    '- Reviewing the same code and disagreeing about taste is not a refutation; showing the finding is wrong about what the code does is.',
    '- Default to refuted when you are uncertain. Uncertainty is a refutation here, not a tie.',
    '',
    '### Diff under review',
    '',
    '[BEGIN FULL DIFF]',
    ctx.diff,
    '[END FULL DIFF]',
    '',
    'Return refuted: true when the finding does not hold, refuted: false only when you tried to break it and could not.',
  ].join('\n');
}

// Re-renders a structured result into the per-agent markdown shape Step 3 already consumes,
// so synthesis reads the same input on both paths and the skills/work/SKILL.md Phase 4c SYNC
// contract keeps holding. Findings the quorum dropped are deliberately NOT rendered here:
// they are reported through the envelope and the run log instead, so synthesis cannot pick a
// refuted finding back up out of the text.
function renderReport(name, result) {
  const lines = [];
  lines.push('## ' + name + ' report');
  lines.push('');
  lines.push('### Summary');
  lines.push('');
  lines.push(typeof result.summary === 'string' ? result.summary : '');
  lines.push('');
  lines.push('### Findings');
  lines.push('');

  const findings = Array.isArray(result.findings) ? result.findings : [];
  if (findings.length === 0) {
    lines.push('No findings.');
    lines.push('');
  } else {
    findings.forEach((finding) => {
      lines.push('[' + finding.severity + '] ' + finding.location + ' -- ' + finding.title);
      lines.push(finding.body);
      lines.push('');
    });
  }

  lines.push('### Verdict');
  lines.push('');
  lines.push(typeof result.verdict === 'string' ? result.verdict : '');
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// args guard
// ---------------------------------------------------------------------------
// Terminates with a logged message rather than throwing. A throw here dies before the first
// phase opens and reaches the caller as an error naming the destructure instead of the
// missing payload; a returned envelope with no reports lands in the skill's failure arm,
// which re-runs the fan-out on the prompt path.

if (args === undefined || args === null || typeof args !== 'object' || Array.isArray(args)) {
  log('Deterministic review dispatch stopped before it started: no review payload was supplied to the workflow.');
  return { ok: false, reason: 'missing-args', mode: '', dispatched: [], reports: [], dispatch_log: [], ungated: [], refuted: [] };
}

const missingArgs = REQUIRED_ARGS.filter((field) => args[field] === undefined || args[field] === null);
if (missingArgs.length > 0) {
  log('Deterministic review dispatch stopped before it started: the review payload is missing ' + missingArgs.join(', ') + '.');
  return { ok: false, reason: 'incomplete-args', missing: missingArgs, mode: '', dispatched: [], reports: [], dispatch_log: [], ungated: [], refuted: [] };
}

const mode = String(args.mode).trim().toLowerCase();
if (mode !== 'fast' && mode !== 'deep') {
  log('Deterministic review dispatch stopped before it started: the review mode was neither fast nor deep.');
  return { ok: false, reason: 'unknown-mode', mode: mode, dispatched: [], reports: [], dispatch_log: [], ungated: [], refuted: [] };
}

const manifest = Array.isArray(args.manifest) ? args.manifest : [];
const agentEntries = Array.isArray(args.agents) ? args.agents : [];
const iteration = typeof args.iteration === 'number' ? args.iteration : null;

const ctx = {
  mode: mode,
  diff: String(args.diff),
  deltaDiff: renderValue(args.delta_diff),
  manifestText: renderManifest(manifest),
  reviewContextText: renderValue(args.review_context),
  riskSignalsText: renderValue(args.risk_signals),
  rootListingText: renderValue(args.root_listing),
  changedFilesText: renderValue(args.changed_files_with_languages),
  codegraphAvailable: args.codegraph_available === true,
  lspAvailable: args.lsp_available === true,
  isReReview: iteration !== null,
  iteration: iteration,
};

// ---------------------------------------------------------------------------
// Gating
// ---------------------------------------------------------------------------

phase('Dispatch');

const presentClasses = [];
let unclassifiedFiles = 0;
manifest.forEach((entry) => {
  const cls = classOf(entry);
  if (cls === '') {
    unclassifiedFiles = unclassifiedFiles + 1;
    return;
  }
  if (presentClasses.indexOf(cls) === -1) {
    presentClasses.push(cls);
  }
});
if (unclassifiedFiles > 0) {
  log('Note: ' + unclassifiedFiles + ' changed file(s) arrived without a manifest class, so they count toward no file-type gate.');
}

const dispatchable = [];
const dispatchLog = [];
const ungated = [];

agentEntries.forEach((entry) => {
  const name = agentName(entry);
  if (name === '') {
    return;
  }

  const row = has(DISPATCH_GATES, name) ? DISPATCH_GATES[name] : null;

  // NEVER is checked before anything else. report-checker and senior-reviewer run at later
  // steps of the review, so they are not Step 2 participants: they belong to no total, and
  // logging them as skipped would put deep-only agents in the fast-mode report's skip list.
  if (row !== null && row.gate === 'NEVER') {
    return;
  }

  // Absent from the table: dispatched unconditionally. Dispatching too much is recoverable;
  // silently reviewing nothing is not. The verifier turns this into a loud failure at test
  // time, which is where it belongs.
  if (row === null) {
    ungated.push(name);
    dispatchable.push(name);
    log('The ' + name + ' agent has no dispatch gate on record, so it was included on this diff without a file-type check. Add its row to .claude/rules/review-agent-rules.md.');
    return;
  }

  // Excluded by mode. Logged internally and carrying no note: the skill prints skip notes
  // only for agents excluded by their file-type gate within the active set.
  if (row.modes.indexOf(mode) === -1) {
    dispatchLog.push({ agent: name, exclusion: 'mode', note: null, reduced_requested_coverage: false });
    return;
  }

  if (row.gate === 'PRECONDITION') {
    if (name !== 'codex-code-reviewer') {
      ungated.push(name);
      dispatchable.push(name);
      log('The ' + name + ' agent is gated on a precondition that this dispatcher does not know how to check, so it was included on this diff.');
      return;
    }
    if (args.codex_requested !== true) {
      dispatchLog.push({ agent: name, exclusion: 'precondition', note: CODEX_NOT_REQUESTED_NOTE, reduced_requested_coverage: false });
      return;
    }
    if (args.codex_on_path !== true) {
      dispatchLog.push({ agent: name, exclusion: 'precondition', note: CODEX_NOT_ON_PATH_NOTE, reduced_requested_coverage: true });
      return;
    }
    if (args.codex_diff_within_limit !== true) {
      const note = CODEX_DIFF_TOO_LARGE_PREFIX + lineCount(ctx.diff) + CODEX_DIFF_TOO_LARGE_SUFFIX;
      dispatchLog.push({ agent: name, exclusion: 'precondition', note: note, reduced_requested_coverage: true });
      return;
    }
    dispatchable.push(name);
    return;
  }

  if (row.gate === 'UNCONDITIONAL') {
    dispatchable.push(name);
    return;
  }

  if (gateSatisfied(row.gate, presentClasses)) {
    dispatchable.push(name);
    return;
  }

  const skipNote = has(FILE_TYPE_SKIP_NOTES, name)
    ? FILE_TYPE_SKIP_NOTES[name]
    : 'Skipping ' + name + ': the diff contains no ' + row.gate + ' files.';
  dispatchLog.push({ agent: name, exclusion: 'file-type', note: skipNote, reduced_requested_coverage: false });
});

if (dispatchable.length === 0) {
  log('No review agent qualified for this diff, so the deterministic path produced nothing to synthesize.');
  return {
    ok: false,
    reason: 'no-qualifying-agents',
    mode: mode,
    dispatched: [],
    reports: [],
    dispatch_log: dispatchLog,
    ungated: ungated,
    refuted: [],
    risk_signals: args.risk_signals,
  };
}

log('Dispatching ' + dispatchable.length + ' review agent(s); ' + dispatchLog.length + ' did not qualify for this diff.');

// ---------------------------------------------------------------------------
// Fan-out and refutation
// ---------------------------------------------------------------------------

function dispatchStage(name) {
  return agent(buildAgentPrompt(name, ctx), {
    agentType: 'quiver:' + name,
    schema: AGENT_FINDINGS_SCHEMA,
    label: 'review:' + name,
    phase: 'Dispatch',
  });
}

// Fast mode returns its input unchanged. Deep mode puts each finding in front of
// REFUTER_COUNT independent skeptics and keeps it only when fewer than a majority refute it.
// This runs as the pipeline's second stage rather than after a barrier, so each agent's
// findings enter verification as that agent lands instead of waiting on the slowest reviewer.
function verifyStage(result, name) {
  if (ctx.mode !== 'deep') {
    return result;
  }
  if (result === null || result === undefined) {
    return result;
  }

  const findings = Array.isArray(result.findings) ? result.findings : [];
  if (findings.length === 0) {
    return result;
  }

  return parallel(
    findings.map((finding) => () =>
      parallel(
        REFUTER_PASSES.map((pass) => () =>
          agent(buildRefutePrompt(name, finding, pass, ctx), {
            schema: REFUTATION_SCHEMA,
            label: 'refute:' + name + ':pass-' + pass,
            phase: 'Verify',
          })
        )
      ).then((votes) => {
        // Every vote in here belongs to this one finding, so a vote that came back empty can
        // be dropped without disturbing any pairing. A skeptic that returned nothing is not
        // a skeptic that refuted: it is counted as neither.
        const cast = votes.filter(Boolean);
        const refuteCount = cast.filter((vote) => vote.refuted === true).length;
        return { refute_count: refuteCount, survives: refuteCount < REFUTATION_MAJORITY };
      })
    )
  ).then((judged) => {
    const kept = [];
    const dropped = [];
    // Rulings are paired to findings positionally, and the empties are handled in place
    // rather than filtered out first: dropping a null ruling before the pairing would shift
    // every later finding onto the wrong verdict.
    findings.forEach((finding, position) => {
      const ruling = judged[position];
      if (!ruling) {
        // No ruling came back for this finding. Keep it -- a finding lost to a failed check
        // is not a refuted finding, and silently discarding it is the one outcome the
        // quorum must never produce.
        kept.push(finding);
        log('Kept a ' + name + ' finding that produced no ruling: ' + finding.location + ' -- ' + finding.title + '.');
        return;
      }
      if (ruling.survives) {
        kept.push(finding);
        return;
      }
      dropped.push({
        agent: name,
        severity: finding.severity,
        title: finding.title,
        location: finding.location,
        refute_count: ruling.refute_count,
        refuter_count: REFUTER_COUNT,
      });
      log(
        'Dropped a ' + name + ' finding after independent checks disagreed with it: ' +
        finding.location + ' -- ' + finding.title +
        ' (refuted by ' + ruling.refute_count + ' of ' + REFUTER_COUNT + ').'
      );
    });
    return { summary: result.summary, verdict: result.verdict, findings: kept, refuted: dropped };
  });
}

// Declared here rather than inside verifyStage so the phase exists as a boundary in the run
// even though every agent() call above carries an explicit phase of its own -- the explicit
// option is what groups the progress display, which is why setting the global phase from
// inside a pipeline stage would be a race with no benefit.
if (ctx.mode === 'deep') {
  phase('Verify');
}

const settled = await pipeline(dispatchable, dispatchStage, verifyStage);

// Pair every result to its agent name POSITIONALLY, and only then drop the empties. A null
// removed before the pairing shifts every element after it by one and files one agent's
// findings under another agent's name -- a report that is fully populated, looks correct,
// and is wrong.
const paired = dispatchable.map((name, position) => ({ agent: name, result: settled[position] }));
const landed = paired.filter((entry) => Boolean(entry.result));

const reports = [];
const refuted = [];
landed.forEach((entry) => {
  const result = entry.result;
  const kept = Array.isArray(result.findings) ? result.findings.length : 0;
  const dropped = Array.isArray(result.refuted) ? result.refuted : [];
  dropped.forEach((item) => refuted.push(item));
  reports.push({
    agent: entry.agent,
    report: renderReport(entry.agent, result),
    kept: kept,
    refuted: dropped.length,
  });
});

const lost = paired.length - landed.length;
if (lost > 0) {
  log(lost + ' review agent(s) returned nothing and are absent from the synthesized report.');
}

return {
  ok: reports.length > 0,
  mode: mode,
  dispatched: dispatchable,
  reports: reports,
  dispatch_log: dispatchLog,
  ungated: ungated,
  refuted: refuted,
  risk_signals: args.risk_signals,
};

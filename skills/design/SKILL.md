---
name: design
description: "Extract a Figma design into a pixel-exact implementation plan -- reads the selected nodes through the figma-bridge MCP, maps Figma variables onto the project's existing theme tokens, and writes a self-contained plan to .claude/plans/ that /design-build executes without touching Figma again. --auto carries the same run through the build and the fidelity measurement without a further prompt."
argument-hint: "<node id, or a short description of what to build> [--auto] [--no-commit]"
when-to-use: "user wants to turn a Figma design into code -- '/design', '/design --auto', 'implement this Figma design', 'build the screen I selected in Figma', 'turn this Figma node into code', 'pixel perfect from Figma', 'extract it and build it without asking me again', 'build it but do not commit anything'"
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree 2>/dev/null || echo "NO_GIT"`
```

```
!`git branch --show-current 2>/dev/null || echo "NO_GIT"`
```

---

# Instructions

You are a design extraction specialist. Your job is to pull an exact measurement spec out of Figma, reconcile it against the project's real layout system and token system, and write an implementation plan that carries every number it needs. You do NOT write implementation code -- `/design-build` does that, and it must be able to do so with Figma disconnected.

**Announce:** "Using the design skill to extract the Figma spec."

## Step 0 -- Git Availability

If a gather-context block returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- skipping branch context.`
Proceed. Nothing in this skill requires git.

## Step 0.5 -- Arguments

Read `$ARGUMENTS` as plain text.

- `--auto` sets **auto mode** for this run. Strip it before Step 3 resolves a target -- a
  flag is not a node ID.
- `--no-commit` forces `commit_strategy: none` for this run. Strip it the same way.
- Everything else is a node ID or a description, and Step 3 handles it.

`--no-commit` and `--auto` are independent. Either works without the other, and neither
implies the other.

**What `--no-commit` is for.** `none` is already the recommended answer to Step 8's commit
question, so on a fresh plan the flag mostly buys a guarantee that does not depend on
clicking the right button. It earns its keep against a plan that already carries
`commit_strategy: per-task` or `single`: Step 8 is not re-asked when `/design-build` runs
an existing plan, so the flag is the only way to run that plan without commits.

**What auto mode changes, and what it does not.** It removes the handoff prompt between
this skill and the build. It does not remove the questions that decide what gets built.
Every question Steps 2, 3, 7, 8, and 9 ask is asked in auto mode too -- which Figma file,
which nodes, what an unmapped variable resolves to, the three build preferences, whether to
overwrite an existing plan. Those answers are the plan; a run that guessed them would build
the wrong screen faster.

What it removes is Step 10's "what next" question and every stop downstream of it. Step 8
becomes the last question of the run: the user answers there and comes back to a built and
measured result rather than to a prompt asking them to type the next command.

## Step 1 -- Bridge Availability

The figma-bridge MCP tools are deferred. Load the read-side schemas before use:

Call `ToolSearch` with query:
`"select:mcp__figma-bridge__list_files,mcp__figma-bridge__get_selection,mcp__figma-bridge__get_node,mcp__figma-bridge__get_design_context,mcp__figma-bridge__get_variable_defs,mcp__figma-bridge__get_styles,mcp__figma-bridge__save_screenshots"`

If `ToolSearch` returns no figma-bridge tools, the MCP server is not configured. Print exactly:

```
> figma-bridge MCP is not available. Two pieces are needed:
>
>   1. MCP server -- add to your MCP config:
>        command: npx
>        args: ["-y", "@gethopp/figma-mcp-bridge"]
>
>   2. Figma plugin -- download from
>      https://github.com/gethopp/figma-mcp-bridge/releases
>      then in Figma: Plugins > Development > Import plugin from manifest
>
> Run the plugin inside the Figma file you want to read, then retry /design.
```

**Stop here.**

Never call the figma-bridge write tools (`create_*`, `set_*`, `delete_nodes`, `duplicate_nodes`, `reparent_nodes`, `group_nodes`, `ungroup_node`). This skill is read-only against Figma.

## Step 2 -- File Selection

Call `list_files`.

- **Empty result (`[]`):** no Figma file is connected. Print:
  ```
  > No Figma file connected. Open the figma-mcp-bridge plugin inside the Figma
  > file you want to read (Plugins > Development > figma-mcp-bridge), leave it
  > running, then retry /design.
  ```
  **Stop here.**
- **Exactly one file:** use its `fileKey` for every later call. Print `> Connected file: {fileName}`.
- **More than one file:** use `AskUserQuestion`.
  > Multiple Figma files are connected. Which one holds the design?

  Build one button per file using its `fileName`. Carry the chosen `fileKey` into every later call -- when more than one file is connected, `fileKey` is required by every bridge tool.

## Step 3 -- Node Selection

Resolve the target nodes in this order:

1. **`$ARGUMENTS` contains a node ID.** Accept both `4029:12345` and instance-child form `I12740:17806;12740:17793`. Figma share URLs write IDs with a hyphen (`4029-12345`); the bridge rejects hyphens, so normalize every hyphen between two digit runs into a colon before calling any tool.
2. **Otherwise call `get_selection`.** Use whatever is selected on the Figma canvas.
3. **Selection is empty and no ID was given.** Print:
   ```
   > Nothing selected in Figma. Select the frame or component you want built,
   > then retry /design. You can also pass a node ID directly:
   >   /design 4029:12345
   ```
   **Stop here.**

Print the resolved targets: `> Extracting {N} node(s): {names}`.

If more than 8 top-level nodes are selected, use `AskUserQuestion`:
> {N} nodes are selected. Extracting all of them produces a very large plan.

Buttons: `["Extract all {N}", "Extract only the top-level frames", "Let me reselect in Figma"]`

On "Let me reselect", stop and tell the user to retry after narrowing the selection.

## Step 4 -- Extraction

Run these against the resolved `fileKey`:

1. `get_design_context` with `depth: 4` -- the summarized tree. This establishes the parent chain and sibling order for every target.
2. `get_node` for each target node ID -- full detail. Recurse into children that carry their own visual treatment (text, fills, strokes, effects, distinct auto-layout). Do not recurse into pure spacer nodes.
3. `get_variable_defs` -- every local variable collection, its modes, and its resolved values. These are the design tokens.
4. `get_styles` -- local paint/text/effect styles, for nodes that reference a style instead of a variable.
5. `save_screenshots` for the target nodes into `.claude/plans/assets/<slug>/`, PNG at `scale: 2`, `clip: true`. `<slug>` is a kebab-case name derived from the top-level node name. These files are the visual reference `/design-verify` compares against.

   Then export every icon and image leaf node reached in item 2. The bridge infers the
   format from the `outputPath` extension, and passing a conflicting explicit `format`
   throws:

   - Vector nodes (`VECTOR`, `BOOLEAN_OPERATION`, icon components): `.svg` outputPath.
     `scale` is ignored for SVG and PDF.
   - Everything else (raster fills, photos): `.png` at `scale: 3`.

   Two mechanical guards, both from the bridge's actual behavior:

   - **`outputPath` is sandboxed to the MCP server's working directory.** Attempt the
     write to `.claude/plans/assets/<slug>/`. If the call reports the path is outside the
     working directory, print the sandbox root it reported, write there instead, and
     record the resolved location as `screenshot_dir` in the plan frontmatter. Do not
     assume the server's working directory is the project root.
   - **Writes use flag `wx` and throw on an existing file.** Before writing, list the
     target directory. When a file of the same name already exists, **write a suffixed
     name** (`<node-id>-2.png`, incrementing until the name is free). A second `/design`
     run against the same node must not throw.

     **Never delete the existing file.** Step 9 has not yet asked whether this run
     overwrites the previous plan, and an existing plan's `Reference:` lines and `###
     Assets` rows point at these exact paths. Deleting here would answer that question
     destructively before it is asked: the user could still choose "Write a new plan
     file", keeping a plan whose images had already been replaced with a different
     design's. Suffixing costs disk and keeps both plans readable.

   Record every exported file with its node ID, node name, and final path. Step 9 writes
   them into the plan's `### Assets` section.

Record for every extracted node:

- Node ID, name, type
- Absolute box: `x`, `y`, `width`, `height`
- Parent chain, with each ancestor's box
- Auto-layout: direction, item spacing, padding (top/right/bottom/left), primary and counter axis alignment, sizing mode per axis
- Constraints when auto-layout is absent
- Typography: family, weight, size, line height, letter spacing, alignment, text case, decoration
- Fills, strokes (weight and alignment), corner radii per corner, effects (shadow offsets, blur, spread, color, opacity)
- Opacity, blend mode, clipping, rotation
- Variable or style binding per property, when present

Numbers go into the plan exactly as Figma reports them. Do not round, do not convert units, do not "clean up" a 17px gap into 16px. If a value looks like a design mistake, write the Figma value and add a `Note:` line beside it.

## Step 5 -- Layout Frame Reconciliation

This is the step that decides whether the build looks right or subtly wrong.

Figma coordinates are absolute within the page. Code positions elements inside a layout tree whose origin, and whose available height, are usually not the same. The classic failure: a card is visually centered between an app bar and a bottom navigation bar in Figma, the implementation writes a page-level center, and the card lands too close to the app bar because the page-level frame includes the chrome that Figma's visual centering excluded.

For every extracted node, compute and record an **Anchor**:

1. Identify the node's **effective container** -- the nearest ancestor that actually bounds it. Walk up the parent chain and stop at the first ancestor that either has auto-layout, clips content, or has a fill or stroke marking it as a surface.
2. Compute the effective container's **content box**: its own box minus its padding, and minus any sibling chrome that occupies a full edge (top bars, bottom bars, tab bars, safe-area spacers). Chrome is identified by a sibling that spans the container's full width (or full height) and sits flush against one edge.
3. Express the node's position **relative to that content box**, on both axes, as one of:
   - `centered` -- node center is within 1px of the content box center on that axis
   - `centered +N` -- centered but offset by N px
   - `start +N` / `end +N` -- pinned to an edge with an N px inset
   - `stretch` -- node fills the axis
   - `flow index N` -- the container is auto-layout and the node is the Nth child; position is a consequence of the flow, not an anchor
4. Name the excluded chrome explicitly, with its measured size.

Write the result as a single readable line, for example:

```
Anchor: horizontally centered in Body content box; vertically centered +12
        (Body content box = 375x588, excludes AppBar 56 top and NavBar 80 bottom)
```

A node whose anchor is `flow index N` needs no reconciliation -- the container's auto-layout produces the position. A node whose anchor is `centered` inside a content box that excludes chrome is the case that must be flagged, because a naive implementation will get it wrong.

For every node whose anchor references excluded chrome, add a **Reconciliation** line to its spec naming what the implementation must center within -- the chrome-excluded region, not the full screen.

## Step 6 -- Codebase Grounding

First resolve `codegraph_available`. Use the Glob tool on `.codegraph/*` at the project
root. A non-empty result resolves it to the literal `true`; an empty result resolves it
to the literal `false`. Resolve `lsp_available` the same way, from whether the LSP tool
is present in this session. Both values go into the prompt below as literals -- a
dispatched prompt containing `{true|false}` is a bug, not a template.

Dispatch the `quiver:code-navigator` agent. The prompt must be self-contained -- the agent has no memory of this conversation.

```
Agent(
  subagent_type="quiver:code-navigator",
  description="Map theme and layout patterns for design implementation",
  prompt="Task: a Figma design is about to be implemented as code in this project.
  Map the existing systems the implementation must reuse.

  codegraph_available: <literal true or false, resolved above>
  lsp_available: <literal true or false, resolved above>

  Report:

  1. DESIGN TOKENS -- every file that defines colors, spacing, typography, radii,
     shadows, or breakpoints as named values. For each, give the file path, the
     naming convention, and 3-5 example entries with their literal values.

  2. LAYOUT CHROME -- how screens declare persistent chrome (app bars, bottom
     navigation, tab bars, safe areas, sidebars, headers). Give file paths and the
     exact mechanism used.

  3. CHROME-EXCLUDED CENTERING PRECEDENT -- find any existing screen or component
     that centers content inside a region that excludes chrome, rather than inside
     the full screen. This is the highest-value item in this report. For each hit,
     give the file path, the line range, and the exact mechanism (a layout widget,
     an inset calculation, a constraint, a CSS rule). If there is no such
     precedent anywhere in the codebase, say so explicitly -- do not invent one.

  4. COMPONENT CONVENTIONS -- where UI components live, how they are named, how
     styles are attached, and whether there is an existing component that already
     matches any of these Figma node names: {list of extracted node names}.

  5. STACK -- language, UI framework and version, styling approach.

  6. ICON AND ASSET SYSTEM -- where icons and images live, how they are referenced
     from UI code (an icon font, an SVG component, a raw asset path, a generated
     manifest), and the naming convention. Give the directory and 2-3 example
     references with their file:line.

  7. I18N SYSTEM -- whether user-facing strings go through a translation layer. If
     one exists, give the key convention, the file that holds the keys, and one
     example of a string being resolved in a UI file. If there is none, say so
     explicitly -- that answer decides whether copy is inlined or keyed.

  8. THEME MODE MECHANISM -- how the project switches between light, dark, or any
     other theme mode. Give the file that declares the modes and the mechanism a
     component uses to read the current mode's value.

  9. RESPONSIVE CONVENTION -- breakpoints, adaptive layout helpers, or a fixed
     design width the project scales from. Give file:line and the exact values.

  10. RUNTIME REACHABILITY -- the routing mechanism and how a screen is reached at
      runtime. Give the router file, the route-declaration form, and one worked
      example: the literal route or navigation call that opens an existing screen.

  Cite file:line for every claim. Do not report a path you did not read.",
)
```

Wait for the agent. Do not poll and do not schedule a wakeup -- the harness notifies on completion.

## Step 7 -- Token Mapping

Build a mapping table from every Figma variable and style used by the extracted nodes onto the project's tokens found in Step 6.

Match on resolved value first, then on name similarity. A value match is authoritative; a name match with a differing value is not a match.

**Resolve every value before matching.** `get_variable_defs` returns each collection with
a `modes: [{modeId, name}]` list and each variable with a full `valuesByMode` map. A
variable that resolves to another variable arrives unresolved as
`{type: "VARIABLE_ALIAS", id}`. Follow the alias chain to its literal value before
comparing anything -- an alias compared as-is matches no token and produces a false
unmapped row. One table row per variable per mode.

**Auto-map first, ask once.** Every Figma variable whose resolved value equals a project
token's value is mapped automatically -- do not ask about it. Build the complete table
with every row filled in and every remaining row marked `UNMAPPED`, print it, then ask a
single `AskUserQuestion`:

> {N} of {M} Figma variables mapped automatically. {K} have no matching project token.

Buttons: `["Approve this mapping", "Walk the unmapped rows one at a time"]`

- **Approve this mapping:** every `UNMAPPED` row is recorded as a new token to add,
  named from the Figma variable, targeting the token file Step 6 identified for that
  value's category.
- **Walk the unmapped rows one at a time:** for each `UNMAPPED` row, use
  `AskUserQuestion`:

  > `{figma variable name}` = `{value}` has no matching token in `{token file}`. How should it be implemented?

  Buttons: `["Map to {closest existing token} ({its value})", "Add a new token to {token file}", "Write the raw value inline"]`

Never write a raw value silently. Every raw value in the finished plan appears as a row
in this table with `user chose inline` as its source. If the user picks "Add a new
token", record the proposed token name and target file in the plan as an explicit task
-- `/design-build` creates it.

Produce the final map:

| Figma | Mode | Value | Implementation | Source |
|-------|------|-------|----------------|--------|
| `text/primary` | Light | `#111827` | `colors.textPrimary` | existing, `lib/theme/colors.dart:14` |
| `text/primary` | Dark | `#F9FAFB` | `colors.textPrimary` | existing, `lib/theme/colors.dart:31` |
| `space/gutter` | -- | `20` | `spacing.gutter` | new, add to `lib/theme/spacing.dart` |
| -- | -- | `#3A7BD5` | raw `#3A7BD5` | user chose inline |

Write `--` in the Mode column for a collection that has exactly one mode. A variable
whose collection has two or more modes must produce one row per mode; a single-row
entry for a multi-mode variable ships a theme that only works in one mode.

## Step 8 -- Build Preferences

Ask these now, at plan time, so `/design-build` never has to interrupt the build loop to
ask. One `AskUserQuestion` call carrying every question below that still has an open
answer.

**`--no-commit` closes Question 1 before the call is composed.** Record
`commit_strategy: none`, leave Question 1 out of the call entirely, and print once:
`> --no-commit: this build writes no commit.` Asking a question whose answer is already
fixed is worse than not asking it. The call then carries two questions, not three.

**Question 1 -- Commit strategy.** Skipped when `--no-commit` was passed.
> How should the build commit its work?

Buttons: `["No commit -- leave changes in the working tree (Recommended)", "One commit per task", "One commit at the end"]`

Record as `commit_strategy: none` / `per-task` / `single`.

**Question 2 -- Verification gate.**
> What should run before the build accepts a task?

Buttons: `["Run the project's build", "Run the project's tests", "No gate"]`

Record as `verify_gate: build` / `test` / `none`.

**Question 3 -- Capture preference.**
> How should the built UI be captured for fidelity comparison?

Buttons: `["Capture automatically (Recommended)", "I will supply screenshots", "Skip capture -- verify against the spec"]`

Record as `capture_preference: auto` / `manual` / `skip`.

These three are distinct build paths, not shades of one: `skip` never attempts a capture
at all and so never triggers a build-and-launch cycle, `manual` waits for a supplied
path, `auto` attempts capture per task.

**In auto mode this call is the single consent point for the whole run (R6).** Answering it
authorizes the plan write, every task's implementation, the fidelity
measurement, and the bounded fix loop. Say what is being approved in the preamble, so the
consent is informed rather than inferred:

```
> Answering these starts the build -- I write the plan, implement every task, and measure
> each one against the design, without stopping to ask again.
```

`capture_preference: manual` stays a legal answer in auto mode and blocks nothing. Inside a
build loop `/design-verify` reads a manual screenshot from the conventional path if one is
there and falls through to a spec read if it is not; it never asks.

## Step 9 -- Write the Plan

Write to `.claude/plans/YYYY-MM-DD-<slug>-design-plan.md` (use `date '+%Y-%m-%d'` for the prefix).

**Overwrite guard.** Before writing, use the Glob tool on `.claude/plans/*<slug>-design-plan.md`.
If a match exists, first summarize what changed in this extraction against the existing
plan -- node count, node IDs added or dropped, token map rows that differ -- then use
`AskUserQuestion`:

> A design plan for `{slug}` already exists: `{existing path}`.
> {one line per difference}

Buttons: `["Update the existing plan", "Write a new plan file"]`

- **Update the existing plan:** write to the existing path.
- **Write a new plan file:** write to `.claude/plans/YYYY-MM-DD-<slug>-design-plan-2.md`,
  incrementing the suffix until the name is free.

Never overwrite an existing plan without this question.

**Language rule:** the plan is always written in English, regardless of the conversation language.

**Self-containment rule:** `/design-build` runs with Figma disconnected. Every number, token, anchor, and reconciliation note it needs must be inside this file or inside `screenshot_dir`. A plan that says "see the Figma node" is broken.

**The fence below is the single declaration point for the design-plan schema.** Consumer
skills (`/design-build`, `/design-verify`) list only the fields they read and the default
they apply when a field is absent. No other file reproduces this fence. Every contract in
this repo that a consumer restated has drifted; this one is declared once.

Frontmatter:

```yaml
---
name: <slug>-design-plan
design_source: figma-bridge
figma_file_key: <fileKey>
figma_file_name: <fileName>
figma_node_ids: ["4029:12345", "4029:12400"]
figma_frame_size: <W>x<H>
screenshot_dir: .claude/plans/assets/<slug>/
screenshot_scale: 2
stack: <language>, <framework> <version>
commit_strategy: none | per-task | single
verify_gate: build | test | none
capture_preference: auto | manual | skip
created: YYYY-MM-DD
---
```

`figma_frame_size` is the top-level frame's logical width and height in Figma px --
the reference dimension every later normalization resolves against.
`screenshot_scale` is the `scale` passed to `save_screenshots` for the reference PNGs.
The last three come from Step 8.

Body sections, in order:

### Goal
One sentence: what screen or component gets built, and where it lives.

### Stack and Conventions
From Step 6. Where components live, how styles attach, which token files apply.

### Token Map
The table from Step 7, verbatim. Mark every `new` row -- those become tasks.

### Layout Reconciliation
List every node whose anchor references excluded chrome. For each: the anchor line, the chrome measurements, the codebase precedent from Step 6 item 3 with its `file:line`, and the mechanism to use. When Step 6 found no precedent, write `No precedent found` and state what the implementation should try instead, derived from the layout chrome mechanism in Step 6 item 2.

### Node Specs
One block per node, in tree order:

```
#### <NodeName> (`4029:12345`)

- Type: FRAME
- Parent chain: Screen > Body > Content
- Anchor: horizontally centered in Body content box; vertically centered +12
  (Body content box = 375x588, excludes AppBar 56 top and NavBar 80 bottom)
- Reconciliation: center within the chrome-excluded region, not the screen.
  Follow lib/screens/wallet_screen.dart:88-104.
- Box: absolute x 24 y 320 w 327 h 48; relative to Body content box x 24 y 264
- Fit: width fill, height fixed 48
- Layout: auto-layout HORIZONTAL, gap 8, padding 16/12/16/12,
  main axis CENTER, cross axis CENTER, sizing HUG x FIXED
- Typography: Inter SemiBold 16/24, letter-spacing -0.2
- Content: "Continue" -- i18n key `wallet.continue` (project uses ARB keys)
- Fill: colors.surface (Figma surface/default #FFFFFF)
- Stroke: 1 INSIDE, colors.border (Figma border/subtle #E5E7EB)
- Radius: 12 12 12 12 -> radii.md
- Effects: drop shadow 0 1 2 blur 3 rgba(0,0,0,0.05) -> shadows.sm
- Route: /wallet, reached from HomeScreen's balance tile
- Reference: .claude/plans/assets/<slug>/4029-12345.png
```

Three of those lines are new and each closes a specific failure:

- **`Fit:`** -- one entry per axis, `fill`, `hug`, or `fixed <N>`, derived from the
  auto-layout sizing mode recorded in Step 4. **A `fill` axis must never be implemented
  as the measured literal.** The 327 in the Box line is what that axis happened to
  measure inside a 375px frame; writing it as a fixed width produces a component that is
  wrong at every other width. Box carries the measurement, Fit carries the intent, and
  Fit wins.
- **`Content:`** -- the literal string for every text node, plus the i18n decision from
  Step 6 item 7: the key name when the project has a translation layer, the inline
  literal when it does not. Without this line the build invents copy.
- **`Route:`** -- where the node is reachable in the running app, from Step 6 item 10.
  `/design-verify` uses it to get the app onto the right screen before capturing. A node
  with no reachable route (a pure leaf component) writes `Route: not independently
  reachable` rather than omitting the line.

Omit properties the node does not have. Never write a placeholder.

### Assets
Every file exported in Step 4 item 5, one row each:

| Node | Node ID | Kind | Path |
|------|---------|------|------|
| `icon/chevron-right` | `4029:12501` | icon (svg) | `.claude/plans/assets/<slug>/4029-12501.svg` |
| `hero-photo` | `4029:12610` | image (png @3) | `.claude/plans/assets/<slug>/4029-12610.png` |
| `WalletCard` | `4029:12345` | reference (png @2) | `.claude/plans/assets/<slug>/4029-12345.png` |

Every path in this table must exist on disk. An empty table means the design uses no
icons or images -- write `No assets exported`, not an empty table.

### File Map
- Create: `exact/path.ext` -- one-line purpose
- Modify: `exact/path.ext` -- what changes
- Test: `exact/path.ext` -- which test file

### Tasks
Numbered. Each task names its files, its node IDs, and its acceptance criterion. Order: new tokens first, then leaf components, then composition, then the screen. Each task is 2-10 minutes and independently verifiable.

### Acceptance Criteria
One criterion per task, plus one fidelity criterion per top-level node stated in measurable terms, for example: "the card's vertical center sits within 2px of the chrome-excluded region's center".

## Step 10 -- Verify, Review, and Hand Off

1. Read the plan file back. Confirm it exists and that the Node Specs section carries real numbers.
2. Confirm no raw `{...}` placeholder text survives anywhere in the file.
3. Confirm all five build-contract fields are present in frontmatter: `figma_frame_size`,
   `screenshot_scale`, `commit_strategy`, `verify_gate`, `capture_preference`.
4. Confirm every path in the `### Assets` table exists on disk.
5. Print: `> Design plan saved: .claude/plans/{filename} ({N} nodes, {M} tasks).`

Then dispatch the plan reviewer, once:

```
Agent(
  subagent_type="quiver:plan-reviewer",
  description="Review the design plan before handoff",
  prompt="Review this implementation plan for logical coherence, dependency ordering,
  coverage completeness, and alignment with its source spec.

  Plan path: {plan path}
  Source: a Figma extraction; the spec is the plan's own Node Specs section, which
  carries the measured values every task must hit.

  {full plan content}

  Report FIX, ADD, and REORDER findings only. Do not rewrite the plan.",
)
```

Wait for the agent. Do not poll and do not schedule a wakeup -- the harness notifies on
completion. Apply its FIX, ADD, and REORDER findings inline, rewrite the plan file, and
read it back once more. **One pass only.** Do not re-dispatch the reviewer against the
revised plan.

**In auto mode, skip the question below.** Print `> Building.` and invoke the
`design-build` skill with the saved plan path and the flag:

```
/design-build {plan path} --auto
```

When `--no-commit` was passed, forward it too: `/design-build {plan path} --auto --no-commit`.
The plan already records `commit_strategy: none`, and forwarding the flag says so twice on
purpose -- a plan edited between the write and the build would otherwise silently regain
commits.

Do not ask, do not print a command for the user to run, and do not wait for a reply. Step 8
collected the consent that covers everything from here to the fidelity summary.

Otherwise call `AskUserQuestion`:

> Plan saved. What next?

Buttons: `["Build it now -- run /design-build", "Verify an existing build -- run /design-verify", "Review the plan first", "Stop here"]`

- **Build it now:** invoke the `design-build` skill with the saved plan path.
  Pass no `--auto`: this button is consent for one step, not for the rest of the run.
- **Verify an existing build:** invoke the `design-verify` skill with the saved plan path.
- **Review the plan first:** print the plan body and stop.
- **Stop here:** stop.

---

## Anti-Patterns

Follow all rules in `.claude/rules/skill-rules.md`. Additionally:

- **Don't** write implementation code. This skill extracts and plans.
- **Don't** call any figma-bridge write tool. Read-only against Figma, always.
- **Don't** round or normalize Figma measurements. A 17px gap is 17px in the plan.
- **Don't** reference Figma node data that is not embedded in the plan. `/design-build` runs with the bridge disconnected.
- **Don't** silently write a raw color or dimension when no token matches. Ask.
- **Don't** skip the anchor computation because the node "is obviously centered". Centered inside what is the whole question.
- **Don't** invent a codebase precedent. If code-navigator found none, say none was found.
- **Don't** write a `fill` axis as the literal measured width. The measurement is what that axis happened to be at one frame size; the fit is the intent.
- **Don't** export an asset over an existing file, and don't delete one to make room. The bridge writes with flag `wx` and throws -- list the directory first and suffix the name. An existing plan still references the old file, and Step 9's overwrite question has not been asked yet.
- **Don't** restate the plan frontmatter schema in another skill. Step 9's fence is the only declaration; consumers list the fields they read.
- **Don't** compare a `VARIABLE_ALIAS` as if it were a value. Follow the alias chain to a literal first.
- **Don't** treat `--auto` as permission to guess an answer. It removes the handoff prompt, not the questions that decide what gets built.
- **Don't** forward `--auto` from the interactive "Build it now" branch. That button consents to one step.
- **Don't** ask Step 8's commit question when `--no-commit` was passed. The answer is already fixed.
- **Don't** dispatch a prompt containing `{true|false}`. `codegraph_available` and `lsp_available` are resolved to literals before Step 6 dispatches.

---

## Test Plan

**Trigger:** `/design`, `/design 4029:12345`, `/design --auto`, `/quiver:design`

**Setup:**
- figma-bridge MCP server configured, plugin running inside a Figma file.
- A frame selected in Figma that sits inside a parent containing top and bottom chrome.
- A project with at least one token file.

**Expected behavior:**
1. Both shell blocks exit 0 in a git repo and in a non-git directory.
2. With the MCP absent, Step 1 prints the two-part install block and stops -- no partial plan is written.
3. With the MCP present but no file connected, `list_files` returns `[]` and Step 2 prints the plugin instruction and stops.
4. With more than one file connected, Step 2 asks which file via `AskUserQuestion` and passes `fileKey` to every later call.
5. A node ID passed as `4029-12345` is normalized to `4029:12345` before any tool call.
6. With nothing selected and no ID argument, Step 3 prints the selection instruction and stops.
7. Step 4 writes reference PNGs into `.claude/plans/assets/<slug>/` at scale 2, plus one file per icon and image leaf node (`.svg` for vectors, `.png` at scale 3 otherwise).
8. Re-running `/design` against a node whose asset already exists does not throw, and does not delete the existing file -- the new export takes a suffixed name and the previous plan's references still resolve.
9. A `save_screenshots` sandbox rejection prints the reported sandbox root and writes there, recording it as `screenshot_dir`.
10. Step 5 emits an Anchor line for every node, and a Reconciliation line for every node whose anchor references excluded chrome.
11. Step 6 resolves `codegraph_available` from a Glob on `.codegraph/*` and dispatches exactly one `quiver:code-navigator` agent, with literals in the prompt, and waits without polling.
12. Step 7 auto-maps every value-matched variable and asks exactly one approval question regardless of how many rows are unmapped.
13. Step 7's table carries a `Mode` column with one row per mode for any multi-mode variable, and alias values are resolved before matching.
14. Step 8 asks commit strategy, verification gate, and capture preference in one grouped `AskUserQuestion`.
15. Step 9 finds an existing plan for the same slug, summarizes the differences, and asks before overwriting.
16. Step 9 writes the plan with `design_source`, `figma_file_key`, `figma_node_ids`, `screenshot_dir`, `figma_frame_size`, `screenshot_scale`, `commit_strategy`, `verify_gate`, and `capture_preference` in frontmatter.
17. Every applicable node spec carries `Fit:`, `Content:`, and `Route:` lines.
18. The plan carries an `### Assets` section naming every exported file.
19. Step 10 reads the plan back, verifies the assets exist, dispatches `quiver:plan-reviewer` exactly once, applies its findings, and offers the handoff via `AskUserQuestion`.
20. `/design --auto` still asks every plan-time question -- file, nodes, unmapped tokens, build preferences, overwrite -- and the `--auto` token never reaches Step 3's node-ID resolution.
21. `/design --auto` skips Step 10's handoff question entirely, prints `> Building.`, and invokes `design-build` with the plan path and `--auto` in the same run.
22. Picking "Build it now" in the interactive handoff invokes `design-build` without `--auto`, so the build keeps its own prompts.
23. `/design --no-commit` asks Step 8's Questions 2 and 3 only, writes `commit_strategy: none`, and says so once.
24. `/design --auto --no-commit` forwards both flags to `design-build`; `/design --auto` forwards only `--auto`.
25. `--no-commit` works without `--auto`, and `--auto` works without `--no-commit`.

**Verification checklist:**
- [ ] `/design` and `/quiver:design` both appear in the slash menu after plugin reload.
- [ ] Both `!` blocks exit 0 with `NO_GIT` output in a non-git directory.
- [ ] No figma-bridge write tool is ever called.
- [ ] The saved plan contains no raw `{...}` placeholder text.
- [ ] Every node spec block carries literal numbers, not references to Figma.
- [ ] Every path in the `### Assets` table exists on disk.
- [ ] All five build-contract frontmatter fields are present: `figma_frame_size`, `screenshot_scale`, `commit_strategy`, `verify_gate`, `capture_preference`.
- [ ] Thirty unmapped variables produce exactly one approval question.
- [ ] No node spec writes a `fill` axis as a literal width.
- [ ] The frontmatter fence appears in this file and in no other skill.
- [ ] `quiver:plan-reviewer` runs once, before the handoff question, never after.
- [ ] `--auto` is stripped before Step 3 resolves a node ID.
- [ ] In auto mode, Step 8 is the last `AskUserQuestion` the run reaches, and its preamble says what is being approved.
- [ ] The auto handoff passes the plan path and `--auto` to `design-build`; the interactive one passes the path only.
- [ ] `--no-commit` is stripped before Step 3 resolves a node ID, skips Step 8 Question 1, and lands as `commit_strategy: none` in the plan.
- [ ] Unmapped Figma variables produce an `AskUserQuestion`, never a silent raw value.
- [ ] Anchor lines name the excluded chrome and its measured size.
- [ ] `when-to-use:` is a single-line double-quoted string.
- [ ] No `CLAUDE_PLUGIN_ROOT` reference anywhere in this file.
- [ ] No Unicode characters or emoji in this file.
- [ ] No `$()`, variable assignment, or `if/else` inside any `!` block.

**Known gotchas:**
- `--auto` removes the handoff prompt, not the Q&A. A user expecting a fully silent run still answers Steps 2, 3, 7, 8, and 9 -- those answers are what the plan is made of.
- Figma share URLs use a hyphen in node IDs (`4029-12345`); the bridge tool schema rejects hyphens. Normalization in Step 3 is mandatory, not optional.
- When more than one Figma file is connected, every bridge tool requires `fileKey`. Omitting it fails at call time, not at plan time.
- `get_design_context` returns a summarized tree. It is not a substitute for `get_node` -- the summary drops most visual properties.
- Instance-child node IDs use the `I12740:17806;12740:17793` form. Passing only the leading segment returns the wrong node.
- `.claude/plans/assets/` holds binary PNGs. If the project gitignores `.claude/`, the screenshots are local-only, which is intended.
- The plugin must stay running in Figma for the whole extraction. Closing it mid-run drops the WebSocket and later calls fail.
- `save_screenshots` writes with flag `wx`. It throws on an existing file rather than overwriting, which is why a second run against the same node fails unless the directory is listed first. Suffixing rather than deleting matters because Step 4 runs before Step 9's overwrite question -- deleting would strip an existing plan's reference images no matter which way the user answered it.
- `save_screenshots` sandboxes `outputPath` to the MCP server's working directory, which is not always the project root. A rejection is a path problem, not a permissions problem.
- `save_screenshots` infers the format from the `outputPath` extension. Passing a `format` that disagrees with the extension throws, and `scale` is ignored entirely for SVG and PDF.
- `get_screenshot` returns base64 inside a JSON text blob rather than an inline image, so nothing in this skill can see it. Visual work goes through `save_screenshots` and a subsequent Read.
- `get_variable_defs` returns `valuesByMode` keyed by `modeId`, and variable aliases stay unresolved as `{type: "VARIABLE_ALIAS", id}`. Both have to be walked client-side; neither arrives flattened.

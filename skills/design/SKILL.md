---
name: design
description: "Extract a Figma design into a pixel-exact implementation plan -- reads the selected nodes through the figma-bridge MCP, maps Figma variables onto the project's existing theme tokens, and writes a self-contained plan to .claude/plans/ that /design-build executes without touching Figma again."
argument-hint: "<node id, or a short description of what to build>"
when-to-use: "user wants to turn a Figma design into code -- '/design', 'implement this Figma design', 'build the screen I selected in Figma', 'turn this Figma node into code', 'pixel perfect from Figma'"
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
5. `save_screenshots` for the target nodes into `.claude/plans/assets/<slug>/`, PNG at `scale: 2`, `clip: true`. `<slug>` is a kebab-case name derived from the top-level node name. These files are the visual reference `/design-build` compares against.

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

Dispatch the `quiver:code-navigator` agent. The prompt must be self-contained -- the agent has no memory of this conversation.

```
Agent(
  subagent_type="quiver:code-navigator",
  description="Map theme and layout patterns for design implementation",
  prompt="Task: a Figma design is about to be implemented as code in this project.
  Map the existing systems the implementation must reuse.

  codegraph_available: {true|false -- set true if .codegraph/ exists at project root}
  lsp_available: {true|false}

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

  Cite file:line for every claim. Do not report a path you did not read.",
)
```

Wait for the agent. Do not poll and do not schedule a wakeup -- the harness notifies on completion.

## Step 7 -- Token Mapping

Build a mapping table from every Figma variable and style used by the extracted nodes onto the project's tokens found in Step 6.

Match on resolved value first, then on name similarity. A value match is authoritative; a name match with a differing value is not a match.

For every Figma variable that has **no** project token with the same value, use `AskUserQuestion`. Batch up to 4 unmapped variables per call.

> `{figma variable name}` = `{value}` has no matching token in `{token file}`. How should it be implemented?

Buttons per variable: `["Map to {closest existing token} ({its value})", "Add a new token to {token file}", "Write the raw value inline"]`

Never write a raw value silently. If the user picks "Add a new token", record the proposed token name and target file in the plan as an explicit task -- `/design-build` creates it.

Produce the final map:

| Figma | Value | Implementation | Source |
|-------|-------|----------------|--------|
| `text/primary` | `#111827` | `colors.textPrimary` | existing, `lib/theme/colors.dart:14` |
| `space/gutter` | `20` | `spacing.gutter` | new, add to `lib/theme/spacing.dart` |
| -- | `#3A7BD5` | raw `#3A7BD5` | user chose inline |

## Step 8 -- Write the Plan

Write to `.claude/plans/YYYY-MM-DD-<slug>-design-plan.md` (use `date '+%Y-%m-%d'` for the prefix).

**Language rule:** the plan is always written in English, regardless of the conversation language.

**Self-containment rule:** `/design-build` runs with Figma disconnected. Every number, token, anchor, and reconciliation note it needs must be inside this file or inside `screenshot_dir`. A plan that says "see the Figma node" is broken.

Frontmatter:

```yaml
---
name: <slug>-design-plan
design_source: figma-bridge
figma_file_key: <fileKey>
figma_file_name: <fileName>
figma_node_ids: ["4029:12345", "4029:12400"]
screenshot_dir: .claude/plans/assets/<slug>/
stack: <language>, <framework> <version>
created: YYYY-MM-DD
---
```

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
- Layout: auto-layout HORIZONTAL, gap 8, padding 16/12/16/12,
  main axis CENTER, cross axis CENTER, sizing HUG x FIXED
- Typography: Inter SemiBold 16/24, letter-spacing -0.2
- Fill: colors.surface (Figma surface/default #FFFFFF)
- Stroke: 1 INSIDE, colors.border (Figma border/subtle #E5E7EB)
- Radius: 12 12 12 12 -> radii.md
- Effects: drop shadow 0 1 2 blur 3 rgba(0,0,0,0.05) -> shadows.sm
- Reference: .claude/plans/assets/<slug>/4029-12345.png
```

Omit properties the node does not have. Never write a placeholder.

### File Map
- Create: `exact/path.ext` -- one-line purpose
- Modify: `exact/path.ext` -- what changes
- Test: `exact/path.ext` -- which test file

### Tasks
Numbered. Each task names its files, its node IDs, and its acceptance criterion. Order: new tokens first, then leaf components, then composition, then the screen. Each task is 2-10 minutes and independently verifiable.

### Acceptance Criteria
One criterion per task, plus one fidelity criterion per top-level node stated in measurable terms, for example: "the card's vertical center sits within 2px of the chrome-excluded region's center".

## Step 9 -- Verify and Hand Off

1. Read the plan file back. Confirm it exists and that the Node Specs section carries real numbers.
2. Confirm no raw `{...}` placeholder text survives anywhere in the file.
3. Confirm every screenshot referenced under `screenshot_dir` exists on disk.
4. Print: `> Design plan saved: .claude/plans/{filename} ({N} nodes, {M} tasks).`

Then call `AskUserQuestion`:

> Plan saved. What next?

Buttons: `["Build it now -- run /design-build", "Review the plan first", "Stop here"]`

- **Build it now:** invoke the `design-build` skill with the saved plan path.
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

---

## Test Plan

**Trigger:** `/design`, `/design 4029:12345`, `/quiver:design`

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
7. Step 4 writes PNGs into `.claude/plans/assets/<slug>/` at scale 2.
8. Step 5 emits an Anchor line for every node, and a Reconciliation line for every node whose anchor references excluded chrome.
9. Step 6 dispatches exactly one `quiver:code-navigator` agent and waits without polling.
10. Step 7 asks before writing any raw value, batching up to 4 unmapped variables per `AskUserQuestion` call.
11. Step 8 writes the plan with `design_source`, `figma_file_key`, `figma_node_ids`, and `screenshot_dir` in frontmatter.
12. Step 9 reads the plan back, verifies the screenshots exist, and offers the handoff via `AskUserQuestion`.

**Verification checklist:**
- [ ] `/design` and `/quiver:design` both appear in the slash menu after plugin reload.
- [ ] Both `!` blocks exit 0 with `NO_GIT` output in a non-git directory.
- [ ] No figma-bridge write tool is ever called.
- [ ] The saved plan contains no raw `{...}` placeholder text.
- [ ] Every node spec block carries literal numbers, not references to Figma.
- [ ] Every screenshot named in the plan exists at that path.
- [ ] Unmapped Figma variables produce an `AskUserQuestion`, never a silent raw value.
- [ ] Anchor lines name the excluded chrome and its measured size.
- [ ] `when-to-use:` is a single-line double-quoted string.
- [ ] No `CLAUDE_PLUGIN_ROOT` reference anywhere in this file.
- [ ] No Unicode characters or emoji in this file.
- [ ] No `$()`, variable assignment, or `if/else` inside any `!` block.

**Known gotchas:**
- Figma share URLs use a hyphen in node IDs (`4029-12345`); the bridge tool schema rejects hyphens. Normalization in Step 3 is mandatory, not optional.
- When more than one Figma file is connected, every bridge tool requires `fileKey`. Omitting it fails at call time, not at plan time.
- `get_design_context` returns a summarized tree. It is not a substitute for `get_node` -- the summary drops most visual properties.
- Instance-child node IDs use the `I12740:17806;12740:17793` form. Passing only the leading segment returns the wrong node.
- `.claude/plans/assets/` holds binary PNGs. If the project gitignores `.claude/`, the screenshots are local-only, which is intended.
- The plugin must stay running in Figma for the whole extraction. Closing it mid-run drops the WebSocket and later calls fail.

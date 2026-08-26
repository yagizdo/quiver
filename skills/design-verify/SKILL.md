---
name: design-verify
description: "Measure a built UI against its design measurement spec -- captures the running app when capture tooling exists, normalizes both images to a common logical width, compares them, and writes a deviation report to disk. Works standalone against any plan carrying a Node Specs section, and never requires a screenshot, an MCP server, or an installed comparison tool."
argument-hint: "<path to a plan with a Node Specs section> [--screenshot <path>] [--nodes <id,id>] [--task <id>] [--mode standalone|build]"
when-to-use: "user wants to check whether built UI matches its design spec -- '/design-verify', 'does this match the design', 'check the pixel accuracy', 'compare the screen to the Figma reference', 'measure the deviations from the spec'"
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

You are a design fidelity inspector. You measure what was built against what was
specified, and you write down the differences. You do not implement fixes and you do not
open Figma. Your output is a deviation report on disk that either a human or
`/design-build` reads.

Three things you never do: demand a screenshot, demand an installed tool, or stop because
one is missing. Every absent capability degrades to a lower-confidence path and the run
continues.

**Announce:** "Using the design-verify skill to measure the build against the spec."

## Phase 0 -- Git Availability

If a gather-context block returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- skipping branch context.`
Proceed. Nothing in this skill requires git.

## Phase 1 -- Arguments and Mode

Parse `$ARGUMENTS`:

| Argument | Meaning | Default |
|----------|---------|---------|
| first bare path ending in `.md` | the plan to verify against | Glob fallback, see Phase 2 |
| `--screenshot <path>` | a capture the user already has | none |
| `--nodes <id,id>` | restrict verification to these node IDs | every node in the plan |
| `--task <id>` | names the report file | the first node ID |
| `--vm-uri <ws-uri>` | the Dart VM service URI a marionette capture attaches to | a registered marionette instance, else the row is skipped |
| `--mode standalone` or `--mode build` | who is running this | `standalone` |

**Mode arrives as an argument. Never detect the caller.** There is no inspection of the
conversation, the transcript, or any other skill's state to decide which mode applies.
`standalone` is the default because a human typing `/design-verify` passes no mode.

The only behavioral difference between the two modes:

- `standalone` may make the one-time offer to supply a screenshot manually (Phase 3).
- `build` never offers it, because that question belongs at plan time, and interrupting a
  build loop to ask it is the interruption the plan-time preference exists to prevent.

Everything else -- capture, normalization, comparison, the report shape -- is identical.

## Phase 2 -- Load the Plan

**Path given.** If `$ARGUMENTS` contains a path ending in `.md`, read that file.

**No path given.** Use the Glob tool on `.claude/plans/*-design-plan.md`. Treat an empty
result as none found.

- One match: read it and print `> Verifying against: {filename}`.
- Several matches: use `AskUserQuestion` with one button per plan, most recent first,
  plus `"Other -- I'll give a path"`.
- No matches: print
  ```
  > No plan found. /design-verify needs a file with a ### Node Specs section -- a plan
  > written by /design, or a hand-written measurement spec in the same shape.
  ```
  **Stop here.**

**Validate on `### Node Specs` and nothing else.** The file is acceptable when it contains
a `### Node Specs` section carrying at least one node block. A hand-written measurement
spec is equivalent input to a Figma extraction, so this skill never requires
`design_source`, `figma_file_key`, or any other Figma-derived field. If the section is
missing, print:

```
> {filename} has no ### Node Specs section, so there is nothing to measure against.
> Run /design to produce one, or pass a file that carries node measurements.
```

**Stop here.**

### Nodes marked reference only are not verified

A node spec carrying `Scope: reference only -- not built by this plan` was extracted for
context, not built. Skip it and record it under the report's `## Notes` with that reason.
Measuring it reports real deviations against code nobody wrote, and in a build loop those
deviations enter a fix cycle that edits working parts of the screen.

An explicit `--nodes` list wins: a node named on the command line is verified whatever its
`Scope:` line says, because naming it is the stronger signal.

### Frontmatter fields this skill reads

The plan schema is declared once, in `skills/design/SKILL.md` Step 9. This skill does not
reproduce that fence. It reads these fields and applies these defaults when a field is
absent:

| Field | Used for | Default when absent |
|-------|----------|---------------------|
| `figma_frame_size` | the reference logical width and height every normalization resolves against | none -- normalization is skipped and the report is marked low confidence |
| `screenshot_scale` | the scale the reference images were exported at | `2` |
| `screenshot_dir` | where reference images and the report live | `.claude/plans/assets/<slug>/`, slug derived from the plan filename |
| `capture_preference` | which capture path Phase 3 takes | `auto` |

A plan written before these fields existed loads cleanly on the defaults. Absence is
expected, not an error.

## Phase 3 -- Resolve the Capture

### Input precedence

None of these is mandatory. Walk them in order and stop at the first that produces an
image:

1. **A supplied screenshot** -- `--screenshot <path>` when the file exists, or a file
   already sitting at this run's conventional capture path,
   `<screenshot_dir>/actual/<task-id>.png`. Both are user-supplied input; neither runs a
   capture command.
2. **An automatic capture** -- the per-target commands below.
3. **A spec-versus-code read** -- no image at all. Read the written code against the node
   spec: every measurement, token, and anchor checked by hand. The report is marked
   `spec-check` and low confidence.

**An explicit `--screenshot` wins over `capture_preference`.** A path the user typed on
the command line is a stronger signal than a preference stored at plan time, so level 1
runs before the preference is consulted, on every value including `skip`. A supplied file
is not a capture attempt, and `skip` only forbids capture attempts.

With no `--screenshot`, `capture_preference` routes into the ladder, and its three values
are three distinct paths:

- `skip` -- go straight to level 3. No capture is attempted, so no build-and-launch cycle
  runs. This is the cheap path for a plan whose UI is not runnable right now.
- `manual` -- level 1 only, including the conventional path. The user drops screenshots at
  `<screenshot_dir>/actual/<task-id>.png` and both modes find them there with no question
  asked -- which is what makes `manual` reachable inside a build loop that may not be
  interrupted. When neither source produces a file, print once:
  ```
  > capture_preference: manual and no screenshot supplied. Drop one at
  > <screenshot_dir>/actual/<task-id>.png and re-run, or continue on the spec read.
  ```
  then fall to level 3 rather than capturing.
- `auto` -- the full ladder.

When mode is `standalone`, level 1 produced no image, and either automatic capture found
no tooling or `capture_preference` is `manual`, make the offer **once** before falling to
level 3, with `AskUserQuestion`:

> No capture tooling resolved. A screenshot would turn this into a measured comparison
> instead of a spec read.

Buttons: `["Verify against the spec by reading the code", "I'll supply a screenshot path"]`

When mode is `build`, skip that question and fall through silently.

### Probe the capture tooling once, before resolving the target

The target order below drops a physical-device row when nothing can photograph that
device, so what is installed has to be known before the target is chosen, not after a
capture fails. Run these probes once per run, with the Bash tool. Skip the block entirely
when `capture_preference` is `skip` -- that plan attempts no capture, so nothing it
reports could change a decision:

| Probe | Answers |
|-------|---------|
| `command -v marionette` | can a Flutter app be captured wherever it runs, physical device included |
| `command -v pymobiledevice3` | can a physical iOS device be captured on a non-Flutter stack |
| `command -v adb` | can an Android device or emulator be captured, and detected at all |
| `magick -version` | will the comparison be measured or structural (Phase 5 re-reads this) |

`command -v` rather than a version flag: the question is whether the binary resolves, and
a wrong flag guess reports a present tool as missing.

Print one line naming everything absent, then continue -- this block decides which rows
are reachable, it never stops the run:

```
> Capture tooling: marionette missing, pymobiledevice3 missing, magick present.
```

### Resolve the target once per run

Resolve the target once, before the first capture, never per node. Detect the project
type from its manifest, then take the first live target in that type's order:

| Manifest at the project root | Project type | Target order |
|------------------------------|--------------|--------------|
| `pubspec.yaml` | Flutter | wired physical device, then wireless physical device, then simulator or emulator |
| `*.xcodeproj`, `*.xcworkspace`, or `Package.swift` | iOS | wired physical device, then wireless physical device, then iOS simulator |
| `build.gradle` or `build.gradle.kts` declaring an Android plugin | Android | wired physical device, then wireless physical device, then Android emulator |
| `package.json` naming `next`, `react`, `vue`, `svelte`, or `vite` | Web | Web |

**A physical device outranks a simulator because it is the only target that renders what
ships** -- real safe-area insets, real fonts, real display scaling. The simulator is the
fallback, not the default.

**A device row is only reachable when a capture path for it resolved** in the tooling
probe above, and which tool that is depends on the stack:

| Physical device | Captured by |
|-----------------|-------------|
| Android | `adb`, the same binary the emulator row uses -- nothing extra to install |
| Flutter, any platform | `marionette`, or the platform's own tool below |
| iOS, non-Flutter | `pymobiledevice3` only |

With none of them present for the stack in hand, the device can still be built to and
launched on, and nothing can photograph it -- so the device rows are dropped and the run
continues at the simulator row. Building on a target that cannot be captured trades a
measured comparison for a spec read, which is the opposite of why the device ranks first.

**Wired before wireless.** Both answer the same probes and both capture through the same
tooling; a wireless capture crosses the network for every frame and drops mid-run more
often. Resolve the transport per platform:

- **iOS:** `xcrun devicectl list devices --json-output <tmp-path>`, then read each
  device's `connectionProperties.transportType` -- `wired` sorts before `localNetwork`.
  The JSON file is devicectl's only supported interface for scripts; its stdout table is
  documented as human-readable output and must not be parsed.
- **Android:** `adb devices -l`. A serial shaped `host:port` is a wireless connection; a
  bare serial is USB.
- **Flutter:** `flutter devices --machine` names the target, then its platform's rule
  above resolves the transport.

Then resolve the tie:

- **One live target:** use it.
- **Several live** -- two attached phones, or a phone and a booted simulator. In
  `standalone` mode ask with `AskUserQuestion`, one button per live target. In `build`
  mode never ask: take the first live target in the order above and name the choice in
  the report's `capture_method`.
- **No manifest matches:** walk the command rows below top to bottom and take the first
  target whose absence probe reports something live.

An Android capture compared against an iOS-frame export produces a deviation on every
row, so the resolved target is recorded in the report rather than left implicit.

### Where captures land

Every capture command writes to `<screenshot_dir>/actual/<task-id>.png`, with `<task-id>`
resolved exactly as Phase 6 resolves it. Create `<screenshot_dir>/actual/` with `mkdir -p`
before the first capture: `adb ... > <path>` fails on a missing parent directory, and the
failure reads as a device problem.

In the commands below, `<path>` is that file.

### The app must be running and fresh

A capture of a stale binary measures the previous build. Resolve the running app once per
run, before the first capture:

- **`standalone`** -- an already-running instance is accepted as it is. This run edited no
  code, so what is on screen is what the plan describes.
- **`build`** -- a running instance is never trusted as fresh. `/design-build` owns one run
  session and refreshes it after each task's implementation. When this skill runs with
  `--mode build` and no refreshed session is on screen, build and launch before capturing.

Build-and-launch is capped at **3 attempts** per run, not per node. Each failed attempt
gets one targeted fix -- read the error, change one thing -- and one retry.

| Target | Build-and-launch command |
|--------|--------------------------|
| Flutter | `flutter run -d <device-id>` -- the same `<device-id>` the target resolution picked, physical device or simulator |
| iOS simulator | `xcodebuild -scheme <scheme> -destination 'platform=iOS Simulator,name=<device>' build`, then `xcrun simctl install booted <app-path>` and `xcrun simctl launch booted <bundle-id>` |
| iOS physical device | `xcodebuild -scheme <scheme> -destination 'id=<udid>' build`, then `xcrun devicectl device install app --device <udid> <app-path>` and `xcrun devicectl device process launch --device <udid> <bundle-id>` |
| Android | `./gradlew installDebug`, then `adb -s <SERIAL> shell am start -n <package>/<activity>` -- `<SERIAL>` is the resolved target, device or emulator |
| Web | the dev server script named in `package.json` -- `dev`, then `start` |
| Any other stack | the run command the project itself documents -- a README quickstart, a `Makefile` target, a package-manager script. When none is discoverable, run no launch at all and continue on the spec read. |

**The launch row and the capture row resolve to the same target.** They are two halves of
one decision made once in the target resolution above, and splitting them is the failure
this rule exists to prevent: launching a simulator build while capturing an attached
phone photographs whatever that phone was already running, and every deviation afterwards
describes a binary this run never wrote.

**A device build that fails on code signing falls back to the simulator once.** Read the
error: a signing, provisioning, or `no eligible devices` failure is a machine-setup
problem no code fix reaches, so retrying it on the device spends the whole budget on the
same wall. Re-resolve to the simulator row, print
`> Device build failed on code signing -- falling back to the simulator.`, and continue.
The fallback costs one attempt, and it happens once per run.

The four named rows are the stacks with a standard command, not the stacks that are
allowed. An unlisted one -- Kotlin/JVM, Go, a Makefile-driven build -- resolves through
the last row and the run continues.
**A stack with no discoverable run command costs zero attempts.** An attempt is a launch
that ran and failed; a launch that was never possible is not one.

**Print the launch result once, naming the command that ran.** `> Launch: {target} -- {command}`,
or `> Launch: failed after 3 attempts -- continuing on the spec read.` The last row resolves its
command out of repository content rather than a fixed binary, and an unattended run reaches no
`AskUserQuestion` -- this line is the only record of what was executed.

**After the third failed attempt, continue without a capture on the level 3 spec read.**
There is no fourth attempt and there is no stop: a launch failure lowers confidence, it
does not end verification. Record `capture_method: none -- launch failed after 3 attempts`
in the report.

Route each attempt on parsed output, never on exit status -- the rule the capture probes
below already follow. `flutter run` stays in the foreground until the app exits, so run it
in the background and read its output; a build error prints `Error:` lines and never
returns an exit status you can wait on.

### Per-target capture commands

| Target | Capture command | Absence probe |
|--------|-----------------|---------------|
| Flutter app on any target, physical device included | `marionette --uri <vm-service-uri> take-screenshots --output <path>` | `command -v marionette` from the probe block, then a URI that resolves through the ladder below |
| iOS simulator | `xcrun simctl io booted screenshot --type=png <path>` | `xcrun simctl list devices booted -j`, parse the JSON for a non-empty booted list |
| Android emulator or device | `adb -s <SERIAL> exec-out screencap -p > <path>` | `adb devices -l`, parse the device lines |
| Physical iOS device | `pymobiledevice3 developer dvt screenshot <path>`, or `pymobiledevice3 developer core-device screen-capture screenshot <path>` on iOS 17+ | `pymobiledevice3 usbmux list`, parse the output for a UDID |
| Flutter without marionette | resolve the run target from `flutter devices --machine`, then use that platform's row above | parse the JSON array's length, never the exit code |
| Web | Playwright MCP `browser_take_screenshot` with `filename`; add `element` and `target` for a clipped capture | `ToolSearch` for `browser_take_screenshot` |

### Resolving the VM service URI for marionette

marionette attaches to the running app's Dart VM service rather than to the device, which
is what makes it the one capture path that works on a physical phone without extra device
tooling. It needs a `ws://.../ws` URI. Resolve it in this order and take the first that
answers:

1. **`--vm-uri <uri>`** on this skill's own invocation. `/design-build` owns the run
   session, reads the URI out of its `flutter run` output, and forwards it here.
2. **This run's own launch output.** When this skill ran the `flutter run` under "The app
   must be running and fresh", the address is in the streamed output it is already reading
   for `Error:` lines. `flutter run` prints it in its HTTP form --
   `A Dart VM Service on <device> is available at: http://127.0.0.1:<port>/<token>/` --
   so convert it: swap the `http` scheme for `ws` and append `ws`. Re-read it after any
   relaunch; the port and the token are both regenerated.
3. **A registered marionette instance** -- `marionette doctor` lists the registered
   instances and their connectivity. When exactly one is reachable *and* it is the target
   this run resolved, capture with
   `marionette -i <instance> take-screenshots --output <path>`. An instance registered by
   some other Flutter app on this machine is not this run's app; skip the row rather than
   photograph the wrong one.
4. **None of them** -- skip this row and fall to the next one. Do not prompt for a URI: a
   missing URI is missing tooling, and missing tooling never stops this skill.

With the marionette MCP loaded in the session, `connect` followed by `take_screenshots`
is equivalent to the CLI row and may be used instead. The CLI is listed first because it
needs no MCP server, which is the same reason every other native row here is a CLI
command.

Notes that change what these commands mean:

- **`adb exec-out`, not `adb shell`.** `shell` mangles the binary PNG stream with CRLF
  translation and produces a corrupt file that still writes successfully.
- **`pymobiledevice3`, not `idevicescreenshot`.** Apple moved the screenshot relay onto
  RemoteXPC over an RSD tunnel; libimobiledevice has no RSD implementation, so
  `idevicescreenshot` does not work on iOS 17 or later regardless of what it prints.
- **Playwright, not Puppeteer.** The reference Puppeteer MCP server is archived. In the
  Playwright MCP the element parameter is `target` (renamed from `ref`), and `fullPage`
  cannot be combined with an element screenshot.
- **A marionette capture is the app's own view, not the device screen.** It photographs
  the Flutter view, so the OS-drawn overlay -- status bar clock and battery, the home
  indicator -- is absent from the image while every pixel the app itself drew is present.
  Record it as `capture_surface: app-view` and read the two consequences in Phase 4.
- **marionette needs the app prepared and running in debug.** The app must depend on
  `marionette_flutter` and call `MarionetteBinding.ensureInitialized()`, and the VM
  service only exists in debug or profile builds. A release build has no URI to connect
  to. When the capture fails to attach, print the install hint once and fall to the next
  row.
- **marionette downscales large screenshots by default**, to fit within 2000x2000
  physical px. Phase 4 checks for it; the app-side fix is `maxScreenshotSize: null` in
  `MarionetteConfiguration`.
- **No MCP server is required for any native target.** Every native row above --
  simulator, emulator, and physical device -- is a CLI command run with the Bash tool.
  This is not a preference: no iOS MCP captures from a physical device. The
  xcodebuild-wrapping servers expose build, install, launch, and test for devices and stop
  there, and their screenshot tools are simulator-only, so an MCP row there would duplicate
  `simctl` under a second name and still leave the device uncovered. Web is the one row
  that goes through an MCP, because the browser is where the app runs.

### Exit codes lie here -- route on parsed output

Every one of these tools has a non-standard exit convention:

- `xcrun simctl io booted screenshot` exits **148** when nothing is booted.
- `adb exec-out` with no device attached exits **255**, while `adb devices -l` exits 0
  even when the list is empty.
- `flutter devices --machine` prints `[]` and exits **0** when nothing is attached, so
  detection reads the array length. Each device object also carries
  `capabilities.screenshot` as a boolean -- the cheapest per-target capability probe
  available.

**Route on parsed output, never on exit status.**

Run every probe with the **Bash tool**, mid-run, never inside a `` !`...` `` block. These
are non-git commands, and lesson L1 in `.claude/rules/skill-rules.md` forbids `||` with
non-git commands inside those blocks -- the permission parser splits on `||` and evaluates
each side independently.

### Missing tooling is informational, never terminal

When a tool is absent, print exactly one line naming what is missing, then continue down
the precedence ladder:

```
> marionette not found -- install with: dart pub global activate marionette_cli
> Continuing without a device capture.
```

The hint names the install command for the tool that was actually missing:

| Tool | Install hint |
|------|--------------|
| `marionette` | `dart pub global activate marionette_cli` |
| `adb` | ships with the Android SDK -- name the SDK, not a package |
| `magick` | `brew install imagemagick` |
| `pymobiledevice3` | none -- report the absence, see below |

**`pymobiledevice3` is used when it resolves and never recommended.** Every other tool
here installs with one command and needs no elevated privileges. That one does not: on
iOS 17+ it also needs a root tunnel daemon (`sudo pymobiledevice3 remote tunneld`) and a
mounted Developer Disk Image, which is a larger ask than one screenshot is worth from a
tool the user did not choose. It stays in the capture table because a machine that already
has it gets a real device capture out of it. When it is absent, report that and move on --
no install command, no second line:

```
> pymobiledevice3 not found -- capturing the simulator instead.
```

Do not print an install hint more than once per run. Do not stop.

### Reaching the screen

Use each node's `Route:` line from the plan to get the app onto the right screen before
capturing. When a node's `Route:` line is absent or reads
`not independently reachable`, skip the capture for that node and record the reason in
the report rather than capturing whatever screen happens to be open.

Print the resolved path once: `> Capture: {method}` or `> Capture: none -- spec check`.

## Phase 4 -- Normalize

**Normalization runs before any measurement.** This is not an optimization step that can
be skipped when the images look close.

A capture and a Figma export almost never share dimensions. The capture is a device
screenshot at the device's pixel ratio; the export is the frame at `screenshot_scale`.
ImageMagick 7 does not error on a dimension mismatch -- it aligns the smaller image
against the larger, pads with virtual pixels, and returns a plausible-looking number that
silently includes the padded region. An unnormalized comparison produces a wrong answer
that looks like a right one.

**The two sides do not start from the same origin, and each needs its own normalization.**

- **The reference PNG is node-clipped.** `/design` exports it with `clip: true` at
  `screenshot_scale`, so the file holds the node's own box at that scale -- not the frame.
  Its logical size is the node's `Box:` width and height.
- **A device capture is the whole screen** at the device's pixel ratio. Its logical size
  is the frame, not the node.
- **An app-view capture is the app's own surface** -- the same logical rect as the screen
  for an app that draws edge to edge, so it normalizes exactly like a device capture. Two
  things differ, and both belong in the report rather than in the arithmetic. A node whose
  box overlaps a band the OS draws over the app -- the status bar, the home indicator --
  is being compared against Figma pixels no app-view capture can contain, so record that
  difference as a chrome artifact, not as design drift. And a capture measuring exactly
  2000 physical px on either axis hit marionette's default downscale cap: mark the report
  `confidence: low` and print the `maxScreenshotSize: null` hint once.

Intermediates land beside the capture: `<screenshot_dir>/actual/<task-id>-ref.png`,
`-norm.png`, and `-crop.png`.

1. **Normalize the reference to the node's logical box.** Take `w` and `h` from the node
   spec's `Box:` line. The reference is that box at `screenshot_scale`, so this is a
   scale-only resize and the aspect ratio already matches:
   ```
   magick <reference.png> -resize '<w>x<h>!' <ref.png>
   ```
   The `!` is required; without it ImageMagick preserves aspect ratio and the output does
   not land on the requested size. **Never resize the reference to `figma_frame_size`.**
   It is not a frame image. Stretching a node crop to frame dimensions, then cropping it
   again at the node's absolute coordinates, reads a region that lies outside the original
   node entirely -- every delta downstream is a geometry artifact, and the fix loop then
   edits working code to chase it.
2. **Normalize the capture to the frame's logical size**, from `figma_frame_size`. When
   `figma_frame_size` is absent, skip normalization entirely and mark the report low
   confidence -- do not guess a frame size.
   - **Scale-only difference** (same aspect ratio, different pixel dimensions):
     ```
     magick <capture.png> -resize 'WxH!' <norm.png>
     ```
   - **Aspect-ratio difference** (a taller device than the Figma frame):
     ```
     magick <capture.png> -background none -gravity NorthWest -extent WxH <norm.png>
     ```
     Pad, do not resize. `-resize` across differing aspect ratios stretches the image and
     shifts every element, so every measured delta afterwards is wrong. Gravity must be
     `NorthWest`: `Center` shifts content by half the size delta on both axes, which
     silently invalidates every anchor measurement.
3. **Crop the normalized capture to the node's box**, in logical px, from the same `Box:`
   line -- absolute `x`, `y`, `w`, `h`:
   ```
   magick <norm.png> -crop '<w>x<h>+<x>+<y>' +repage <crop.png>
   ```
   `+repage` is required; without it the crop keeps the original canvas geometry and every
   later `identify` reports the frame size instead of the crop.
   **The reference is never cropped.** It is already the node.
4. **Confirm both sides ended up the same size** before comparing:
   ```
   magick identify -format '%wx%h ' <ref.png> <crop.png>
   ```
   Two different sizes mean the crop coordinates or the frame size are wrong. Say which,
   mark the report low confidence, and do not compare anyway -- a mismatch here is exactly
   the padded-comparison failure this phase exists to prevent.

A capture that is already node-scoped -- a Playwright element screenshot taken with
`element` and `target` -- skips steps 2 and 3 and resizes straight to the node's logical
box, like the reference.

Without ImageMagick, do the equivalent reasoning structurally: state the node box, the
reference size, the capture size, and the scale factor between them in the report, and
treat every measurement you read off the image as relative to that factor.

## Phase 5 -- Compare

### Select the metric

Probe availability first, with the Bash tool:

```
magick -version
```

Exit 127 means ImageMagick is absent. This is also a clean IM7-versus-IM6 discriminator,
because IM6 never shipped a `magick` binary.

Then probe which metric to use:

```
magick -list metric
```

- **`PDC` present:** use it. `PDC` (pixel difference count) was added in 7.1.2-20 and is
  the current way to get a differing-pixel count.
- **`PDC` absent:** fall back to `AE` -- but only on these older builds, where `AE` still
  means a differing-pixel count. **Do not use `-metric AE` without this probe.**
  ImageMagick 7.1.2-27 silently redefined `AE` as a normalized per-channel absolute-error
  magnitude with no deprecation warning, and 7.1.2-28 normalized it further. On a current
  build, `AE` returns a number that is not a pixel count and reads as a suspiciously small
  deviation.

### Run the comparison

```
magick compare -metric PDC -fuzz 5% -alpha off <ref.png> <crop.png> null: 2>&1
```

Four facts about this command, each of which changes the result if ignored:

1. **The metric goes to stderr, not stdout, with no trailing newline.** Capturing stdout
   alone yields an empty string. The `2>&1` above is what makes the number readable.
2. **Exit code 1 means "the images differ but the comparison succeeded."** That is the
   normal path for any real comparison, not a failure. Exit 2 is a hard error -- a
   missing file, an unreadable format, an unknown metric. Exit 0 means the images are
   within the fuzz tolerance.
3. **`-fuzz` must precede the input files.** Placed after them it is silently ignored,
   and it is honored only by `AE`, `PDC`, `PAE`, and `MAE`.
4. **`-alpha off` is required on both sides.** PNG alpha participates in the metric, so
   an opaque device capture compared against a transparent Figma export reports every
   single pixel as differing.

Omit `-subimage-search`. It always takes the slow path for these metrics and answers a
question this skill is not asking.

Without ImageMagick, read the two normalized crops structurally against the spec and mark
the report's comparison path `structural`.

### From the metric to the measurements

**The metric is a screening number, not a measurement.** It answers one question -- does
this node's crop differ from its reference at all, and across how many pixels -- and it
cannot answer any of the questions in the check order below. A pixel count carries no box
height and no font size. Record it in the report as `diff_pixels` and use it only as the
gate:

- **`diff_pixels` is 0**, or `magick compare` exited 0 (everything within `-fuzz`): the
  node matches. Write a report with an empty deviation table and stop. Do not measure
  fields.
- **`diff_pixels` is greater than 0**: run the check order, and fill each `Measured` cell
  from the source named below. Never fill a `Measured` cell from `diff_pixels` -- it is
  one number for the whole node and cannot be divided across rows.

Each field group has exactly one measurement source:

| Field group | Measured from | How |
|-------------|---------------|-----|
| `box.width`, `box.height` | the normalized capture crop | `magick <crop.png> -alpha off -fuzz 5% -trim -format '%wx%h' info:` -- the trimmed content size, already in logical px |
| `anchor.x`, `anchor.y` | the crop's content within the crop box | trim as above with `-format '%wx%h%O'`; `%O` gives the trimmed content's offset inside the crop, and the node's measured center is that offset plus half the trimmed size, plus the crop's own `x`/`y` |
| `spacing` | the normalized capture crop | measure the gap between two adjacent trimmed child regions in the crop, in logical px |
| `typography`, `paint` | the implementation source | no pixel operation returns a font weight, a token name, or a radius value. Read the code the build wrote against the spec line, and mark these rows `source: code` in the report |

The 2px tolerance below applies to these per-field deltas. It never applies to
`diff_pixels`, which is a count, not a distance.

### Check order

Check in this order, and report each miss as a deviation with its measured delta:

1. **Anchor** -- is the node positioned relative to the right region? Measure its center
   against the chrome-excluded region's center from the node spec's `Anchor:` line.
   **This is first because it is the check that silently passes.** A node centered in the
   wrong region reads as correct at a glance while every single dimension checks out.
2. **Box** -- width, height, and insets against the spec numbers. Where the node spec's
   `Fit:` line says an axis is `fill`, verify the fill behavior, not the literal number
   on the `Box:` line -- that number is what the axis measured at one frame size.
3. **Spacing** -- gaps and padding.
4. **Typography** -- size, weight, line height, color.
5. **Paint** -- fill, stroke, radius, effects.

**Tolerance is 2 logical px per single measurement.** Anything larger is a deviation.

The tolerance is per measurement, not cumulative. Four separate 2px deviations still add
up to a visibly wrong layout, so when several small in-tolerance deviations cluster on one
node, recheck the anchor -- clustered small deltas are the signature of a node placed
relative to the wrong region, where each individual dimension passes and the composition
does not.

## Phase 6 -- Write the Deviation Report

Write to `<screenshot_dir>/verify/<task-id>.md`, where `<task-id>` is:

- the `--task` value when mode is `build`,
- the node ID (with `:` replaced by `-`) when mode is `standalone`.

Create `<screenshot_dir>/verify/` if it does not exist. (`<screenshot_dir>/actual/` was
already created in Phase 3, before the first capture.)

Fixed report shape -- identical in both modes, so a human reading a standalone report and
`/design-build` reading a composed one see the same file:

```markdown
---
plan: .claude/plans/2026-08-17-wallet-design-plan.md
task_id: 3
nodes: ["4029:12345"]
capture_method: ios-simulator | android-adb | ios-device | flutter-marionette | web-playwright | supplied | none
capture_surface: device-screen | app-view | none
comparison_path: imagemagick-pdc | imagemagick-ae | structural | spec-check
confidence: high | low
normalized: true | false
diff_pixels: 18432 | none
created: YYYY-MM-DD HH:MM:SS
---

# Deviation Report -- <NodeName> (`4029:12345`)

Reference: .claude/plans/assets/wallet/4029-12345.png
Capture:   .claude/plans/assets/wallet/actual/3.png
Normalized to: 327x48 logical px, the node box
  (reference 654x96 at 2x, capture 1179x2556 at 3x -> frame 375x812 -> crop +24+320)

## Deviations

| Field | Expected | Measured | Delta | Source |
|-------|----------|----------|-------|--------|
| anchor.y | centered in Body content box (376) | 402 | +26 px | crop |
| box.height | 48 | 56 | +8 px | crop |
| typography.size | 16 | 14 | -2 px | code |

## Notes

- Node `4029:12400` skipped: no Route: line in the spec, screen not reachable.
```

Rules for the report:

- **Every delta is stated in logical px**, computed after normalization. A delta measured
  on unnormalized images is not a delta, it is a scale artifact.
- **Every row names its `Source`** -- `crop` for a value read off the normalized crop,
  `code` for a value read from the implementation. A row with no source is a guess.
- **`diff_pixels` records the screening metric**, or `none` when no metric ran. It is
  never a `Measured` value.
- **`capture_surface` records what the image is**, not which tool made it. A reader
  comparing two runs needs to know whether the missing status bar was a design change or
  the capture path changing under them, and `capture_method` alone does not say.
- **`confidence: low`** whenever normalization was skipped, the comparison path is
  `spec-check` or `structural`, `figma_frame_size` was absent, or the two normalized
  sides did not end up the same size.
- **A clean run still writes a report.** Zero deviations produces the same file with an
  empty deviation table and a line saying so. An absent report file therefore means
  exactly one thing: the verify step did not run. Nothing else may be inferred from a
  missing file.
- **An empty table is not by itself a pass.** "Measured and matched" and "never measured"
  both produce an empty table, and the frontmatter is what separates them: a pass carries
  `comparison_path: imagemagick-*` with `confidence: high`, while an unmeasured run
  carries `spec-check` or `structural`, or `confidence: low`, and lists every skipped node
  under `## Notes` with its reason. Readers key on those fields, never on the row count.
- **Read the file back after writing it** and confirm it exists (rule L3 in
  `.claude/rules/skill-rules.md`). A silent write failure would read downstream as "verify
  did not run", which is the wrong conclusion.

Print: `> Deviation report: {path} ({N} deviations, confidence {high|low})`.

## Phase 7 -- Summarize

When mode is `build`, stop here. The caller reads the file.

When mode is `standalone`, print the deviation table inline, then call
`AskUserQuestion`:

> {N} deviations measured against the spec. What next?

Buttons: `["Fix them -- run /design-build", "Just show me the report", "Stop here"]`

- **Fix them:** invoke the `design-build` skill with the plan path.
- **Just show me the report:** print the report body and stop.
- **Stop here:** stop.

---

## Anti-Patterns

Follow all rules in `.claude/rules/skill-rules.md`. Additionally:

- **Don't** call figma-bridge tools. This skill never opens Figma; the plan carries the
  measurements and `screenshot_dir` carries the reference images.
- **Don't** measure before normalizing. A dimension mismatch does not error -- it pads and
  returns a wrong number that looks right.
- **Don't** resize the reference PNG to `figma_frame_size` or crop it by the node's
  absolute box. It is exported node-clipped, so it is already the node.
- **Don't** fill a `Measured` cell from the comparison metric. It is one count for the
  whole node; per-field values come from the crop or from the code.
- **Don't** run a capture command without resolving `<path>` first. Every capture lands at
  `<screenshot_dir>/actual/<task-id>.png`, under a directory created with `mkdir -p`.
- **Don't** let `capture_preference` override an explicit `--screenshot`. A typed path
  outranks a stored preference.
- **Don't** capture from whichever target answers first when several are live. Resolve the
  target from the project manifest, then ask (standalone) or take the ordered first
  (build).
- **Don't** build on one target and capture from another. One resolution, both halves.
- **Don't** rank a physical device first when no tool can photograph it. Probe the capture
  tooling before the target order is applied, not after a capture fails.
- **Don't** retry a code-signing failure on the device. Fall back to the simulator once
  and spend the remaining attempts on something a retry can change.
- **Don't** prompt for a VM service URI. An unresolvable URI is missing tooling, and
  missing tooling never interrupts this skill.
- **Don't** add an MCP row for a physical-device capture. No iOS MCP has one -- the
  xcodebuild-wrapping servers stop at build, install, launch, and test.
- **Don't** treat `magick compare` exit code 1 as a failure. It means the images differ,
  which is the entire point of running it.
- **Don't** use `-metric AE` without probing `magick -list metric` for `PDC` first. On
  current builds `AE` is no longer a pixel count.
- **Don't** route on exit status for any capture tool. 148, 255, and a successful 0 on an
  empty device list all mean something other than what they look like.
- **Don't** detect which skill invoked this one. Mode is an argument.
- **Don't** verify a node marked `Scope: reference only` unless `--nodes` names it.
- **Don't** demand a screenshot. Every path degrades to a spec read.
- **Don't** block on a missing tool. One install hint, then continue.
- **Don't** put a capture probe inside a `` !`...` `` block. Non-git commands with `||`
  fail the permission parser (lesson L1).
- **Don't** skip writing the report when there are no deviations. A missing file must mean
  only that the step did not run.

---

## Test Plan

**Trigger:** `/design-verify`, `/design-verify .claude/plans/2026-08-17-wallet-design-plan.md --mode build --task 3`, `/quiver:design-verify`

**Setup:**
- A plan carrying a `### Node Specs` section with at least one node that has `Box:`,
  `Anchor:`, and `Route:` lines.
- For the measured path: reference PNGs under `screenshot_dir` and a runnable app.
- For the fallback paths: the same plan with no reference images, and a machine with no
  ImageMagick and no device tooling.

**Expected behavior:**
1. Both shell blocks exit 0 in a git repo and in a non-git directory.
2. A plan with `### Node Specs` but no `design_source` is accepted and verified.
2b. A node carrying `Scope: reference only` is skipped and listed under `## Notes`, and is
    verified anyway when `--nodes` names it explicitly.
3. A file with no `### Node Specs` section is rejected with a message; nothing is written.
4. A plan missing all five new frontmatter fields loads on the documented defaults.
5. `--screenshot <path>` is used directly; no capture is attempted. It is used even when
   the plan carries `capture_preference: skip`.
6. With `capture_preference: skip` and no `--screenshot`, no capture command runs at all
   and the report's comparison path is `spec-check`.
7. With `capture_preference: manual`, a file already at
   `<screenshot_dir>/actual/<task-id>.png` is used in both modes with no question asked.
   With no such file and no supplied path, the run prints the drop-here line once and
   falls to the spec read rather than capturing.
7b. With a booted iOS simulator and an attached Android device both live, `standalone`
    asks which to use and `build` takes the manifest-ordered first, recording it as
    `capture_method`.
8. With no capture tooling installed, each absent tool prints exactly one install line and
   the run reaches a written report.
8b. `--mode standalone` accepts an already-running app without rebuilding it; `--mode
    build` rebuilds and relaunches before the first capture.
8c. Three consecutive failed build-and-launch attempts produce no fourth attempt: the run
    continues on the spec read and the report records
    `capture_method: none -- launch failed after 3 attempts`.
8d. With `capture_preference: skip`, no build-and-launch attempt runs at all.
8e. With no MCP server loaded at all, the CLI row for the resolved target is used and
    nothing reports a missing MCP as an error.
8f. The capture-tooling probe runs once, before the target is resolved, and prints one
    line naming every absent tool with its install command.
8g. With a physical device attached and neither `marionette` nor `pymobiledevice3`
    installed, the device rows are dropped and the simulator row is used.
8h. With two devices attached, one wired and one wireless, the wired one is resolved
    first; the transport comes from `connectionProperties.transportType` in devicectl's
    JSON output file, never from its stdout table.
8i. A device build failing on code signing falls back to the simulator exactly once,
    prints the fallback line, and spends one attempt doing it.
8j. A Flutter app running on a physical device is captured through marionette when a URI
    resolves from `--vm-uri` or a registered instance, and the report records
    `capture_method: flutter-marionette` with `capture_surface: app-view`.
8k. With `marionette` absent, a Flutter run falls to its platform's CLI row and prints the
    `dart pub global activate marionette_cli` hint once.
9. An iOS simulator capture succeeds with no MCP server configured.
10. `xcrun simctl` exiting 148, `adb` exiting 255, and `flutter devices --machine`
    printing `[]` with exit 0 are all routed from parsed output, not exit status.
11. `--mode standalone` makes the manual-screenshot offer once; `--mode build` never does.
12. Normalization runs before any measurement, and every delta in the report is in
    logical px.
12b. The reference is resized to the node's `Box:` size and never cropped; the capture is
     resized to `figma_frame_size` and then cropped at the node's absolute box. Both
     sides `identify` to the same size before the comparison runs.
13. `PDC` is selected when `magick -list metric` lists it; `AE` only when it does not.
14. `magick compare` exit code 1 produces deviations, never an error.
14b. `diff_pixels` appears in the report frontmatter, and no `Measured` cell repeats it.
     Every deviation row carries a `Source` of `crop` or `code`.
15. A run with zero deviations still writes a report file, with
    `comparison_path: imagemagick-*` and `confidence: high` when it was actually measured.
16. The report is read back after writing and its path is printed.
17. Captures and their intermediates land under `<screenshot_dir>/actual/`, which is
    created before the first capture runs.

**Verification checklist:**
- [ ] `/design-verify` and `/quiver:design-verify` both appear in the slash menu after plugin reload.
- [ ] Both `!` blocks exit 0 with `NO_GIT` output in a non-git directory.
- [ ] Validation checks `### Node Specs` only -- never `design_source`.
- [ ] The plan frontmatter fence is not reproduced anywhere in this file.
- [ ] Every field this skill reads is listed with its default when absent.
- [ ] No capture probe appears inside a `` !`...` `` block.
- [ ] Every capture command's `<path>` resolves to `<screenshot_dir>/actual/<task-id>.png`.
- [ ] The reference normalization targets the node box, never `figma_frame_size`.
- [ ] Every field group in the check order has a named measurement source.
- [ ] No figma-bridge tool is called anywhere in this file.
- [ ] The report is written in both modes and in every comparison path.
- [ ] The build-and-launch attempt cap reads 3 and the degrade path continues without a
      capture rather than stopping.
- [ ] Every native capture row is a CLI command; only Web requires an MCP server.
- [ ] The capture-tooling probe appears before the target resolution, not after it.
- [ ] The launch table and the capture table resolve the same target.
- [ ] `capture_surface` is written into every report's frontmatter.
- [ ] `when-to-use:` is a single-line double-quoted string.
- [ ] No `CLAUDE_PLUGIN_ROOT` reference anywhere in this file.
- [ ] No Unicode characters or emoji in this file.
- [ ] No `$()`, variable assignment, or `if/else` inside any `!` block.

**Known gotchas:**
- `magick compare` writes its metric to stderr with no trailing newline. Reading stdout
  returns an empty string and looks like a zero-deviation result.
- ImageMagick redefined `-metric AE` in 7.1.2-27 without a deprecation warning. Any skill
  or script written before that release returns a wrong number on a current build rather
  than failing.
- A dimension mismatch is the dangerous case precisely because it does not error.
  ImageMagick pads the smaller image with virtual pixels and reports a number that
  includes the padding.
- `-gravity Center` on `-extent` shifts content by half the size delta on both axes. Every
  anchor measurement taken afterwards is off by that amount, and the images still look
  correct side by side.
- The reference PNG is node-clipped, not a frame render. Treating it as a frame -- resize
  to `figma_frame_size`, then crop at the node's absolute coordinates -- reads a region
  outside the node, and the resulting deltas look like real design drift.
- `-crop` without `+repage` leaves the original canvas geometry attached. The file looks
  cropped in a viewer while `identify` still reports the frame size.
- `idevicescreenshot` still exists and still runs on iOS 17+; it just never returns an
  image. An empty output file, not an error, is the symptom.
- `adb shell screencap -p` writes a file that opens in some viewers and fails in others,
  because the CRLF translation corrupts the stream. `exec-out` is the only correct form.
- `flutter devices --machine` is a hidden flag. It exits 0 whether or not a device is
  attached, so an exit-status check reports success against an empty list.
- `flutter run` does not return while the app is alive. Waiting on it blocks the run;
  read its streamed output instead and treat the first `Error:` line as the attempt's
  failure.
- `xcrun devicectl` prints a device table to stdout and documents that table as
  human-readable output. `--json-output <path>` writing a file is the only interface it
  supports for scripts, so a run that greps the table is reading something Apple does not
  promise to keep stable.
- `xcrun devicectl` has no screenshot subcommand, and neither does any MCP server built
  on top of it. A physical device is the only target where build, install, and launch all
  work while capture needs a separate tool.
- marionette photographs the Flutter view, so a screenshot from it never contains the
  status bar clock or the home indicator. Against a Figma frame that draws them, that band
  reports a deviation on every run and no code change fixes it.
- marionette silently downscales screenshots to fit 2000x2000 physical px. The image is
  well-formed and the deviations it produces look like real drift, which is the same
  failure mode as an unnormalized comparison.
- marionette only works in debug and profile builds, because the VM service does not
  exist in release. A release build produces no URI, and the failure reads as a
  connection error rather than a mode error.

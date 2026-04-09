---
name: visual-companion
description: Browser-based visual brainstorming companion for showing mockups, diagrams, and visual options. Use when brainstorm topics involve UI/UX, layout, architecture diagrams, or any content better understood visually.
---

# Visual Companion

A browser-based companion for displaying mockups, wireframes, architecture diagrams, and side-by-side visual comparisons during brainstorm sessions.

## 1. When to Use

Decide **per question** whether to show content in the browser or keep it in the terminal.

**Use the browser for:**
- UI mockups and wireframes
- Architecture diagrams and system maps
- Side-by-side visual comparisons (layout A vs. layout B)
- Spatial relationships (grid layouts, navigation flows, screen transitions)
- Color palettes, typography samples, component galleries

**Use the terminal for:**
- Requirements questions and conceptual choices
- Tradeoff lists and technical decisions
- Clarifying questions about scope or constraints
- API design, data models, algorithm selection

A question about a UI topic is not automatically a visual question. "Should we use tabs or accordion?" is a terminal question. "Here are two tab layouts -- which one?" is a browser question.

## 2. Starting a Session

1. Create a temporary directory for HTML files:
   ```
   mktemp -d /tmp/visual-companion-XXXXXX
   ```

2. Start the visual companion server in the background:
   ```
   python3 <skill-dir>/server.py --dir <temp-dir> --owner-pid $$ &
   ```
   `<skill-dir>` is resolved by the invoking agent to the absolute path of `skills/visual-companion/`.

3. Read `server-info.json` from the `.vc-meta` subdirectory to get the URL and port:
   ```
   cat <temp-dir>/.vc-meta/server-info.json
   ```
   Returns `{"port": N, "pid": N, "url": "http://localhost:N"}`.

4. Tell the user:
   > Visual companion running at {url}. It auto-refreshes when I update content.

## 3. The Loop

For each visual step in the brainstorm:

1. **Write an HTML fragment** to `<temp-dir>` with a semantic filename (e.g., `layout-options.html`). Write body content only -- the server wraps fragments automatically.
2. **Never reuse filenames.** Each screen gets a fresh file. For iterations, append a version suffix: `layout-options-v2.html`.
3. **Browser auto-reloads** via SSE when a new or changed `.html` file is detected. No manual refresh needed.
4. **For clickable options:** Use `data-choice` attributes on elements. The client JS handles selection toggling and event capture.
5. **Read events:** Before the next question, read `<temp-dir>/.vc-meta/events.jsonl` to check for user clicks.
6. **Clear events:** `DELETE /events` before presenting a new visual question to clear prior selections.
7. **Terminal-only steps:** No browser action needed. Optionally push a placeholder page:
   ```html
   <div style="display:flex;align-items:center;justify-content:center;height:100vh;font-family:system-ui;color:#666">
     <p>Continuing in terminal...</p>
   </div>
   ```

## 4. HTML Content Guide

Write body content only. The server wraps fragments with DOCTYPE, CSS, and client JS automatically.

A file is treated as a fragment if its first 256 bytes (stripped, case-insensitive) do not start with `<!DOCTYPE` or `<html>`. Full HTML documents are served as-is, with client JS injected before `</body>`.

### Layout Patterns

- **Options grid:** Use `.options` + `.option` for comparing 2-3 approaches visually. Mark the recommended option with `.recommended`.
- **Cards:** Use `.cards` + `.card` for component galleries or feature inventories.
- **Mockup:** Use `.mockup` with `.mock-nav`, `.mock-sidebar`, `.mock-content` for wireframes.
- **Split view:** Use `.split` for before/after or A/B comparisons.
- **Pros/cons:** Use `.pros-cons` for tradeoff visualization.
- **Mock UI:** `.mock-button`, `.mock-input` for wireframe form elements.

### Clickable Options with `data-choice`

Add `data-choice` attributes to elements that users can click to make selections:

```html
<div class="options">
  <div class="option" data-choice="grid">
    <h3>Grid Layout</h3>
    <p>Content arranged in a responsive grid</p>
  </div>
  <div class="option" data-choice="list">
    <h3>List Layout</h3>
    <p>Content in a vertical list</p>
  </div>
</div>
```

When a user clicks a `[data-choice]` element:
- The `.selected` class is added (blue border + light blue background)
- Previous selections within the same parent are deselected
- A JSON event is appended to `.vc-meta/events.jsonl`:
  ```
  {"type":"choice","choice":"grid","text":"Grid Layout Content arranged in a responsive grid","timestamp":"2026-04-09T14:30:00.000Z"}
  ```

### events.jsonl Format

Each line is a JSON object appended by the server. The agent reads this file to see what the user clicked:
```
{"type":"choice","choice":"option-a","text":"Option A","timestamp":"..."}
{"type":"choice","choice":"option-b","text":"Option B","timestamp":"..."}
```

## 5. Cleaning Up

The server self-terminates in two cases:
- **Idle timeout:** No HTTP requests for 30 minutes.
- **Owner PID death:** The `--owner-pid` process no longer exists (checked every 0.5s).

To stop manually:
```
kill $(cat <temp-dir>/.vc-meta/server-info.json | python3 -c "import sys,json; print(json.load(sys.stdin)['pid'])") 2>/dev/null
```

HTML files remain in the temp directory for reference. Optionally copy key mockups to `docs/brainstorms/` alongside the spec:
```
cp <temp-dir>/final-layout.html docs/brainstorms/YYYY-MM-DD-<name>-mockups/
```

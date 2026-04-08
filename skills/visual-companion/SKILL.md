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

2. Start a local server in the background:
   ```
   python3 -m http.server 8432 --directory <temp-dir> &
   ```

3. Save the server PID for cleanup:
   ```
   echo $! > <temp-dir>/.server-pid
   ```

4. Tell the user:
   > Visual companion is running. Open http://localhost:8432 in your browser.
   > I will tell you when to refresh for new content.

## 3. The Loop

For each visual step in the brainstorm:

1. **Write an HTML file** to the temp directory with a semantic filename (e.g., `layout-options.html`, `navigation-flow.html`).
2. **Never reuse filenames.** Each screen gets a fresh file. For iterations, append a version suffix: `layout-options-v2.html`.
3. **Tell the user** to open the specific file URL: `http://localhost:8432/layout-options.html`
4. **User provides feedback** in the terminal. There is no client-side event system -- all communication happens through the normal conversation.
5. **When returning to terminal-only questions:** Push a placeholder page so the user knows the visual step is done:
   ```html
   <div style="display:flex;align-items:center;justify-content:center;height:100vh;font-family:system-ui;color:#666">
     <p>Continuing in terminal...</p>
   </div>
   ```

## 4. HTML Content Guide

Write content fragments, not full documents. Each HTML file should be self-contained with inline styles.

### Frame Template

Use this base structure for all visual pages:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{Page Title}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: system-ui, -apple-system, sans-serif; padding: 2rem; background: #fafafa; color: #1a1a1a; }
  h1 { font-size: 1.5rem; margin-bottom: 1.5rem; }
  h2 { font-size: 1.1rem; margin-bottom: 1rem; color: #444; }

  /* Options grid -- side-by-side approach comparison */
  .options { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1.5rem; }
  .option { background: #fff; border: 2px solid #e0e0e0; border-radius: 8px; padding: 1.5rem; }
  .option.recommended { border-color: #2563eb; }
  .option h3 { margin-bottom: 0.75rem; }

  /* Cards -- feature or component gallery */
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; }
  .card { background: #fff; border: 1px solid #e5e5e5; border-radius: 6px; padding: 1rem; }

  /* Mockup container -- wireframe wrapper */
  .mockup { background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 1rem; max-width: 800px; margin: 0 auto; }

  /* Split view -- two-panel comparison */
  .split { display: grid; grid-template-columns: 1fr 1fr; gap: 2rem; }

  /* Pros and cons */
  .pros-cons { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
  .pros-cons .pros { color: #16a34a; }
  .pros-cons .cons { color: #dc2626; }

  /* Mock UI elements for wireframes */
  .mock-nav { background: #f3f4f6; padding: 0.75rem 1rem; border-bottom: 1px solid #e5e5e5; display: flex; gap: 1rem; align-items: center; }
  .mock-sidebar { background: #f9fafb; padding: 1rem; border-right: 1px solid #e5e5e5; min-width: 200px; }
  .mock-content { padding: 1.5rem; flex: 1; }
  .mock-button { display: inline-block; background: #2563eb; color: #fff; padding: 0.5rem 1rem; border-radius: 4px; font-size: 0.875rem; }
  .mock-input { display: block; width: 100%; padding: 0.5rem; border: 1px solid #d1d5db; border-radius: 4px; background: #fff; margin-bottom: 0.5rem; }
</style>
</head>
<body>
  <!-- Content here -->
</body>
</html>
```

### Layout Patterns

- **Options grid:** Use `.options` + `.option` for comparing 2-3 approaches visually. Mark the recommended option with `.recommended`.
- **Cards:** Use `.cards` + `.card` for component galleries or feature inventories.
- **Mockup:** Use `.mockup` with `.mock-nav`, `.mock-sidebar`, `.mock-content` for wireframes.
- **Split view:** Use `.split` for before/after or A/B comparisons.
- **Pros/cons:** Use `.pros-cons` for tradeoff visualization.

## 5. Cleaning Up

When the brainstorm session ends:

1. Kill the server:
   ```
   kill $(cat <temp-dir>/.server-pid) 2>/dev/null
   ```

2. HTML files remain in the temp directory for reference.

3. Optionally copy key mockups to `docs/brainstorms/` alongside the spec:
   ```
   cp <temp-dir>/final-layout.html docs/brainstorms/YYYY-MM-DD-<name>-mockups/
   ```

---
name: code-navigation
description: "LSP-first code navigation with grep fallback. Provides agents with a reusable strategy for semantic code exploration -- goToDefinition, findReferences, documentSymbol -- with automatic fallback to grep when LSP is unavailable or returns empty results."
---

# Code Navigation

Reference skill for agents that search the broader codebase. Defines when to use LSP vs Grep/Glob and how to handle fallback.

## LSP Operation Catalog

Three semantic operations where LSP outperforms grep. For everything else, use Grep/Glob/Read directly.

| Operation | Use When | Grep Fallback |
|-----------|----------|---------------|
| `goToDefinition` | Find where a function, class, or type is defined | Grep for `function {name}`, `class {name}`, `def {name}`, `const {name}` |
| `findReferences` | Find all callers or consumers of a symbol | Grep for the symbol name (noisier -- includes comments, strings, partial matches) |
| `documentSymbol` | Get a structural overview of a file's exports and symbols | Read the file and parse manually |

**Not covered by this skill** (Grep/Glob is already sufficient):
- File discovery -- use Glob
- Text pattern matching -- use Grep
- Content reading -- use Read

## Agent Instructions Block

Agents that search the broader codebase should include this block in their prompt. The dispatching command passes `lsp_available: true|false` as part of the agent's context.

```
## Code Navigation Strategy

You have been provided an `lsp_available` flag in your context.

**When `lsp_available: true`:**
- For finding where a function/class/type is defined: use LSP goToDefinition first.
- For finding all callers or consumers of a symbol: use LSP findReferences first.
- For getting a structural overview of a file: use LSP documentSymbol first.
- If LSP returns empty or unhelpful results for any operation, inform the user:
  "LSP returned no results for {operation} on `{symbol}` -- falling back to grep-based search."
  Then use the grep equivalent from the catalog above.
- For file discovery and pattern matching: always use Grep/Glob regardless of LSP availability.

**When `lsp_available: false`:**
- Use Grep, Glob, and Read for all code navigation.
```

## Command-Level LSP Detection

Commands that dispatch code-exploration agents (`/plan`, `/review`) run this detection once before agent dispatch. The result is passed to all agents as context.

### Detection Flow

1. **Check project memory** for cached LSP preference.
   - If `lsp_declined` found: set `lsp_available=false`, skip to step 4.
   - If `lsp_confirmed` found: set `lsp_available=true`, skip to step 4.

2. **Attempt an LSP probe.**
   - Try a lightweight LSP call (e.g., `documentSymbol` on any source file from the project root).
   - If LSP responds with results: set `lsp_available=true`, cache `lsp_confirmed` in project memory, skip to step 4.

3. **LSP not available -- prompt user.**
   - Detect project language from manifest files (`package.json`, `Gemfile`, `requirements.txt`, `pubspec.yaml`, `go.mod`, `Cargo.toml`, `Package.swift`, etc.).
   - Use `AskUserQuestion` to suggest installation:

     > LSP is not available for this project. Installing a language server (e.g., {recommended_server} for {language}) would enable better code navigation -- go-to-definition, find-references, and symbol search. Would you like to set it up? (You can always use /plan and /review without it -- grep-based navigation works fine.)

     Buttons: `["Yes, help me set it up", "No, continue with grep"]`

   - If user accepts: provide installation instructions for the detected language server, re-probe LSP, cache result in project memory.
   - If user declines: set `lsp_available=false`, cache `lsp_declined` in project memory.

4. **Pass `lsp_available` flag** to all dispatched agents as part of their context.

### Language Server Recommendations

| Language | Recommended Server | Install Command |
|----------|-------------------|-----------------|
| TypeScript/JavaScript | typescript-language-server | `npm install -g typescript-language-server typescript` |
| Python | pyright | `npm install -g pyright` or `pip install pyright` |
| Go | gopls | `go install golang.org/x/tools/gopls@latest` |
| Rust | rust-analyzer | Install via rustup or IDE extension |
| Swift | sourcekit-lsp | Included with Xcode |
| Dart/Flutter | dart language-server | Included with Dart SDK |
| Ruby | solargraph | `gem install solargraph` |
| Java/Kotlin | jdtls | Install via IDE or manually |

### Memory Caching

LSP preference is stored in project memory:

- **File:** `lsp_preference.md` in the project's auto-memory directory
- **Content:** Whether LSP is available/declined, which language server was detected, date cached
- **Lifetime:** Persists across sessions. User can reset by saying "forget LSP preference" or by installing a language server and re-running a command.

## For Agent Authors

If your agent searches the broader codebase (beyond files it already knows about), reference this skill:

1. Add the **Code Navigation Strategy** block from above to your agent's prompt.
2. Ensure the dispatching command passes `lsp_available` context to your agent.
3. Your agent does NOT need to handle LSP detection -- that is the command's responsibility.

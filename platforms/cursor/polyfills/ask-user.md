# AskUserQuestion Polyfill (Cursor)

Cursor does not expose a public action-button question API as of 2026. When a Quiver command requests a user decision, the agent must render a numbered text prompt and wait for the user's reply.

## Format

```
<one-sentence question>

1. <Option A label> -- <one-line description>
2. <Option B label> -- <one-line description>
3. <Option C label> -- <one-line description>
4. Other -- <ask the user to describe>

Reply with the number, or describe your choice.
```

## Rules

1. Always include "Other -- describe" as the last option, mirroring Claude Code's free-text fallback.
2. Number options 1-N; do not letter them. Numbered options are easier to type on mobile and over voice.
3. Do not collapse multiple decisions into a single prompt unless the original `AskUserQuestion` call did so. One question per polyfill prompt is the default.
4. After the user replies with a number, restate the choice in one sentence ("Going with option 2: ...") before continuing. This catches misclicks visible to the user before the action runs.

## When to apply

Apply this polyfill anywhere a Quiver command body says `AskUserQuestion(...)`, `use AskUserQuestion`, or describes action-button prompts. The Cursor rule file at `platforms/cursor/rules/quiver-shell-blocks.mdc` tells the agent to substitute this format.

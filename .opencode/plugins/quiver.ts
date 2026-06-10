import type { Plugin } from "@opencode-ai/plugin"

export const QuiverPlugin: Plugin = async (ctx) => {
  await ctx.client.app.log({
    body: {
      service: "quiver",
      level: "info",
      message: "Quiver plugin initialized",
    },
  })

  return {
    "experimental.session.compacting": async (input, output) => {
      output.context.push(`## Quiver Handover Context
When generating a continuation summary for this session, include the following Quiver-specific state:

- **Current branch and task**: What branch you are on and what task/feature you are working on.
- **Completed work**: What has been done so far in this session.
- **In-progress files**: Which files are being actively modified and their current state.
- **Key decisions**: Important decisions made during the session and their rationale.
- **Blockers and next steps**: What is blocking progress and what should be done next.
- **Active skills**: Which Quiver skills were loaded and their current state.
- **Handover reference**: If a handover exists at .claude/handovers/, reference the most recent one.

This context ensures that Quiver sessions can be resumed seamlessly across compactions.`)
    },

    "tool.execute.before": async (input, output) => {
      if (input.tool === "question") {
        return
      }
    },

    "session.created": async (input, output) => {
      await ctx.client.app.log({
        body: {
          service: "quiver",
          level: "debug",
          message: "Session created",
          extra: { sessionId: input.session.id },
        },
      })
    },
  }
}

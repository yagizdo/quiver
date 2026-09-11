/**
 * Quiver plugin for OpenCode.ai
 *
 * Injects Quiver bootstrap context (.opencode/bootstrap.md) via message transform.
 * Registers the skills directory and the context7 MCP server via the config hook,
 * so a user needs no opencode.json entry of their own.
 *
 * install.sh symlinks this file into ~/.config/opencode/plugins/. Node and Bun
 * resolve import.meta.url through symlinks to the real path, so the
 * path.resolve(__dirname, '../../skills') below lands back in the clone.
 */

import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const quiverSkillsDir = path.resolve(__dirname, '../../skills');
const bootstrapPath = path.join(__dirname, '..', 'bootstrap.md');

// Module-level cache for bootstrap content.
// bootstrap.md does not change during a session, so reading it once eliminates
// redundant fs.existsSync + fs.readFileSync work on every agent step.
// The file carries no frontmatter, so there is nothing to strip.
let _bootstrapCache = undefined; // undefined = not yet loaded, null = file missing

export const QuiverPlugin = async ({ client }) => {
  // Helper to generate bootstrap content (cached after first call)
  const getBootstrapContent = () => {
    // Return cached result on subsequent calls
    if (_bootstrapCache !== undefined) return _bootstrapCache;

    // Try to load the OpenCode bootstrap
    if (!fs.existsSync(bootstrapPath)) {
      _bootstrapCache = null;
      return null;
    }

    const content = fs.readFileSync(bootstrapPath, 'utf8');

    _bootstrapCache = `<EXTREMELY_IMPORTANT>
You have Quiver.

**IMPORTANT: The Quiver OpenCode bootstrap is included below. It is ALREADY LOADED - you are currently following it. Do NOT use the skill tool to load it again - it is not a skill.**

${content}
</EXTREMELY_IMPORTANT>`;

    return _bootstrapCache;
  };

  await client.app.log({
    body: { service: "quiver", level: "info", message: "Quiver plugin initialized" },
  });

  return {
    // Register skills directory so OpenCode discovers Quiver skills
    // without requiring manual symlinks or config file edits.
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(quiverSkillsDir)) {
        config.skills.paths.push(quiverSkillsDir);
      }

      // Register context7 so documentation lookups work with no user config file.
      // This replaces .opencode/opencode.json, which OpenCode only ever read when
      // the working directory was the Quiver clone itself -- inside a user's own
      // project it was never loaded. A user-declared context7 entry wins.
      config.mcp = config.mcp || {};
      config.mcp.context7 = config.mcp.context7 || {
        type: 'remote',
        url: 'https://mcp.context7.com/mcp',
      };
    },

    // Inject bootstrap into the first user message of each session.
    // Using a user message instead of a system message avoids token bloat
    // from system messages repeated every turn.
    //
    // The hook fires on every agent step (not just every turn) because
    // OpenCode reloads messages from DB each step. Fresh message arrays
    // may need injection again, so getBootstrapContent() must not do
    // repeated disk work.
    'experimental.chat.messages.transform': async (_input, output) => {
      const bootstrap = getBootstrapContent();
      if (!bootstrap || !output.messages.length) return;
      const firstUser = output.messages.find(m => m.info.role === 'user');
      if (!firstUser || !firstUser.parts.length) return;

      // Guard: skip if first user message already contains bootstrap.
      // Prevents double injection when OpenCode passes an already
      // transformed in-memory message array through the hook again.
      if (firstUser.parts.some(p => p.type === 'text' && p.text.includes('EXTREMELY_IMPORTANT'))) return;

      firstUser.parts.unshift({ type: 'text', text: bootstrap });
    },

    // Preserve Quiver-specific state across session compactions.
    'experimental.session.compacting': async (_input, output) => {
      output.context.push(`## Quiver Handover Context
When generating a continuation summary for this session, include the following Quiver-specific state:

- **Current branch and task**: What branch you are on and what task/feature you are working on.
- **Completed work**: What has been done so far in this session.
- **In-progress files**: Which files are being actively modified and their current state.
- **Key decisions**: Important decisions made during the session and their rationale.
- **Blockers and next steps**: What is blocking progress and what should be done next.
- **Active skills**: Which Quiver skills were loaded and their current state.
- **Handover reference**: If a handover exists at .claude/handovers/, reference the most recent one.

This context ensures that Quiver sessions can be resumed seamlessly across compactions.`);
    },

    // Block the question tool to prevent infinite loops. OpenCode's plugin API
// requires `throw` for cancellation; a bare `return` is a no-op.
    'tool.execute.before': async (input, _output) => {
      if (input.tool === 'question') {
        throw new Error('Quiver: question tool disabled to prevent infinite loops');
      }
    },

    'event': async ({ event }) => {
      if (event.type === 'session.created') {
        await client.app.log({
          body: {
            service: "quiver",
            level: "debug",
            message: "Session created",
            extra: { sessionId: event.properties.sessionID },
          },
        });
      }
    },
  };
};

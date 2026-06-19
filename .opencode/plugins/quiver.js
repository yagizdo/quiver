/**
 * Quiver plugin for OpenCode.ai
 *
 * Injects Quiver bootstrap context via message transform.
 * Auto-registers skills directory via config hook (no symlinks needed).
 */

import path from 'path';
import fs from 'fs';
import os from 'os';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const quiverSkillsDir = path.resolve(__dirname, '../../skills');
const usingQuiverPath = path.join(quiverSkillsDir, 'using-quiver', 'SKILL.md');

// Module-level cache for bootstrap content.
// The SKILL.md file does not change during a session, so reading + parsing it
// once eliminates redundant fs.existsSync + fs.readFileSync + regex work on
// every agent step.
let _bootstrapCache = undefined; // undefined = not yet loaded, null = file missing

// Simple frontmatter extraction (avoid dependency on skills-core for bootstrap)
const extractAndStripFrontmatter = (content) => {
  const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return { content };

  const frontmatterStr = match[1];
  const body = match[2];
  const frontmatter = {};

  for (const line of frontmatterStr.split('\n')) {
    const colonIdx = line.indexOf(':');
    if (colonIdx > 0) {
      const key = line.slice(0, colonIdx).trim();
      const value = line.slice(colonIdx + 1).trim().replace(/^["']|["']$/g, '');
      frontmatter[key] = value;
    }
  }

  return { frontmatter, content: body };
};

// Normalize a path: trim whitespace, expand ~, resolve to absolute
const normalizePath = (p, homeDir) => {
  if (!p || typeof p !== 'string') return null;
  let normalized = p.trim();
  if (!normalized) return null;
  if (normalized.startsWith('~/')) {
    normalized = path.join(homeDir, normalized.slice(2));
  } else if (normalized === '~') {
    normalized = homeDir;
  }
  return path.resolve(normalized);
};

export const QuiverPlugin = async ({ client, directory }) => {
  const homeDir = os.homedir();
  const envConfigDir = normalizePath(process.env.OPENCODE_CONFIG_DIR, homeDir);
  const configDir = envConfigDir || path.join(homeDir, '.config/opencode');

  // Helper to generate bootstrap content (cached after first call)
  const getBootstrapContent = () => {
    // Return cached result on subsequent calls
    if (_bootstrapCache !== undefined) return _bootstrapCache;

    // Try to load using-quiver skill
    if (!fs.existsSync(usingQuiverPath)) {
      _bootstrapCache = null;
      return null;
    }

    const fullContent = fs.readFileSync(usingQuiverPath, 'utf8');
    const { content } = extractAndStripFrontmatter(fullContent);

    const toolMapping = `**Tool Mapping for OpenCode:**
When Quiver skills request actions, substitute OpenCode equivalents:
- Create or update todos -> \`todowrite\`
- \`Subagent (general-purpose):\` -> \`task\` with \`subagent_type: "general"\` (or specific Quiver subagent)
- Invoke a skill -> OpenCode's native \`skill\` tool
- Read files -> \`read\`
- Create, edit, or delete files -> \`apply_patch\`
- Run shell commands -> \`bash\`
- Search files -> \`grep\`, \`glob\`
- Fetch a URL -> \`webfetch\`

Use OpenCode's native \`skill\` tool to list and load Quiver skills.`;

    _bootstrapCache = `<EXTREMELY_IMPORTANT>
You have Quiver.

**IMPORTANT: The using-quiver skill content is included below. It is ALREADY LOADED - you are currently following it. Do NOT use the skill tool to load "using-quiver" again - that would be redundant.**

${content}

${toolMapping}
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

      const ref = firstUser.parts[0];
      firstUser.parts.unshift({ ...ref, type: 'text', text: bootstrap });
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

    // Short-circuit the question tool to prevent infinite loops.
    'tool.execute.before': async (input, _output) => {
      if (input.tool === 'question') {
        return;
      }
    },

    'session.created': async (input, _output) => {
      await client.app.log({
        body: {
          service: "quiver",
          level: "debug",
          message: "Session created",
          extra: { sessionId: input.session.id },
        },
      });
    },
  };
};

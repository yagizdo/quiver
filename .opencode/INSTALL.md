# Installing Quiver for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed

## Installation

Add quiver to the `plugin` array in your `opencode.json` (global or project-level):

```json
{
  "plugin": ["quiver@git+https://github.com/yagizdo/quiver.git"]
}
```

Restart OpenCode. The plugin installs through OpenCode's plugin manager and
registers all skills automatically.

Verify by asking: "Tell me about your Quiver skills"

OpenCode uses its own plugin install. If you also use Claude Code, Codex, or
another harness, install Quiver separately for each one.

## Migrating from the old setup script

If you previously installed Quiver using `setup-opencode.sh`, remove the old setup:

```bash
# Remove generated Quiver files from your project's .opencode directory
rm -f /path/to/your/project/.opencode/opencode.json
rm -rf /path/to/your/project/.opencode/agents
rm -rf /path/to/your/project/.opencode/skills
rm -rf /path/to/your/project/.opencode/commands
rm -rf /path/to/your/project/.opencode/plugins
rm -rf /path/to/your/project/.opencode/rules
```

Then follow the installation steps above.

## Usage

Use OpenCode's native `skill` tool:

```
use skill tool to list skills
use skill tool to load brainstorm
```

Quiver provides 20 specialist agents, 19+1 skills (including the auto-loaded `using-quiver` meta-skill), and 16 slash commands.

## Updating

To pin a specific version:

```json
{
  "plugin": ["quiver@git+https://github.com/yagizdo/quiver.git#v1.13.0"]
}
```

OpenCode installs Quiver through a git-backed package spec. Some OpenCode
and Bun versions pin that resolved git dependency in a lockfile or cache, so a
restart may not pick up the newest Quiver commit. If updates do not appear,
clear OpenCode's package cache or reinstall the plugin.

## Troubleshooting

### Plugin not loading

1. Check logs: `opencode run --print-logs "hello" 2>&1 | grep -i quiver`
2. Verify the plugin line in your `opencode.json`
3. Make sure you're running a recent version of OpenCode

### Windows install issues

Some Windows OpenCode builds have upstream installer issues with git-backed
plugin specs, including cache paths for `git+https` URLs and Bun not finding
`git.exe` even when it works in a normal terminal. If OpenCode cannot install
the plugin, try installing with system npm and pointing OpenCode at the local
package:

```powershell
npm install quiver@git+https://github.com/yagizdo/quiver.git --prefix "$HOME\.config\opencode"
```

Then use the installed package path in `opencode.json`:

```json
{
  "plugin": ["~/.config/opencode/node_modules/quiver"]
}
```

### Skills not found

1. Use `skill` tool to list what's discovered
2. Check that the plugin is loading (see above)
3. The bootstrap content from `using-quiver/SKILL.md` is auto-injected, not loaded via the `skill` tool

### Note on experimental hooks

Quiver's plugin uses `experimental.chat.messages.transform` to inject the
`using-quiver` bootstrap into the first user message of every session. The
`experimental.` prefix means this hook is under active development in
OpenCode and may change. If a future OpenCode version breaks this hook:

- The plugin will still load and register the skills directory.
- The `using-quiver` bootstrap will not be injected.
- Skills will still be discoverable via the `skill` tool, but agents will
  not auto-invoke them. Users can still type `/brainstorm`, `/plan`, etc.

Pin OpenCode to a version that supports this hook if you depend on auto-activation.

## Getting Help

- Report issues: https://github.com/yagizdo/quiver/issues
- Full documentation: [README.md](README.md)
- OpenCode docs: https://opencode.ai/docs/

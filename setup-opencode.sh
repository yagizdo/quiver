#!/usr/bin/env bash
set -euo pipefail

# Quiver OpenCode Setup
# Copies Quiver agents, skills, commands, and plugin to a target project's .opencode/ directory.
#
# Usage:
#   ./setup-opencode.sh /path/to/project
#   Q=~/.claude/plugins/quiver .opencode/setup-opencode.sh /path/to/project
#
# The script detects the Quiver root by checking, in order:
#   1. $Q environment variable
#   2. Claude Code plugin dir (~/.claude/plugins/quiver)
#   3. The script's own location (if run from within the quiver repo)

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "Usage: setup-opencode.sh /path/to/project"
  exit 1
fi

if [ ! -d "$TARGET" ]; then
  echo "Error: target directory '$TARGET' does not exist"
  exit 1
fi

# Detect Quiver root
if [ -n "${Q:-}" ] && [ -d "$Q/.opencode" ]; then
  QUIVER_ROOT="$Q"
elif [ -d "$HOME/.claude/plugins/quiver/.opencode" ]; then
  QUIVER_ROOT="$HOME/.claude/plugins/quiver"
else
  QUIVER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

echo "Quiver root: $QUIVER_ROOT"
echo "Target:      $TARGET"
echo ""

# Create target .opencode directory
mkdir -p "$TARGET/.opencode/agents"
mkdir -p "$TARGET/.opencode/skills"
mkdir -p "$TARGET/.opencode/commands"
mkdir -p "$TARGET/.opencode/plugins"
mkdir -p "$TARGET/.opencode/rules"

# Copy agents
echo "Copying agents..."
cp "$QUIVER_ROOT/.opencode/agents/"*.md "$TARGET/.opencode/agents/" 2>/dev/null || echo "  (no agent files found)"

# Symlink skills
echo "Linking skills..."
for skill_dir in "$QUIVER_ROOT/.opencode/skills/"*/; do
  if [ -d "$skill_dir" ]; then
    name=$(basename "$skill_dir")
    target_link="$TARGET/.opencode/skills/$name"
    if [ -L "$target_link" ]; then
      rm "$target_link"
    fi
    ln -sf "$skill_dir" "$target_link"
    echo "  $name"
  fi
done

# Copy commands
echo "Copying commands..."
cp "$QUIVER_ROOT/.opencode/commands/"*.md "$TARGET/.opencode/commands/" 2>/dev/null || echo "  (no command files found)"

# Copy plugin
echo "Copying plugin..."
cp "$QUIVER_ROOT/.opencode/plugins/"*.ts "$TARGET/.opencode/plugins/" 2>/dev/null || echo "  (no plugin files found)"

# Copy rules
echo "Copying rules..."
cp "$QUIVER_ROOT/.opencode/rules/"*.md "$TARGET/.opencode/rules/" 2>/dev/null || echo "  (no rule files found)"

# Handle opencode.json
echo ""
if [ -f "$TARGET/.opencode/opencode.json" ]; then
  echo "opencode.json already exists at target. Appending Quiver MCP config..."
  echo "  (manually add '\"plugin\": [\"./.opencode/plugins/quiver.ts\"]' if not present)"
else
  cat > "$TARGET/.opencode/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "./.opencode/plugins/quiver.ts"
  ],
  "mcp": {
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp"
    }
  }
}
EOF
  echo "Created opencode.json with Quiver plugin and context7 MCP."
fi

# Handle package.json
if [ -f "$TARGET/.opencode/package.json" ]; then
  echo "package.json already exists at target. Ensure @opencode-ai/plugin is listed."
else
  cat > "$TARGET/.opencode/package.json" <<'EOF'
{
  "dependencies": {
    "@opencode-ai/plugin": "1.16.2"
  }
}
EOF
  echo "Created package.json with @opencode-ai/plugin dependency."
fi

echo ""
echo "Quiver OpenCode setup complete!"
echo "Run 'opencode' in $TARGET to use Quiver agents, skills, and commands."

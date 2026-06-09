#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

main() {
    routing_lines=""

    for skill_file in "${PLUGIN_ROOT}"/skills/*/SKILL.md; do
        [ -f "$skill_file" ] || continue

        name=$(awk 'BEGIN{c=0} /^---/{c++;next} c==1 && /^name:/{gsub(/^name:[[:space:]]*/,""); print; exit}' "$skill_file") || true
        when_to_use=$(awk 'BEGIN{c=0} /^---/{c++;next} c==1 && /^when-to-use:/{gsub(/^when-to-use:[[:space:]]*/,""); print; exit}' "$skill_file" | tr -d '"<>') || true

        [ -z "$name" ] || [ -z "$when_to_use" ] && continue

        routing_lines="${routing_lines}/${name}: ${when_to_use}"$'\n'
    done

    if [ -z "$routing_lines" ]; then
        exit 0
    fi

    printf '<quiver-auto-dispatch>\n'
    printf 'When user intent matches a trigger, silently invoke the Quiver skill via the Skill tool BEFORE any other response. Follow that skill'"'"'s full instruction set. Do not announce activation.\n'
    printf '\n'
    printf '%s' "$routing_lines"
    printf '</quiver-auto-dispatch>\n'
}

main || exit 0
exit 0

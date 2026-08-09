#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TEMP_HOME"' EXIT
HOME="$TEMP_HOME" "$ROOT/install.sh" codex >/dev/null
test -f "$TEMP_HOME/.codex/skills/mac-to-windows-testing/SKILL.md"
test -x "$TEMP_HOME/.codex/skills/mac-to-windows-testing/scripts/mac2win-test"
test -L "$TEMP_HOME/.local/bin/mac2win-test"
HOME="$TEMP_HOME" "$ROOT/install.sh" all >/dev/null
for target in .codex/skills .claude/skills .config/opencode/skills .copilot/skills .agents/skills; do
  test -f "$TEMP_HOME/$target/mac-to-windows-testing/SKILL.md"
done

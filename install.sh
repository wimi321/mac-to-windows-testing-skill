#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$ROOT/skills/mac-to-windows-testing"
TARGET="${1:-all}"

if [[ ! -f "$SOURCE/SKILL.md" ]]; then
  printf 'Skill source is incomplete: %s\n' "$SOURCE" >&2
  exit 2
fi

destinations() {
  case "$TARGET" in
    codex) printf '%s\n' "$HOME/.codex/skills/mac-to-windows-testing" ;;
    claude) printf '%s\n' "$HOME/.claude/skills/mac-to-windows-testing" ;;
    opencode) printf '%s\n' "$HOME/.config/opencode/skills/mac-to-windows-testing" ;;
    copilot) printf '%s\n' "$HOME/.copilot/skills/mac-to-windows-testing" ;;
    agents) printf '%s\n' "$HOME/.agents/skills/mac-to-windows-testing" ;;
    all)
      printf '%s\n' \
        "$HOME/.codex/skills/mac-to-windows-testing" \
        "$HOME/.claude/skills/mac-to-windows-testing" \
        "$HOME/.config/opencode/skills/mac-to-windows-testing" \
        "$HOME/.copilot/skills/mac-to-windows-testing" \
        "$HOME/.agents/skills/mac-to-windows-testing"
      ;;
    *)
      printf 'Unknown target: %s (use all, codex, claude, opencode, copilot, or agents)\n' "$TARGET" >&2
      exit 2
      ;;
  esac
}

install_one() {
  local destination="$1"
  local parent temp backup
  parent="$(dirname "$destination")"
  temp="$parent/.mac-to-windows-testing.tmp.$$"
  backup="$parent/.mac-to-windows-testing.backup.$$"
  mkdir -p "$parent"
  cp -R "$SOURCE" "$temp"
  if [[ -e "$destination" ]]; then
    mv "$destination" "$backup"
  fi
  if mv "$temp" "$destination"; then
    rm -rf "$backup"
  else
    [[ ! -e "$destination" && -e "$backup" ]] && mv "$backup" "$destination"
    rm -rf "$temp"
    return 1
  fi
  chmod +x "$destination/scripts/mac2win-test" "$destination/scripts/mac2win_test.py"
  printf 'Installed: %s\n' "$destination"
}

while IFS= read -r destination; do
  install_one "$destination"
  cli_target="$destination/scripts/mac2win-test"
done < <(destinations)

mkdir -p "$HOME/.local/bin"
ln -sfn "$cli_target" "$HOME/.local/bin/mac2win-test"
printf 'CLI: %s\n' "$HOME/.local/bin/mac2win-test"

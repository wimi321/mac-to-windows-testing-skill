# Contributing

Thank you for helping make real Windows validation easier for every desktop-app team.

## Development

1. Fork the repository and create a focused branch.
2. Keep the canonical skill concise. Put transport or platform detail in `references/`.
3. Add tests for every parser, status, redaction, runner, or report change.
4. Run `./tests/run_tests.sh` before opening a pull request.
5. Include sanitized evidence for Windows UI changes. Never attach credentials, device IDs, private source, or personal paths.

## Pull Requests

- Explain the user problem and the observable behavior change.
- State which paths were tested: macOS controller, Windows runner, transport, UI Automation, and visual review.
- Report `PASS`, `FAIL`, or `BLOCKED`; do not turn missing evidence into a pass.
- Do not add background services, public listeners, telemetry, or unsigned executables.

## Compatibility

The project follows the open Agent Skills directory format. Changes must preserve the canonical `SKILL.md` workflow for Codex, Claude Code, OpenCode, and GitHub Copilot unless the pull request clearly documents an unavoidable client-specific extension.

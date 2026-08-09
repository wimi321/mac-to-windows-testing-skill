<div align="center">

# Mac-to-Windows Testing Skill

**Let an AI on your Mac build, operate, inspect, repair, and retest a desktop app on a real Windows PC.**

[简体中文](README.zh-CN.md) · [Quick start](#60-second-start) · [Safety](#safe-by-default) · [Configuration](skills/mac-to-windows-testing/references/CONFIGURATION.md)

[![CI](https://github.com/wimi321/mac-to-windows-testing-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/wimi321/mac-to-windows-testing-skill/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/wimi321/mac-to-windows-testing-skill)](https://github.com/wimi321/mac-to-windows-testing-skill/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-20242A.svg)](LICENSE)
[![Evidence first](https://img.shields.io/badge/verdict-PASS%20%7C%20FAIL%20%7C%20BLOCKED-2563EB.svg)](#the-pass-contract)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/hero-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="assets/hero-light.svg">
  <img alt="Mac-to-Windows Testing Skill: Mac AI controller, secure transport, and real Windows native evidence" src="assets/hero-light.svg" width="100%">
</picture>

</div>

## The problem it solves

A macOS developer can compile a Windows artifact in CI and still miss the defects users actually see: a bundled JVM that will not launch, a 150% DPI dialog with clipped text, a popup behind its owner, a GPU path that only fails on the real card, or a button that exists but does nothing.

This skill gives Codex, Claude Code, OpenCode, or GitHub Copilot a repeatable bridge to an **unlocked, interactive, real Windows desktop**. After one-time device authorization, the agent can run the acceptance loop without asking a person to visually approve each screen.

```text
Mac source + AI
  -> trusted manifest
  -> SSH / WinRM / UU + Computer Use / Windows-side AI
  -> interactive Windows runner
  -> native screenshot + UI Automation tree + logs + environment
  -> AI visual verdict
  -> focused repair -> failed scenario -> full regression
```

The result is always `PASS`, `FAIL`, or `BLOCKED`. Missing evidence never becomes a qualified pass.

<div align="center">
  <img src="assets/demo.gif" alt="Real Windows fixture run: defects detected, safe settings exploration, and a clean PASS regression" width="880">
  <br>
  <sub>Real Windows evidence at 150% scaling: intentional defects fail, safe exploration cleans up its window, and the repaired fixture passes.</sub>
</div>

## 60-second start

Install the skill for one agent:

```bash
git clone https://github.com/wimi321/mac-to-windows-testing-skill.git
cd mac-to-windows-testing-skill
./install.sh codex       # claude | opencode | copilot | agents | all
```

The installer links the CLI to `~/.local/bin/mac2win-test`; add `~/.local/bin` to `PATH` if your shell does not already include it.

Inside the project you want to test:

```bash
mac2win-test init
# Fill in verified Windows build, test, launch and UI scenarios.
mac2win-test doctor --transport ssh --host windows-lab
mac2win-test runner install --transport ssh --host windows-lab
mac2win-test runner trust --transport ssh --host windows-lab
mac2win-test run --transport ssh --host windows-lab
```

The first Windows login, remote-device authorization, SSH/WinRM setup, and profile trust are one-time human actions. Routine tests and evidence review are agent-owned.

## What the AI checks

| Layer | Evidence and checks |
|---|---|
| Build | Verified project command, packaged artifact, exit code, stdout and stderr |
| Desktop | Unlocked interactive session, Windows version, DPI, monitors, GPU, driver and process health |
| Structure | UI Automation control tree, accessible names, bounds, focus, enabled and off-screen state |
| Interaction | Click, selection, text input, keyboard shortcuts and declared state transitions |
| Geometry | Missing controls, overlap, clipping risk, child bounds, abnormal blank regions and owner hierarchy |
| Visual | Native Windows PNGs checked for text clipping, alignment, contrast, broken icons, stale loading and wrong z-order |

Safe exploration is conservative by design: it automatically tries only recognized navigation, tabs, menus, settings, details and about controls. Unknown actions and anything resembling payment, deletion, publishing, uninstall or reset are skipped.

If a visual model is unavailable, the verdict is `BLOCKED_VISION_UNAVAILABLE`. If the desktop is locked, it is `BLOCKED_DESKTOP_LOCKED`. The tool never falls back to “looks fine” from a terminal log.

## Supported routes

| Route | Commands | Native UI | Best fit |
|---|---:|---:|---|
| SSH + interactive runner | Yes | Yes | Default for personal Windows test PCs |
| Existing WinRM + interactive runner | Yes | Yes | Managed Windows environments |
| UU Remote + Computer Use | Through the visible session | Yes | No additional inbound port |
| Windows-side AI agent | Local | Yes | When no Mac-to-Windows shell exists |

UU CLI discovers devices, starts connections, and opens a remote terminal. It is not treated as a generic command or file-transfer API. Without Computer Use, SSH, WinRM, or a Windows-side vision-capable agent, the correct result is `BLOCKED_AUTOMATION_CHANNEL`.

## Designed for desktop frameworks

Ready-to-adapt profiles live in [`examples/`](examples/):

- LizzieYzy Next: a real large Swing application with dynamic title matching and interaction-graph discovery.
- Java Swing: direct Java Access Bridge control trees, bundled JVM, modal ownership, menus, EDT response, fonts and DPI.
- Electron: first paint, renderer/GPU health, native dialogs and packaged resources.
- Tauri: WebView2, native commands, file dialogs, decorations and updater paths.
- .NET: WinForms/WPF scaling, runtime architecture, accessibility and self-contained publishing.
- Generic Windows apps: stable accessible selectors plus native evidence checkpoints.

## The pass contract

`PASS` requires all of these:

1. The declared build and tests pass.
2. The packaged application launches and remains responsive on Windows.
3. Every required scenario completes.
4. Deterministic UI assertions pass.
5. Every passed scenario has an explicitly reviewed native PNG and its matching declared UI tree.
6. AI visual review passes at or above the configured confidence threshold.
7. Evidence is sanitized before publication.
8. A repair is followed by a tracked focused retest and a separate full regression.

The controller enforces this contract while merging deterministic and visual results. A high-confidence AI answer without native evidence is downgraded to `BLOCKED_EVIDENCE_MISSING`.

## Evidence, not anecdotes

Each run is self-contained:

```text
.mac-to-windows-testing/runs/<run-id>/
  manifest.json
  environment.json
  result.json
  ai-review.json
  report.md
  logs/
  screenshots/
  ui-trees/
```

The repository includes a reproducible WinForms fixture with intentional clipping, overlap, off-screen placement, disabled controls, missing click response, and abnormal blank content. The companion clean mode verifies that repairs do not create false positives. CI validates the controller, schemas, installers and PowerShell syntax; **CI is deliberately not presented as real desktop acceptance**.

On the bundled six-defect fixture benchmark, the real Windows run detected all six expected defects with no unexpected finding, then passed the clean regression. This is a reproducible fixture result, not a claim of universal visual-model accuracy. See the [sanitized evidence report](examples/reports/windows-fixture-150-percent.md).

## Safe by default

- The runner uses the current Windows user and an interactive scheduled task, not a system service.
- It opens no port and requires no administrator privilege.
- Profiles are SHA-256 trusted before their commands can execute.
- Payment, publish, uninstall, delete, reset and similarly dangerous controls are denied by default.
- Profiles must not contain passwords, tokens, private addresses or device credentials.
- Repair loops may edit only the selected worktree and stop after the configured limit.
- The tool never pushes, merges, releases, pays, or removes software unless the user separately asks and the workflow explicitly authorizes it.

Read the full [threat model](skills/mac-to-windows-testing/references/SECURITY.md) before registering a new project.

## Validate this repository

```bash
./tests/run_tests.sh
python3 scripts/validate_repository.py
```

On Windows:

```powershell
.\tests\Test-PowerShell.ps1
```

These checks prove repository integrity. A real UI verdict still requires an unlocked Windows machine.

## Contributing

Framework profiles, safer selectors, deterministic layout checks, transport hardening, and sanitized real-world reports are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and the [Code of Conduct](CODE_OF_CONDUCT.md).

Released under the [MIT License](LICENSE).

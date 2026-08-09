---
name: mac-to-windows-testing
description: Automatically validate a Mac-developed desktop project on a real Windows PC. Use when a user asks to test, reproduce, inspect, or fix Windows-only launch, installer, GPU, DPI, Swing, Electron, Tauri, .NET, menu, dialog, focus, clipping, or visual bugs from a Mac; when UU Remote, SSH, WinRM, or a Windows-side AI agent is available; or when evidence-backed PASS, FAIL, or BLOCKED results are required instead of CI-only claims.
---

# Mac-to-Windows Testing

Run an evidence-first loop from the current Mac checkout to a real, interactive Windows desktop. Do not substitute GitHub-hosted CI, a process-survival check, or a remote terminal for visible Windows UI validation.

## Non-negotiable rules

1. Confirm the exact source repository, branch, commit, dirty files, build artifact, Windows target, and transport before testing.
2. Keep the Windows test account logged in and unlocked. A terminal session is not the interactive desktop.
3. Return only `PASS`, `FAIL`, or `BLOCKED`. Missing screenshots, missing vision, a locked desktop, or an uncertain result is `BLOCKED`.
4. Never ask a person to visually approve the run. Gather more evidence automatically up to three times, then block if still uncertain.
5. Do not save credentials, tokens, device IDs, private IPs, or unredacted personal paths in project files or reports.
6. Do not execute payment, publish, uninstall, delete, reset, or account actions unless a trusted profile explicitly enables them with disposable fixture data.
7. Do not push, merge, release, or modify unrelated files as part of the repair loop unless the user explicitly asks.

## Start here

Resolve this skill directory as `SKILL_DIR`, then use its scripts:

```bash
python3 "$SKILL_DIR/scripts/mac2win_test.py" doctor --json
python3 "$SKILL_DIR/scripts/mac2win_test.py" init --project-root "$PWD"
```

Read these references only when needed:

- Connection choice and setup: `references/TRANSPORTS.md`
- Profile and result contracts: `references/CONFIGURATION.md`
- Windows UI runner behavior: `references/UI-AUTOMATION.md`
- Threat model and trust rules: `references/SECURITY.md`
- Framework profiles: `references/FRAMEWORKS.md`

## Workflow

### 1. Ground the run

- Run `git status --short`, `git remote -v`, `git branch --show-current`, and `git rev-parse HEAD` in the real source checkout.
- Identify the Windows artifact and the commands that build, test, package, and launch it.
- Reuse `mac-to-windows-testing.yaml` when present. Otherwise generate it with `init` and fill only verified commands.
- Use a dedicated Windows worktree or disposable checkout. Never run upgrade or cleanup smoke tests against a daily-use profile.

### 2. Select an automation channel

Use the first viable option:

1. `ssh`: preferred for deterministic command execution and evidence transfer.
2. `winrm`: use only when PowerShell remoting is already configured.
3. `uu-computer-use`: use when the current agent can control the UU Remote window visually.
4. `windows-agent`: hand the generated manifest to a vision-capable Codex, Claude Code, OpenCode, or Copilot session on Windows.

UU CLI can discover and connect devices or open a terminal; do not assume it is a general remote command or file-transfer API. If no automation channel can trigger the interactive runner and return evidence, report `BLOCKED_AUTOMATION_CHANNEL`.

### 3. Run deterministic checks

Compile the profile to a run manifest and execute the Windows runner. It must:

- collect OS, architecture, display, DPI, GPU, driver, session, process, and runtime facts;
- run trusted build and test commands;
- launch the packaged Windows application in the interactive session;
- execute declared UI actions by accessible name and control type;
- capture native Windows screenshots and UI Automation trees at checkpoints;
- assert control existence, enabled state, focus, containment, overlap, modal ownership, and response;
- write `result.json` even when setup or a scenario fails.

### 4. Perform AI visual review

Inspect every accepted PNG with the current agent's image tool. Compare the screenshot with its UI tree and scenario intent. Check for clipping, overlap, off-screen content, broken icons, empty regions, unreadable contrast, wrong z-order, stale loading states, and unexpected dialogs.

Write `ai-review.json` using `assets/ai-review.schema.json`. Every finding needs a screenshot, severity, concise evidence, and confidence. If confidence is below `0.85`, capture a window crop, full-screen image, and fresh tree, then retry. After three attempts, return `BLOCKED_VISUAL_UNCERTAIN`.

Finalize the result:

```bash
python3 "$SKILL_DIR/scripts/mac2win_test.py" finalize \
  --result <run>/result.json \
  --review <run>/ai-review.json
python3 "$SKILL_DIR/scripts/mac2win_test.py" report --run-dir <run>
```

### 5. Repair and retest

- For `FAIL`, create a minimal reproduction from the evidence and modify only the source checkout.
- Rerun the failed scenario first.
- When focused validation passes, rerun the full declared suite.
- Repeat at most three repair rounds. If the same blocker persists, return `BLOCKED_REPAIR_LIMIT` with the exact remaining evidence.

## Pass contract

`PASS` requires all of the following:

- build and declared tests passed;
- the packaged app launched on Windows and stayed healthy;
- every required scenario completed;
- deterministic UI assertions passed;
- AI visual review passed at confidence `>= 0.85`;
- required logs, native screenshots, UI trees, and environment metadata exist;
- evidence redaction passed;
- a focused repair, when made, was followed by full regression.

Anything less is `FAIL` or `BLOCKED`, never a qualified pass.

## Completion response

Report the Windows environment, source commit, transport, scenarios, final status, repair rounds, evidence directory, and all blockers. Keep claims bounded to what the evidence proves.

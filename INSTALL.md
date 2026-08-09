# Installation

## macOS / Linux controller

Unpack the release archive, then install for one client or all supported clients:

```bash
./install.sh codex
./install.sh all
```

Supported target names are `codex`, `claude`, `opencode`, `copilot`, `agents`, and `all`. The installer copies the canonical skill atomically and links `mac2win-test` into `~/.local/bin`.

## PowerShell installer

```powershell
.\install.ps1 -Target codex
```

The PowerShell installer supports the same target names. It is useful for Windows-side AI agents; the normal controller still runs on the Mac.

## Verify the archive

```bash
shasum -a 256 -c SHA256SUMS
```

## One-time Windows runner setup

After configuring an SSH alias or existing WinRM endpoint:

```bash
mac2win-test runner install --transport ssh --host windows-lab
mac2win-test runner trust --transport ssh --host windows-lab --config mac-to-windows-testing.yaml
```

The Windows test user must remain signed in with an unlocked desktop. No background service, public listener, or administrator privilege is required.

# Transport Selection

## Decision table

| Transport | Command channel | Native evidence transfer | Interactive UI | Best use |
|---|---:|---:|---:|---|
| SSH/SCP | Yes | Yes | Through runner task | Default deterministic path |
| WinRM | Yes | Scripted | Through runner task | Managed Windows environments |
| UU + Computer Use | Through visible terminal/UI | Through visible UI or a secondary channel | Yes | Zero network configuration |
| Windows-side AI | Local | Local | Yes | Handoff when no remote shell exists |

## UU Remote

Probe the installed CLI instead of hard-coding blog examples:

```bash
/Applications/UURemote.app/Contents/Helpers/uuyc-cli --help
/Applications/UURemote.app/Contents/Helpers/uuyc-cli status
/Applications/UURemote.app/Contents/Helpers/uuyc-cli device list
```

All responses are JSON, but some failure paths may still exit with code `0`. Parse `success` and `error`; never trust the process code alone. The UU desktop app must be running and signed in.

The current CLI opens connections and remote terminals. A vision-capable agent with Computer Use may operate that visible session. Otherwise combine UU for observation with SSH/WinRM or use a Windows-side AI agent.

For `uu-computer-use` and `windows-agent`, `mac2win-test run` compiles the immutable manifest and writes `automation-handoff.json`. This is a ready state for the agent, not a final `BLOCKED` result. The agent must still run the Windows manifest, collect native evidence, write the AI review and finalize the verdict.

## SSH/SCP

Use a standard Windows test account, Ed25519 keys, and LAN-restricted firewall rules. Never expose port 22 directly to the public internet.

Pass PowerShell through stdin when quoting is complex:

```bash
ssh windows-test powershell.exe -NoProfile -ExecutionPolicy Bypass -Command -
```

SSH does not run in the visible desktop. Trigger the installed interactive scheduled task for GUI work.

## WinRM

Use only when the machine is already managed for PowerShell remoting. Do not weaken TrustedHosts, TLS, or firewall rules automatically. If the existing configuration is insufficient, return `BLOCKED_WINRM_CONFIGURATION`.

## Windows-side AI

Copy the compiled manifest and canonical skill to the Windows checkout. The Windows agent must be vision-capable and must follow the same result schemas. Do not accept a prose-only "looks good" response.

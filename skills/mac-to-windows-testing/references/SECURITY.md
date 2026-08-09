# Threat Model

## Trust boundary

The source repository, project profile, Windows account, transports, screenshots, and AI model are separate trust boundaries. A cloned repository may be malicious; do not execute its profile until the command list is explicitly trusted.

## Runner guarantees

- Current-user privileges only.
- No Windows service.
- No inbound network listener.
- No credential collection.
- No arbitrary manifests outside the trusted queue directory.
- Manifest and profile hashes recorded in every result.
- Dangerous UI actions denied unless the profile opts in.
- Local evidence by default.

## Redaction

Before a report leaves the Windows machine, replace usernames, user-profile paths, hostnames, IP addresses, device IDs, bearer tokens, API keys, passwords, cookies, and configured custom patterns. Do not redact raw evidence in place; create a sanitized export and retain raw evidence locally.

## Repair loop

Automated code repair is limited to the selected source worktree. It must not push, merge, publish, purchase, reset configuration, or modify the Windows runner. Stop after three unsuccessful rounds.

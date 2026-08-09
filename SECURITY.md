# Security Policy

## Supported Versions

Security fixes are provided for the latest release and the current `main` branch.

## Reporting

Please use GitHub private vulnerability reporting. Do not post credentials, device IDs, IP addresses, private screenshots, source archives, or remote-session details in a public issue.

## Security Model

- The Windows runner executes as the current standard user.
- It does not install a service or open a network listener.
- Project commands come from an explicitly trusted local profile.
- Destructive actions are denied unless the profile opts in with isolated fixture data.
- Passwords, tokens, and UU credentials are never stored by this project.
- Evidence is local by default and is redacted before a report is shared.
- A locked or non-interactive Windows desktop is `BLOCKED`, never `PASS`.

See `skills/mac-to-windows-testing/references/SECURITY.md` for the detailed threat model.

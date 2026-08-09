## Summary

- Describe the observable user-facing change.

## Evidence

- [ ] `./tests/run_tests.sh`
- [ ] `python3 scripts/validate_repository.py`
- [ ] PowerShell parser checks on Windows
- [ ] Real unlocked Windows UI run, or the PR clearly states why it is not applicable

## Safety

- [ ] No credentials, private addresses, device IDs, or personal paths are included
- [ ] Dangerous actions remain denied by default
- [ ] CI is not presented as real Windows UI acceptance

# Configuration And Evidence Contracts

## Project profile

`mac-to-windows-testing.yaml` is intentionally a small YAML subset: mappings, lists, quoted strings, numbers, booleans, and null. Anchors, tags, aliases, and executable YAML objects are forbidden.

Required sections:

- `version`: schema version, currently `1`.
- `project`: name, repository, Windows workspace, and artifact.
- `commands`: trusted build, test, and launch commands.
- `automation`: transport, repair limit, confidence threshold, and destructive-action policy.
- `scenarios`: safe UI actions and assertions.

Commands are explicit strings executed by the Windows test account. Treat any changed command as a new trust decision. Profiles must not contain secrets.

Targets may use exact `name`, case-insensitive `nameContains`, `nameRegex`, `automationId`, and `controlType`. Prefer stable automation IDs or accessible names. Use `nameContains` for application titles that include a version, document, or engine name; avoid screen coordinates.

Scenario actions include declared clicks, input, shortcuts and assertions plus two automatic actions:

- `audit` checks accessible names, positive bounds, off-screen controls, window containment and actionable sibling overlap. `failOn` selects which finding codes fail the scenario.
- `explore` builds an interaction graph and invokes only classified tabs, navigation, settings, details and top-level menus. Unknown and dangerous controls are never invoked. `maxControls` is limited to `1..50`.

## Run manifest

The controller compiles YAML into immutable JSON containing:

- run ID and creation time;
- source repository, branch, commit, and dirty state;
- resolved Windows paths and commands;
- scenario actions and assertions;
- SHA-256 of the source profile;
- redaction patterns and trust policy.
- repair round, parent run and validation phase (`initial`, `focused`, or `full-regression`).

Use `--repair-round`, `--parent-run-id` and `--phase` when an AI repair starts a follow-up run. A focused pass is not completion-eligible until a full-regression run passes, and the configured repair limit is enforced while compiling the manifest.

## Result states

- `PASS`: all deterministic and visual checks passed.
- `FAIL`: the app or a declared expectation failed with sufficient evidence.
- `BLOCKED`: the environment or available evidence cannot support a verdict.
- `PENDING_AI_REVIEW`: runner completed and screenshots require visual review.

`READY_FOR_WINDOWS_AGENT` may appear only in `automation-handoff.json`. It is an intermediate handoff state, not a test verdict. UU Computer Use and Windows-side AI transports create this handoff instead of prematurely writing a blocked `result.json`.

Common blockers include `BLOCKED_DESKTOP_LOCKED`, `BLOCKED_VISION_UNAVAILABLE`, `BLOCKED_AUTOMATION_CHANNEL`, `BLOCKED_RUNNER_NOT_INSTALLED`, and `BLOCKED_VISUAL_UNCERTAIN`.

## Evidence layout

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

Screenshots and UI trees use matching checkpoint names. A visual finding without a matching screenshot is invalid.

`ai-review.json` must include `reviewedEvidence[]`. Every scenario that would contribute to a final `PASS` needs at least one explicitly reviewed native screenshot and its matching declared UI tree. A global screenshot from another scenario cannot satisfy this requirement.

# Windows fixture acceptance at 150% scaling

This report is a sanitized, reproducible example from the bundled WinForms fixture. It contains no device name, user name, credential, private address, source token, or absolute user path.

## Environment

| Item | Value |
|---|---|
| Operating system | Windows 11, build 22631 |
| Architecture | AMD64 |
| Display | 1920 x 1080, 150% scaling |
| Session | Interactive and unlocked |
| GPU | NVIDIA GeForce RTX 3070 Laptop GPU |
| Runner | Windows PowerShell 5.1 |

## Intentional-defect run

The deterministic runner and AI review returned `FAIL`, as required. All six known defects were identified:

| Defect | Evidence |
|---|---|
| Text clipping | The visible status text ended early while the accessibility tree exposed the complete sentence. |
| Control overlap | Primary and secondary actions occupied intersecting bounds. |
| Off-screen control | The report action extended beyond its owning panel. |
| Unexpected disabled state | The continue action was visible but could not be invoked. |
| Missing response | The declared status transition did not happen after activation. |
| Abnormal blank content | The result panel contained neither content nor an empty-state explanation. |

Fixture score:

- Expected defects: 6
- Detected defects: 6
- Recall: 100%
- Unexpected findings: 0
- False-positive rate: 0%

These figures apply only to the bundled fixture and its declared ground truth.

## Clean regression

The clean mode returned `PASS`. It verified valid geometry, enabled controls, the declared status transition, non-empty evidence content, and safe exploration. The explorer opened `Fixture settings`, captured native evidence, closed the new window, and confirmed that the window was gone before completing.

## Evidence contract

Both runs included native Windows PNG screenshots, UI Automation trees, environment data, process/log evidence, and an explicit visual review. Removing a required screenshot or matching UI tree causes finalization to return `BLOCKED_EVIDENCE_MISSING` rather than `PASS`.

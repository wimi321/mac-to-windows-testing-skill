# LizzieYzy Next real Windows acceptance

This is a sanitized record of the first large-application acceptance completed with Mac-to-Windows Testing Skill. It contains no user name, device name, account, credential, private address, device identifier, or absolute user path. Raw screenshots remain private because the remote-compute screen contained a real test account.

## Scope

| Item | Value |
|---|---|
| Application | [LizzieYzy Next](https://github.com/wimi321/lizzieyzy-next), Java Swing |
| Application change | PR [#245](https://github.com/wimi321/lizzieyzy-next/pull/245), first-start work-area fix |
| Skill commit | `7500138` |
| Operating system | Windows 11, interactive and unlocked |
| Physical desktop | 1920 x 1080 |
| GPU | NVIDIA GeForce RTX 3070 Laptop GPU |
| Connection | UU Remote terminal and visible desktop, interactive Windows runner |
| Run ID | `20260811T013056Z-14af7fa0` |

This run did not claim Windows 10, a multi-monitor matrix, or every DPI scale. Those environments require separate native runs.

## Automated result

| Gate | Result |
|---|---|
| Build | `PASS`, 7.06 seconds |
| Maven tests | `PASS`, 2,162 tests in 95.925 seconds |
| Packaged artifact | `PASS` |
| Application launch | `PASS` |
| Deterministic UI scenarios | `PASS`, 7 of 7 |
| AI visual review | `PASS`, confidence 0.97 |
| Visual findings | 0 |
| Evidence coverage | Complete, 7 of 7 scenarios |
| Release eligibility | `true` |

The seven scenarios covered the main window, KataGo Auto Setup, opening and inspecting Remote Compute, opening and inspecting Strength Evaluation, and safe main-menu navigation. Each passed scenario had a declared native PNG and matching UI tree. The review found no text clipping, control overlap, window overflow, abnormal blank region, stale popup, or incorrect dialog layering.

## Repair loop

The first acceptance passes exposed two real automation and application-edge defects:

- Transient Swing menus could remain open after safe exploration and contaminate later screenshots. The explorer now closes and verifies transient windows before proceeding.
- The application's first-start window could extend beneath the Windows taskbar. PR #245 constrains the default bounds to the available work area.

Focused Windows retests passed before the separate full regression above. The final result contained no `nextRequiredPhase` and set `completionEligible` to `true`.

## Integrity

- Manifest SHA-256: `0e0240aba71263b061322e512b06823443bdba5d6750b3c93e8a73f7faf9ca17`
- Profile SHA-256: `e699d52ca69c7ba7077d9b90b8dd04a0c202d1bf821b2622b7b7372d0c084791`

The checksums identify the private acceptance inputs without publishing account-bearing screenshots. CI was used for repository checks, but it was not substituted for the real interactive Windows verdict.

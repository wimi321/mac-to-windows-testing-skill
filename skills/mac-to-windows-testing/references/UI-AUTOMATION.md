# Windows UI Automation

## Execution boundary

GUI automation must run in the same unlocked interactive session as the target application. The runner is a per-user scheduled task configured with `InteractiveToken`; it is not a Windows service.

## Selectors

Prefer selectors in this order:

1. Automation ID plus control type.
2. Accessible name plus control type.
3. Stable ancestor path plus name.
4. Relative geometry only when the profile labels it fragile.

Do not use fixed screen coordinates as the normal path.

## Java Swing

Windows UI Automation often exposes only the top-level `SunAwtFrame` for Swing applications. The runner therefore enables Java Access Bridge once during runner installation and combines both providers:

- UI Automation remains the primary provider for native, Electron, Tauri, and .NET controls.
- Java Access Bridge walks the Swing accessibility tree by `AccessibleContext`, records the English and localized role/state values, and releases every returned Java object.
- Swing assertions and clicks fall back to accessible name, role, state, and native screen bounds when UI Automation cannot see the child control.
- A Swing root with no Java child tree is `BLOCKED_JAVA_ACCESS_BRIDGE_UNAVAILABLE` or `BLOCKED_JAVA_ACCESS_BRIDGE_NOT_ENABLED`, never a successful empty discovery.

The Windows test account must be logged out and back in, or the Java application must be restarted, after Access Bridge is enabled for the first time.

## Deterministic assertions

- Window and control exist within the deadline.
- Expected controls are enabled, keyboard-focusable, and on screen.
- Actionable sibling controls do not overlap beyond the configured tolerance.
- Child bounds remain inside the owning window client region.
- Modal dialogs are owned by and above the expected parent.
- A click, selection, text change, or shortcut produces the declared state transition.

## Visual review

The AI reviews native screenshots, not a scaled Mac capture of the remote desktop. It checks clipping, ellipsis where full text is required, baseline misalignment, icon damage, blank content, extreme whitespace, unreadable contrast, stale loading, and unexpected windows.

If the screenshot is loading, blank, cropped, obscured, or from the wrong window, reject it and capture again. Use full-screen and window crops when z-order is in doubt.

## Safe crawling

Discovery mode may enumerate and focus controls automatically. It may invoke only controls categorized as navigation, view, settings, tab, expand, collapse, open, cancel, back, or close. Unknown controls are not clicked. Destructive text and automation IDs are denied by default.

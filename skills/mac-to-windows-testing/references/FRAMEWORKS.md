# Framework Profiles

## Java Swing

Capture the packaged launcher rather than only `java -jar`. Check JVM launch health, bundled runtime, font rendering, menu popups, owner/modal relationships, EDT responsiveness, and DPI scaling.

Require a non-empty Java Access Bridge tree for child-control validation. A top-level `SunAwtFrame` alone is insufficient evidence. Restart the Java process after the runner enables Access Bridge, then use accessible names and roles instead of fixed coordinates.

## Electron

Test the packaged executable with development tools disabled. Check first paint, native dialogs, multi-window focus, renderer crashes, GPU-process state, and packaged resource paths.

## Tauri

Test the packaged WebView2 application and confirm the required WebView runtime. Check native menus, file dialogs, command errors, window decorations, scaling, and updater behavior.

## .NET

Test the published artifact, not the IDE launch profile. Check framework-dependent versus self-contained deployment, runtime architecture, WinForms/WPF scaling, accessibility names, and single-file extraction behavior.

## Generic desktop application

At minimum declare one launch command, one healthy-window selector, one screenshot checkpoint, and one close action. Add framework-specific checks only when the repository proves the framework.

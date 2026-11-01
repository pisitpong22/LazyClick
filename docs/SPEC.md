You are a senior macOS engineer specializing in Swift, AppKit, low-level input events, and Apple Magic Mouse multitouch.

Build a COMPLETE, production-quality, ultra-lightweight native macOS menu bar application called "Magic Mouse Tap". Implement the project in the current workspace, not just a design or code snippets.

GOAL
Add touch-based clicks and three-finger drag to Apple's Magic Mouse while preserving its existing behavior. The application must be extremely resource-efficient, responsive, simple and reliable.

REQUIRED GESTURES
1. One-finger quick tap anywhere in the usable touch area -> left mouse click.
2. Two-finger simultaneous quick tap -> right mouse click.
3. Three-finger simultaneous quick tap without movement -> middle mouse click.
4. Three-finger touch + deliberate mouse movement -> hold left mouse button and drag. Continue dragging while the fingers remain on the surface; release when all fingers lift.
5. Physical left/right clicks, mouse movement, scrolling, swipes, Smart Zoom and other native Magic Mouse behaviors must continue to function normally.
6. Quick three-finger tap and three-finger dragging must be mutually exclusive. A completed drag must NEVER trigger a middle click.

GESTURE ENGINE
- Implement a reliable state machine using real touch contact identities, contact counts, positions, timing and transitions.
- Distinguish intentional taps from resting fingers, scrolling, swipes, accidental touches and physical clicks.
- A multi-finger gesture must never generate extra one- or two-finger clicks during its start or release.
- Three-finger drag should begin only after deliberate movement and/or a brief configurable hold threshold, with minimal perceived latency.
- Use configurable internal thresholds for timing, movement, tap sensitivity, finger-count stabilization and drag activation.
- Support normal double-click behavior from two successive one-finger taps.
- Never produce duplicate clicks, stuck buttons, ghost drags or unexpected context menus.
- Handle fingers landing/lifting a few milliseconds apart.
- Avoid interference between two-finger scroll and two-finger tap.
- Never synthesize clicks merely because a finger rests on the surface.
- Handle rapid repeated taps, device disconnection/reconnection, sleep/wake, and app shutdown.
- If a drag is interrupted, always release the synthetic mouse-down safely.
- Prefer completing the gesture based on touch lifecycle, without polling.

TECHNOLOGY
- Swift, AppKit, CoreGraphics and IOKit only where necessary.
- Use Apple's private MultitouchSupport.framework if necessary to access raw Magic Mouse contacts. Load it carefully at runtime with dlopen/dlsym, verify ABI structures and callback signatures, and isolate private API usage behind a small adapter.
- Study implementation techniques in https://github.com/slopcore/mousetoucher and https://github.com/Raphe-dev/magic-mouse-touch, while respecting their licenses. Do not blindly copy code.
- Generate synthetic mouse events only when a recognized gesture requires it, using CGEvent APIs with correct event types, cursor location, button state and ordering.
- Avoid recursive event injection by identifying the application's own synthetic events.
- If monitoring pointer movement is required for drag, design the event tap to minimize overhead and never swallow unrelated input.
- Do not override macOS mouse preferences, change system-wide scrolling behavior, install kernel extensions or require disabling SIP.
- Do not use Electron, Chromium, Node.js, Python runtimes, networking, analytics, cloud services or third-party packages.
- Do not use accessibility polling loops.
- Do not add background helper processes unless technically unavoidable.
- Make device handling specific to Magic Mouse rather than modifying all pointing devices.
- Explain any macOS or hardware limitations honestly; do not claim unsupported functionality is working.

UI
- Menu Bar Only: no Dock icon, no permanent window.
- A small, elegant native macOS menu with:
  * Enabled toggle, default ON after required permission is granted.
  * Magic Mouse Connected / Disconnected status.
  * One-finger tap: Left Click (ON).
  * Two-finger tap: Right Click (ON).
  * Three-finger tap: Middle Click (ON).
  * Three-finger drag (ON).
  * Launch at Login toggle (default OFF).
  * Settings, About and Quit.
- Simple macOS-style settings panel, opened only on demand.
- Advanced settings can expose tap sensitivity, drag activation threshold and an optional drag lock setting (OFF by default).
- Persist preferences locally with UserDefaults.
- Use SMAppService for Launch at Login where supported.
- Use SF Symbols for status/menu icons.
- Do not update the UI continuously while the menu is closed.

PERMISSIONS AND SAFETY
- Request Accessibility permission only when required, with clear instructions.
- Do not silently modify security/privacy permissions.
- If permission is denied or touch APIs are unavailable, show a clear status and fail safely.
- Stop gesture handling when disabled.
- Unregister callbacks and event taps during shutdown.
- Never leave a synthetic mouse button held down.
- Avoid broad event suppression; physical mouse actions must remain usable if the app fails.
- Never automatically run destructive TCC resets or modify protected system settings.

PERFORMANCE
- Native arm64 Apple Silicon build, optimized Release configuration.
- Event-driven architecture; no high-frequency timers, busy waiting or continuous scans.
- Target approximately zero CPU usage when idle, minimal wakeups and the smallest practical RAM footprint.
- Avoid excessive allocations, logging, UI refreshes and work in touch callbacks.
- Profile and report actual CPU/RAM measurements when possible; do not invent benchmark results.
- Optimize correctness and responsiveness before micro-optimizations.

DELIVERABLES
1. Complete compilable source code and project files.
2. A build.sh script that produces an installable .app bundle.
3. A clearly named Release build artifact: Magic Mouse Tap.app.
4. README with installation, permissions, usage, troubleshooting and uninstall steps.
5. Automated unit tests for gesture state transitions using simulated touch sequences.
6. Test cases for 1/2/3-finger taps, scrolling rejection, three-finger drag, double taps, interrupted gestures, physical click coexistence, device reconnection and shutdown.
7. Brief explanation of any private framework limitations and macOS compatibility.
8. Actual build output and test results, indicating anything unverified on real Magic Mouse hardware.

WORKFLOW
- Inspect the macOS environment, SDK, available toolchains and current workspace.
- Choose the simplest reliable architecture.
- Implement all files directly.
- Compile the application and fix compilation errors.
- Run automated tests and fix failures.
- Perform static review for input handling, event lifecycle, permissions, deadlocks, crashes and resource leaks.
- Produce the final .app and clear installation instructions.
- If actual hardware testing is unavailable, explicitly say which behaviors need hands-on verification; never fabricate successful hardware testing.
- Do not stop at pseudocode, mockups or a partial implementation.
- Make practical engineering decisions without unnecessary questions.

ACCEPTANCE CRITERIA
A. One-finger tap creates exactly one left click.
B. Two-finger tap creates exactly one right click and no left click.
C. Three-finger quick tap creates exactly one middle click.
D. Three-finger touch-and-move enables real drag-and-drop, including dragging files/windows and selecting text wherever macOS permits.
E. Releasing all fingers ends dragging without leaving the button pressed.
F. Physical mouse clicks and native scrolling remain functional.
G. No accidental click occurs during ordinary scrolling or finger resting.
H. Toggling the app OFF immediately stops its injected actions.
I. Application remains responsive and lightweight over prolonged use.
J. A distributable .app bundle exists and builds successfully.

START IMPLEMENTING NOW.
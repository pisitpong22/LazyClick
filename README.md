# LazyClick

A tiny native macOS menu bar app that adds touch gestures to Apple's **Magic Mouse** without changing its normal behavior.

| Gesture | Result |
|---|---|
| One-finger quick tap | Left click (two quick taps = double-click) |
| Two-finger quick tap | Right click |
| Three-finger quick tap (no movement) | Middle click |
| Three fingers down + move the mouse | Left button held → drag; releases when all fingers lift |

### Gesture styles

Settings shows a looping animation of each gesture (a top-down Magic Mouse, your fingers and a tiny desktop). Hover a row to see it; Reduce Motion shows a still frame.

Pick one in the menu or **Settings → Gesture style** (default: Trackpad).

| | Trackpad style | Mouse style |
|---|---|---|
| Left click | 1-finger tap | Tap the **left half** of the surface |
| Right click | 2-finger tap | Tap the **right half** |
| Middle click | 3-finger tap | — |
| Double-click | 2 quick 1-finger taps | 2 quick taps on the left half |
| Drag | 3 fingers down + move the mouse | Tap once, then touch again and **move the mouse while holding** (release by lifting) |

**Both** turns everything on at once. The only real overlap is a one-finger tap (Trackpad: always left click; Mouse: left/right by half). In Both, the half decides; two- and three-finger taps and three-finger drag still work, and tap-and-hold drag is added.

In Mouse style the second touch must come within 0.4 s of the left tap, near the same spot, and the finger must stay still on the surface (a sliding finger is a scroll). "Swap left and right sides" mirrors the halves.

Physical clicks, pointer movement, scrolling, swipes and Smart Zoom are never intercepted or suppressed — the app only *adds* events when a gesture is recognized.

- Swift + AppKit + CoreGraphics + IOKit only. No packages, no network, no helper processes, no kernel extensions, no SIP changes.
- Event driven: no timers or polling while idle (one single-shot timer exists only while the optional drag lock window is open).
- Apple Silicon (arm64) release build, ~430 KB bundle.

> **Status:** the code builds, 86 automated tests pass, and the private touch API was verified to load and enumerate a real Magic Mouse on the development Mac. **Actual finger gestures on real hardware have not been exercised yet** — see [Verification status](#verification-status).

## Requirements

- macOS 13 or newer (uses `SMAppService`). Developed and built on macOS 27.0.1 / Xcode toolchain with Swift 6.4, Apple Silicon.
- A Magic Mouse (family ID 112/113, or any non-built-in multitouch device with a Magic-Mouse-sized sensor).

## Build

```sh
./build.sh
```

Runs the unit tests, builds Release for arm64, assembles `build/LazyClick.app`, generates the icon, and signs it ad-hoc. Options:

```sh
SKIP_TESTS=1 ./build.sh                                   # skip tests
CODESIGN_IDENTITY="Apple Development: Name (TEAMID)" ./build.sh   # stable identity
```

Ad-hoc signed builds get a new code identity every rebuild, so macOS may ask you to re-grant Accessibility after rebuilding. Sign with a fixed identity to avoid that.

## Install

```sh
cp -R "build/LazyClick.app" /Applications/
open "/Applications/LazyClick.app"
```

Launch at Login works best from `/Applications`.

If you copy the app from another Mac or download it, macOS quarantines it. For an ad-hoc signed build run once:
`xattr -dr com.apple.quarantine "/Applications/LazyClick.app"`.

## Permissions

The app needs **Accessibility** (to post click/drag events). On first launch it shows the standard macOS prompt once. Nothing is changed automatically:

1. System Settings → Privacy & Security → Accessibility
2. Switch on **LazyClick**

The menu shows "Grant Accessibility Access…" until it's granted; gestures start automatically afterwards (the app listens for the trust-change notification — no polling). Reading touches does not require a permission. If permission is missing, the app does nothing and the menu bar icon is dimmed.

Never run `tccutil reset` for this — toggle the switch off/on instead if macOS shows it enabled but it doesn't work (typical after a rebuild with a different signature).

## Usage

Click the menu bar icon:

- **Enabled** — master switch. Turning it off immediately releases any synthetic button and stops all injection.
- **Magic Mouse: Connected / Disconnected** — status.
- **One-/Two-/Three-finger tap**, **Three-finger drag** — per-gesture switches.
- **Launch at Login** — off by default.
- **Settings…** — tap sensitivity (strict → relaxed), drag activation distance, optional drag lock (off by default) and its timeout.
- **About**, **Quit**.

Tips: tap with the fingertip lightly and lift quickly (under ~0.3 s) without sliding. Landing fingers within ~0.1 s of each other counts as simultaneous. For a drag, put three fingers down, then move the mouse (≥ 6 pt by default); hold the fingers on the surface for as long as you want to drag.

## How it works

```
MultitouchSupport (private) ──raw frames──▶ RawFrameParser ──▶ GestureEngine (pure state machine)
                                                                       │ actions
                                       CGEvent (HID tap) ◀── SyntheticMouse ◀── GestureController
```

- `Sources/LazyClickCore` — gesture engine, raw frame parser, controller, CGEvent poster. No private API, fully unit tested.
- `Sources/LazyClick` — menu bar app. `MultitouchAdapter.swift` is the **only** file that touches the private framework.
- A *session* begins when the first finger lands and ends when the last finger lifts. Taps are decided only at session end, so staggered landings/lifts can't create intermediate clicks. Fingers sliding, late fingers, long holds, cursor motion, or a physical click disqualify the tap. A drag permanently disqualifies the session from tapping, so a drag can never end in a middle click.
- Drag starts when ≥ 3 fingers are stably present and the pointer has moved past the activation distance; the button is pressed at the session's start position and synthetic `leftMouseDragged` events follow the pointer on each touch frame. Everything that can interrupt it (disable, device loss, sleep, quit, SIGTERM/SIGINT/SIGHUP, feature toggled off) releases the button.
- Pointer movement and physical button state are read from `CGEvent`/`CGEventSource` on touch frames only — there is **no event tap**, so no input is ever swallowed or delayed.
- Synthetic events carry the marker `0x4D4D5441` in `eventSourceUserData`.

## Private framework notes and limitations

- `MultitouchSupport.framework` is private and undocumented. It's loaded with `dlopen`/`dlsym`; any missing symbol → "Touch API unavailable" and the app stays inert. Touch records are read at fixed byte offsets (96-byte records) and every frame is range-checked; five consecutive implausible frames stop gesture handling (ABI-mismatch fail-safe).
- Apple may change it in any macOS release. Not App Store compatible.
- Contact stages 3 (making) and 4 (touching) count as "down"; hover/breaking stages are ignored. Contacts within 3 % of the left/right edge are ignored (grip). Both are heuristics that may need tuning on real hardware.
- **Smart Zoom:** the OS still receives the raw touches, so macOS's own one-finger double-tap Smart Zoom (if enabled in System Settings → Mouse) will fire alongside a synthetic double-click. Disable Smart Zoom if that bothers you.
- Two-finger tap vs. two-finger scroll is separated by finger travel and duration; a scroll that stays under the travel tolerance and lifts within the tap window will be seen as a tap. Use the Strict sensitivity setting if needed.
- If the process is killed with `SIGKILL` or crashes in the middle of a drag, macOS can't be told to release the button; a physical click clears it.
- Only one gesture engine exists: with two Magic Mice attached their touches are merged.

## Verification status

Done on the development Mac (Apple Silicon, macOS 27.0.1):

- `./build.sh` → Release arm64 `.app`, codesign verifies.
- `swift test` → 86 tests, 0 failures: Mouse style (side taps, tap-and-hold drag, double-click vs drag, swapped sides, scroll rejection), 1/2/3-finger taps, staggered landing/lift, late fingers, scroll rejection, strict/relaxed sensitivity, edge contacts, three-finger drag (start, finger count drop, staggered lift, never a click), drag lock, double/triple/rapid taps, interrupted gestures, physical-click coexistence, raw-record parsing, device disconnect/reconnect, sleep, disable mid-drag, shutdown, ABI-fault shutdown.
- `LazyClick --probe` loaded the private framework on the real machine, listed the Magic Mouse (family 112, 5152×9056 sensor — matches `ioreg`), started it and stopped it without errors.
- Idle resource use (no touches), measured with `ps`/`top` for ~30 s: `0.0 %` CPU, resident memory ~7–8 MB with the Magic Mouse started (probe mode) and ~20 MB for the full menu bar app after start-up settles (~55 MB right after launch, without Accessibility granted so the touch adapter was not running). No load testing was done.

**Not verified (needs hands-on testing with the mouse):**

- That real touch frames decode as expected (run `LazyClick --probe 15` and touch the mouse; it prints contacts and flags `IMPLAUSIBLE` frames).
- Actual tap/drag recognition quality and the default thresholds.
- Drag-and-drop of files/windows/text selection in real apps (synthetic drag events vs. hardware motion events).
- Interplay with Smart Zoom, Bluetooth reconnect/sleep-wake with the actual device, Launch at Login.
- CPU/RAM during sustained gesture use.

## Troubleshooting

- **Nothing happens:** check the menu — "Grant Accessibility Access…" shown? Grant it. Status "Disconnected"? Toggle Bluetooth on the mouse. Icon dimmed means disabled / no permission / touch API fault.
- **Accessibility is on but gestures don't work after a rebuild:** switch it off and on again in System Settings, or remove the entry (−) and re-add the app.
- **Accidental clicks:** Settings → set Tap sensitivity to Strict; keep fingers from sliding.
- **Taps ignored:** set Tap sensitivity to Relaxed.
- **Drag starts too eagerly / too late:** adjust Drag activation distance.
- **Diagnose touch data:** `"/Applications/LazyClick.app/Contents/MacOS/LazyClick" --probe 15`
- **Launch at Login fails:** move the app to `/Applications`; approve it in System Settings → General → Login Items.

## Uninstall

1. Quit from the menu; turn off Launch at Login first (or remove it in System Settings → General → Login Items).
2. Delete `/Applications/LazyClick.app`.
3. Remove it from Privacy & Security → Accessibility (− button).
4. Optional: `defaults delete io.github.pisitpong22.LazyClick`.

## Prior art and licensing

The approach (runtime-loaded MultitouchSupport, per-frame contact decoding) was studied from
[slopcore/mousetoucher](https://github.com/slopcore/mousetoucher) (MIT) and
[Raphe-dev/magic-mouse-touch](https://github.com/Raphe-dev/magic-mouse-touch) (no license file at time of review).
No code was copied from either; the gesture engine, parser, controller and tests are original. Touch record layout is community-documented knowledge.

MIT licensed — see `LICENSE`.

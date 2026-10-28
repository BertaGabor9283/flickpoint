# Architecture: Flickpoint

## Stack
| choice | why |
|---|---|
| Native Swift, AppKit + SwiftUI, macOS 14+ | `CMHeadphoneMotionManager` exists on macOS only from 14, and synthetic mouse events need native APIs anyway |
| No Xcode project, `build.sh` + `swiftc` | one script builds a signed `.app`; nothing to keep in sync |
| Menu-bar app (`LSUIElement`) | a remote should sit out of the way; the live panel opens on demand |
| `UserDefaults` for settings + calibration | single user, a handful of numbers |
| Carbon `RegisterEventHotKey` | global hotkeys without needing Input Monitoring permission |
| `CGEvent` posting | real mouse-moved / click events so hover and double-click work everywhere (needs Accessibility) |

No backend, no accounts, no network.

## Modules (`Sources/`)
| file | does |
|---|---|
| `main.swift` | boots `NSApplication`, app delegate, menu-bar item, live panel window |
| `AppModel.swift` | the one observable state object: wires motion → mapper → cursor, owns settings and calibration steps |
| `MotionEngine.swift` | wraps `CMHeadphoneMotionManager`: connect / disconnect, measured Hz, latest sample |
| `PointerMapper.swift` | quaternion math, 3-step calibration, maps attitude → screen point, One-Euro smoothing |
| `FlickDetector.swift` | click gesture from `userAcceleration` spikes, cooldown, peak meter |
| `CursorDriver.swift` | posts mouse-moved / down / up with click counts, Accessibility checks |
| `HotKeys.swift` | global hotkeys |
| `LivePanel.swift` | SwiftUI panel: rate, status, angles, preview, meter, controls |

## The mapping (the hard part)
A bud held in the hand points in an arbitrary direction, so fixed yaw → X, pitch → Y doesn't work. Calibration learns the axes instead:

1. **Center:** aim at the middle of the screen and keep still → stores reference attitude `q0`.
2. **Right edge:** aim at the right edge → the rotation `q · q0⁻¹` gives a rotation vector; its direction is the "horizontal" axis `h`, its length is the half-width angle `θh`.
3. **Top edge:** same for the "vertical" axis `v` (made perpendicular to `h`) and `θv`.

Live: `r = rotvec(q · q0⁻¹)`, `x = (r·h)/θh`, `y = (r·v)/θv` in −1…1 → screen point (× gain), smoothed with a One-Euro filter (low lag when moving fast, steady when still). Works for hand-held or head-worn buds alike, and the calibrated angles become your personal range.

**Recenter** (Space in the panel, ⌃⌥R anywhere) replaces only `q0`, keeping the learned axes; this also cancels the yaw drift headphone sensors get without a compass.

## Click
`|userAcceleration|` (g) above the threshold (default 1.0 g) and rising → click. Cooldown 280 ms. The click lands at the cursor position from ~120 ms earlier (a ring buffer), and the cursor freezes for 220 ms so the flick's swing doesn't drag it. Two clicks within the system double-click interval and 6 pt of each other get `clickState = 2`.

## Permissions
- **Motion & Fitness** (`NSMotionUsageDescription`), asked by the system on first start.
- **Accessibility**, asked via `AXIsProcessTrustedWithOptions`; without it the panel still shows motion but the cursor won't move.
- The build is ad-hoc signed, so a rebuild can make macOS forget the Accessibility grant. Remove and re-add the app in System Settings → Privacy & Security → Accessibility if the cursor stops moving after a rebuild.

## Parts that bite
- Ear detection: taking a bud out disconnects motion → turn Automatic Ear Detection off to hand-hold.
- Motion comes from one bud at a time; status shows which.
- Updates stop when the buds switch to another device.
- Multi-display: v1 maps to the main display only.

## Build order
Shell + panel → motion stream on screen → calibration → cursor move → flick click → hotkeys + menu → settings persistence.

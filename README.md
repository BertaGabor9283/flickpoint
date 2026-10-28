# Flickpoint

Aim your AirPods to move the Mac pointer. Flick to click.

A Mac app for macOS 14+, with a window, a Dock icon and a menu bar icon. It reads the motion sensors in AirPods through Apple's Core Motion API and turns them into a pointer: hold one bud like a pen (or just wear them and steer with your head), aim at the screen, flick your wrist to click.

## Build and run

```bash
xcode-select --install     # once, if you don't have the command line tools
./build.sh --dmg           # builds and makes build/Flickpoint.dmg
```

Open `Flickpoint.dmg` and drag Flickpoint onto Applications. (Or `./build.sh --install` to skip the DMG and install straight away.)

The DMG is signed only for your own Mac, not notarized by Apple. On your Mac it opens normally. If you give it to someone else, macOS will block it the first time: they right-click the app → Open, or allow it under System Settings → Privacy & Security.

On first run macOS asks two things:
1. **Motion access** for headphone motion. Allow it.
2. **Accessibility**, needed to move and click the pointer. Flickpoint opens the right settings page. Switch Flickpoint on.

## Using it

Flickpoint is a regular Mac app with three ways in:
- **Window**: sidebar with **Live** (status, aim preview, flick meter), **Calibration** (guided 3 steps), **Settings** and **Help**. Closing the window keeps Flickpoint running, so the pointer keeps working. Click the Dock icon to bring it back.
- **Dock icon**: right-click it for Pointer Control, Recenter, Calibrate and Settings.
- **Menu bar icon**: click it for a compact panel, right-click for a quick menu. The icon gets motion lines while pointer control is on.
- **Menus across the top**: *Control* (Pointer Control ⌃⌥P, Recenter ⌃⌥R, Calibrate ⌃⌥C), *View* (pages ⌘1–⌘4), *Window*, *Help*. **Settings…** is ⌘, as usual.

You can hide the Dock icon or the menu bar icon in Settings → App (one of them always stays). Settings → App also has **Open at login**.

Can't see the menu bar icon? On a MacBook with a notch, icons that don't fit are hidden behind it: quit a few other menu bar apps, or ⌘-drag icons to make room.

1. Connect your AirPods (AirPods Pro, AirPods 3rd gen or newer, or AirPods Max).
2. **Calibrate** (R in the panel, or ⌃⌥C anywhere): aim at the center, hold still; then the right edge, hold still; then the top edge, hold still. Flickpoint learns how you hold the bud and how far you like to turn.
3. **Pointer control on**: ⌃⌥P.
4. Aim to point. **Flick** to click, flick twice quickly to double-click.
   Like an iPad trackpad, the pointer **sticks** to buttons, links, menu items and sidebar rows: it glides to the center and a soft highlight appears around the control. Aim clearly away to let go.
5. **Auto-recenter** works like head-tracked spatial audio, with a 3-second wait. By default (*Off-screen*): if you aim off the screen and hold still for 3 s, that direction glides back to become the center, so drift or a new sitting position fixes itself. *Always* recenters whenever you hold still for 3 s anywhere, exactly like AirPods audio, but then a pointer resting on something slides to the middle of the screen. *Off* turns it off.
   You can still recenter by hand: **Space** in the panel or **⌃⌥R** anywhere.

### Holding a single bud like the demo
Taking a bud out of your ear normally stops its motion stream. Turn off **Automatic Ear Detection**: System Settings → your AirPods → Automatic Ear Detection. Then hold one bud, calibrate, and go.

### Tuning (in the panel)
- **Reach**: how far the pointer travels for the same turn.
- **Smoothing**: more = steadier, less = snappier.
- **Stickiness**: how strongly the pointer snaps to clickable things and how far you must aim away to break free. 0 turns it off. The highlight can be turned off separately.
- **Flick strength**: raise it if you get clicks you didn't mean, lower it if flicks don't register. The meter shows how hard each flick was.

## Hotkeys
| where | key | does |
|---|---|---|
| anywhere | ⌃⌥P | pointer control on / off |
| anywhere | ⌃⌥R | recenter |
| anywhere | ⌃⌥C | calibrate |
| Live / Calibration page, menu bar panel | Space | recenter (captures the step during calibration) |
| Live / Calibration page, menu bar panel | R | calibrate |
| Live / Calibration page, menu bar panel | Esc | cancel calibration (or close the menu bar panel) |
| app | ⌘1 … ⌘4 | Live, Calibration, Settings, Help |
| app | ⌘, | Settings |

## Good to know
- After a rebuild macOS may silently stop trusting the app for Accessibility (it's ad-hoc signed). If the pointer stops moving, remove Flickpoint from Privacy & Security → Accessibility and add it again, or build with your developer certificate: `SIGN_ID="Apple Development: …" ./build.sh --install`.
- Works on the main display only.
- Sticking uses the Accessibility information apps publish. Most Apple apps, Safari and Chrome publish it well; some games and custom-drawn apps don't, so nothing sticks there.
- While pointer control is on it overrides your trackpad. ⌃⌥P gives the trackpad back.

## Project layout
- `Sources/`: the app (Swift, AppKit + SwiftUI, Core Motion)
- `Resources/`: Info.plist and the icon
- `replica/`: planning notes (recon of the demo video, architecture, brand, parity, test plan)

AirPods is a trademark of Apple Inc. Flickpoint is a personal project, not affiliated with Apple.

# Test plan (manual, on the Mac)

Needs: macOS 14+, motion-capable AirPods (your AirPods Pro work), Xcode command line tools.

| ID | steps | expected |
|---|---|---|
| B-1 | `./build.sh` | compiles with no errors; `build/Flickpoint.app` exists |
| F01-H1 | Launch, connect AirPods (in ears) | system asks for motion access; panel shows Connected · Left/Right bud, ~25–50 Hz, angles moving |
| F01-H2 | Press R, hold still at center, then right edge, then top edge | each step auto-captures after ~1 s still; panel ends at "Ready" or "Pointer control is off" |
| F01-E1 | During step 2, don't move at all | step does not capture (must turn ≥ 4°) |
| F01-E2 | Press Esc during calibration | calibration cancels, old calibration kept |
| F02-H1 | ⌃⌥P on, allow Accessibility when asked | aiming moves the real cursor; reaching the calibrated edges reaches the screen edges |
| F02-H2 | Press Space while aiming somewhere | that direction becomes the center |
| F02-E1 | Hold perfectly still for 10 s | cursor doesn't jitter (raise Smoothing if it does) |
| F02-E2 | Turn way past the edge | cursor stops at the screen edge, doesn't wrap |
| F03-H1 | Aim at a Finder icon, flick the wrist | one click on the icon, not beside it |
| F03-H2 | Two quick flicks on a Finder folder | folder opens (double-click) |
| F03-E1 | Slow, deliberate movement | no clicks (raise Flick strength if there are) |
| F04-H1 | Close the panel, drive System Settings sidebar | hover + clicks work in other apps |
| HAND-1 | Turn off Automatic Ear Detection (Bluetooth → AirPods ⓘ), take one bud out, recalibrate holding it like a pen | works like the demo video |
| N-1 | Put buds in the case | status → Waiting within ~1.5 s; cursor stops |
| N-2 | Deny Accessibility | panel says Accessibility is needed; cursor doesn't move; motion still shows |
| N-3 | Rebuild + reinstall | if cursor stops moving: remove & re-add Flickpoint in Privacy & Security → Accessibility |
| M-1 | Stickiness 60 %, aim across a Finder toolbar / System Settings sidebar | pointer glides onto each button / row, highlight appears around it, moves to the neighbour when you aim onto it |
| M-2 | While stuck, aim a little past the edge | stays stuck; aim further and it lets go |
| M-3 | While stuck, flick | clicks that control |
| M-4 | Stickiness 0 | no snapping, no highlight |
| M-5 | Hover a big area (web page body, list background) | nothing sticks |
| A-1 | Auto-recenter Off-screen: aim well past the left edge, hold still 3 s | panel counts down 3 s, then the pointer glides to the center over ~0.6 s |
| A-2 | Off-screen mode: rest the pointer on a menu bar item 5 s | nothing recenters (that's on-screen) |
| A-3 | Always mode: hold still anywhere 3 s | glides to center; doesn't repeat until you move again |
| A-4 | Move during the countdown | countdown resets |
| D-1 | `./build.sh --dmg`, open the DMG, drag to Applications, launch | app installs and runs |
| K-1 | ⌃⌥P / ⌃⌥R / ⌃⌥C from another app | toggle / recenter / calibrate work without the panel focused |

Bugs: none recorded yet (nothing has been run). Log any as S1–S4 in `replica/bugs.md`.

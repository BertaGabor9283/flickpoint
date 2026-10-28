# Recon: the AirPods "magic remote" demo

## Scope
- **Target:** an unnamed, unreleased macOS developer demo shown in an 18.7 s vertical video (Korean caption "킹받는 프로그램 만들기 #106", creator watermark). The app itself is not public, so the video is the only source.
- **Platform:** macOS on an Apple-silicon MacBook.
- **Slice:** the whole core loop: hold one AirPod like a pointer, aim it to move the Mac cursor, gesture to click.
- **For:** personal use (a fun / accessibility hands-free pointer). Local-only build, nothing sold, so the backend, entrepreneur, launch and deploy phases are skipped. The rebrand still applies.

## Sources
| # | source | URL / location | value |
|---|---|---|---|
| 1 | Demo video (user-supplied) | attachment `1d86e33a-….mp4`, 720×1280, 18.7 s, no narration | primary |
| 2 | Apple docs: CMHeadphoneMotionManager | https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager | platform API, macOS 14+, needs `NSMotionUsageDescription` |
| 3 | WWDC23 "What's new in Core Motion" notes | https://wwdcnotes.com/notes/wwdc23/10179 | headphone motion on macOS 14, sensor location (left/right bud), ear detection fires connect/disconnect |

## Screen inventory
| ID | screen | how you get there | purpose | key components | states seen |
|---|---|---|---|---|---|
| S01 | Live debug window (small dark window, ~0:01–0:06) | launched app | shows the motion stream and calibration state | big green "LIVE nn Hz" rate readout; status row (bud LEFT, sensor location, age, connected); pitch / yaw / roll readouts; cyan guidance line ("calibration done · Space resets reference · R redo"); grey preview area with a green dot (pointer preview); right side: two horizontal meters with a marker (acceleration in g with a threshold, peak value) | live / connected, calibrated. No empty, error or disconnected state seen |
| S02 | Any other app, here System Settings (~0:10–0:15) | the window is closed or moved away, control keeps working | proof it drives the real system pointer | system cursor, hover, sidebar selection changes | clicking sidebar rows (General selected) |

Reference screenshots from the video were used during planning only and are not part of this repository.

## Flows
- **F01 Calibrate:** open app → hold AirPod still → "calibration done" → Space resets the reference point, R repeats calibration. Happy path: ~1 key press.
- **F02 Point:** wrist rotation (yaw / pitch of the bud) moves the cursor across the whole screen. Motion looks absolute (pointing a direction = a screen position), smoothed, ~50 Hz.
- **F03 Click:** a short wrist flick clicks under the cursor (inferred from the acceleration meter + threshold marker and from System Settings rows getting selected while the hand flicks; the stem is not visibly pressed). **Confidence: medium.**
- **F04 Use other apps:** the cursor drives System Settings; control is global, not limited to the app window.

Clicks to beat: point-and-click needs 0 keys once calibrated.

## Components
- Rate readout (large, live)
- Key/value status chips (bud, location, connection, age)
- Angle readouts (pitch, yaw, roll)
- Guidance line (instruction text, changes per calibration state)
- Pointer preview canvas with a dot
- Threshold meter (bar, threshold marker, peak text) ×2

## Inferred data model (no persistence seen)
| entity | fields | evidence | confidence |
|---|---|---|---|
| Motion sample | attitude (quaternion / pitch-yaw-roll), userAcceleration (g), rotationRate, sensorLocation, timestamp | readouts on S01; CoreMotion API | high |
| Calibration | reference attitude | "Space resets reference" | high |
| Settings | flick threshold, maybe gain | threshold markers on meters | guess |

## Can't be cloned (skip)
- The video's channel, branding, caption, watermark.
- Nothing proprietary in the mechanism: it is Apple's public Core Motion API.

## Hardware notes
- Needs motion-capable buds: AirPods Pro (any gen), AirPods 3rd gen or newer, AirPods Max, some Beats.
- Motion arrives from one bud at a time. With Automatic Ear Detection on, taking a bud out of the ear fires a disconnect, so holding a bud in the hand needs Automatic Ear Detection switched **off** (or wear the buds and steer with the head).

## Size
**S (a weekend).** Hardest parts:
1. Mapping an arbitrarily-held bud's orientation to screen X/Y (the bud's axes don't line up with your hand).
2. A flick that clicks without also dragging the cursor away.
3. macOS permissions: Motion & Fitness for headphone motion, Accessibility for synthetic mouse events, and ad-hoc signing resetting the grant on rebuild.

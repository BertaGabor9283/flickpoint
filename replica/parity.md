## Parity: 100.0 / 100

features 100.0  (14 counted, must-haves 7 of 7 done)

## By area, weakest first
- motion                       100.0  (1 features)
- live panel                   100.0  (6 features)
- calibration                  100.0  (3 features)
- pointer                      100.0  (3 features)
- click                        100.0  (1 features)

## Missing, in build order
- nothing. Every counted feature is done.

## Left out on purpose (not scored)
- Creator branding and watermark: not part of the product and not ours

## Yours, not in the original (not scored)
- Guided 3-step calibration that learns your grip and range
- Global hotkeys to toggle / recenter / calibrate
- Menu bar icon with on/off and status
- Auto-pause when the bud disconnects
- Click lands where you aimed (not where the flick swung)
- Double-click from two quick flicks
- Adjustable gain smoothing and flick threshold (saved)
- Permission checks with one-click fix

## Honest caveat
The score counts features **written into the code**, not verified on hardware. The code was written in a Linux workspace with no Swift compiler, so it has **not been compiled or run yet**. Numbers that are verified: the calibration math (simulated in Python with a random grip and a shifted world-yaw origin: aiming at the calibrated edges gives exactly ±1, a corner gives 0.75 / −0.99 for a 0.75 / −1 target). Run `replica/test-plan.md` on the Mac before trusting the score.

Layout diff was not run: the original is a 720p phone video of a laptop screen, so a screenshot-to-screenshot diff isn't meaningful, and the panel's look is deliberately different (rebrand).

Behaviour vs. the original: same zero-key point-and-click loop once calibrated; calibration is 3 holds instead of 1, in exchange for working however the bud is held.

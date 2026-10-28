import Foundation
import simd

/// Turns a sharp acceleration spike (a wrist flick or a quick nod) into one click.
struct FlickDetector {
    var threshold: Double = 1.0          // g
    var cooldown: TimeInterval = 0.28

    private(set) var level: Double = 0   // current |userAcceleration| in g
    private(set) var peak: Double = 0    // held for a second, for the meter
    private var peakAt: TimeInterval = -10
    private var lastFire: TimeInterval = -10
    private var armed = true

    /// Returns true on the sample where a flick starts.
    mutating func update(acceleration a: SIMD3<Double>, at t: TimeInterval) -> Bool {
        let m = simd_length(a)
        level = m
        if m >= peak || t - peakAt > 1.0 { peak = m; peakAt = t }

        // Re-arm only once the hand has settled, so one flick = one click.
        if !armed && m < threshold * 0.5 { armed = true }
        guard armed, m >= threshold, t - lastFire >= cooldown else { return false }
        armed = false
        lastFire = t
        return true
    }
}

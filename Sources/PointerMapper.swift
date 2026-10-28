import Foundation
import simd

/// What calibration learns: which rotation of *your grip* means "right" and "up",
/// and how far you turned to reach the screen edges. Axes are stored in the bud's
/// own frame so they survive reconnects and recentering.
struct Calibration: Codable {
    var hAxisBody: SIMD3<Double>
    var vAxisBody: SIMD3<Double>
    var hAngle: Double            // radians from center to right edge
    var vAngle: Double            // radians from center to top edge
}

/// Rotation vector (axis × angle, radians) of a quaternion, shortest path.
func rotationVector(_ q: simd_quatd) -> SIMD3<Double> {
    var q = q.normalized
    if q.real < 0 { q = simd_quatd(real: -q.real, imag: -q.imag) }
    let s = simd_length(q.imag)
    if s < 1e-9 { return 2 * q.imag }
    return q.imag / s * (2 * atan2(s, q.real))
}

struct PointerMapper {
    private(set) var calibration: Calibration?
    private(set) var reference: simd_quatd?
    private var hWorld = SIMD3<Double>(0, 0, -1)
    private var vWorld = SIMD3<Double>(0, 1, 0)

    static let minAngle = 3.0 * .pi / 180

    mutating func setCalibration(_ c: Calibration?) {
        calibration = c
        rebuild()
    }

    mutating func setReference(_ q: simd_quatd) {
        reference = q
        rebuild()
    }

    private mutating func rebuild() {
        guard let c = calibration, let q0 = reference else { return }
        hWorld = q0.act(c.hAxisBody)
        vWorld = q0.act(c.vAxisBody)
    }

    /// Where the bud points, as −1…1 on each axis (x right, y up). nil until calibrated and centered.
    func normalized(_ q: simd_quatd) -> SIMD2<Double>? {
        guard let c = calibration, let q0 = reference else { return nil }
        let r = rotationVector(q * q0.inverse)
        return SIMD2(simd_dot(r, hWorld) / c.hAngle, simd_dot(r, vWorld) / c.vAngle)
    }

    // MARK: Building a calibration from the three captures

    /// World-frame rotation from `center` to `q`.
    static func turn(from center: simd_quatd, to q: simd_quatd) -> SIMD3<Double> {
        rotationVector(q * center.inverse)
    }

    static func makeCalibration(center: simd_quatd, right: SIMD3<Double>, top: SIMD3<Double>) -> Calibration? {
        let hAngle = simd_length(right)
        guard hAngle >= minAngle else { return nil }
        let h = right / hAngle
        let vPerp = top - simd_dot(top, h) * h
        let vAngle = simd_length(vPerp)
        guard vAngle >= minAngle else { return nil }
        let v = vPerp / vAngle
        let toBody = center.inverse
        return Calibration(hAxisBody: toBody.act(h), vAxisBody: toBody.act(v), hAngle: hAngle, vAngle: vAngle)
    }
}

/// One-Euro filter: steady when still, low lag when moving fast.
struct OneEuroFilter {
    var minCutoff: Double = 1.0
    var beta: Double = 0.004
    var derivativeCutoff: Double = 1.0
    private var x: Double?
    private var dx: Double = 0
    private var t: Double?

    init(minCutoff: Double = 1.0, beta: Double = 0.004) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    mutating func reset() { x = nil; t = nil; dx = 0 }

    mutating func filter(_ value: Double, at time: Double) -> Double {
        guard let prevX = x, let prevT = t else { x = value; t = time; return value }
        let dt = max(time - prevT, 1e-3)
        let rawDx = (value - prevX) / dt
        dx += Self.alpha(derivativeCutoff, dt) * (rawDx - dx)
        let cutoff = minCutoff + beta * abs(dx)
        let out = prevX + Self.alpha(cutoff, dt) * (value - prevX)
        x = out; t = time
        return out
    }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}

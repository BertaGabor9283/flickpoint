import CoreMotion
import Foundation
import simd

/// One headphone motion update, already converted to plain Swift types.
struct MotionSample {
    /// Orientation that maps device-frame vectors into the reference (world) frame.
    let orientation: simd_quatd
    let pitch: Double, yaw: Double, roll: Double          // radians, as reported
    let userAcceleration: SIMD3<Double>                    // g, gravity removed
    let rotationRate: SIMD3<Double>                        // rad/s
    let timestamp: TimeInterval                            // seconds since boot
    let bud: String
}

/// Wraps CMHeadphoneMotionManager (macOS 14+). Delivers samples on the main queue.
final class MotionEngine: NSObject, CMHeadphoneMotionManagerDelegate {
    enum Status { case unavailable, denied, waiting, connected }

    var onSample: ((MotionSample) -> Void)?
    var onStatus: ((Status) -> Void)?

    private let manager = CMHeadphoneMotionManager()

    // CoreMotion doesn't document which way the attitude quaternion rotates.
    // We vote once using gravity: the right convention sends device gravity to world -Z.
    private var votesDirect = 0
    private var votesInverse = 0
    private var useInverse = false
    private var conventionLocked = false

    func start() {
        guard manager.isDeviceMotionAvailable else { onStatus?(.unavailable); return }
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            onStatus?(.denied); return
        default: break
        }
        manager.delegate = self
        onStatus?(.waiting)
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if error != nil, motion == nil {
                let auth = CMHeadphoneMotionManager.authorizationStatus()
                if auth == .denied || auth == .restricted { self.onStatus?(.denied) }
                return
            }
            guard let motion else { return }
            self.onSample?(self.makeSample(motion))
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func makeSample(_ m: CMDeviceMotion) -> MotionSample {
        let cq = m.attitude.quaternion
        let q = simd_quatd(ix: cq.x, iy: cq.y, iz: cq.z, r: cq.w).normalized
        let g = SIMD3<Double>(m.gravity.x, m.gravity.y, m.gravity.z)

        if !conventionLocked, simd_length(g) > 0.5 {
            let gn = simd_normalize(g)
            if q.act(gn).z < -0.8 { votesDirect += 1 }
            else if q.inverse.act(gn).z < -0.8 { votesInverse += 1 }
            if votesDirect + votesInverse >= 10 {
                useInverse = votesInverse > votesDirect
                conventionLocked = true
            }
        }

        let bud: String
        switch m.sensorLocation {
        case .headphoneLeft: bud = "Left"
        case .headphoneRight: bud = "Right"
        default: bud = "Single"
        }

        return MotionSample(
            orientation: useInverse ? q.inverse : q,
            pitch: m.attitude.pitch, yaw: m.attitude.yaw, roll: m.attitude.roll,
            userAcceleration: SIMD3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z),
            rotationRate: SIMD3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z),
            timestamp: m.timestamp,
            bud: bud
        )
    }

    // MARK: CMHeadphoneMotionManagerDelegate

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async { self.onStatus?(.connected) }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async { self.onStatus?(.waiting) }
    }
}

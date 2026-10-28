import AppKit
import Combine
import ServiceManagement
import simd

/// Everything the panel shows, updated once per motion sample.
struct LiveState {
    var hz: Double = 0
    var bud: String = "—"
    var pitch: Double = 0, yaw: Double = 0, roll: Double = 0   // degrees
    var preview: CGPoint?                                        // −1…1, y up
    var accel: Double = 0
    var peak: Double = 0
    var holdProgress: Double = 0
    var restProgress: Double = 0                                 // auto-recenter countdown 0…1
}

final class AppModel: ObservableObject {
    enum Connection { case checking, unavailable, denied, waiting, connected }
    enum CalibrationStep: Int { case idle = 0, center, right, top }

    // Live
    @Published private(set) var live = LiveState()
    @Published private(set) var connection: Connection = .checking
    @Published private(set) var step: CalibrationStep = .idle
    @Published private(set) var trusted = CursorDriver.isTrusted(prompt: false)
    @Published private(set) var calibrated = false
    @Published private(set) var lastClickAt = Date.distantPast

    // Settings (saved)
    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Keys.enabled); enabledChanged() }
    }
    @Published var gain: Double { didSet { defaults.set(gain, forKey: Keys.gain) } }
    @Published var smoothing: Double {
        didSet { defaults.set(smoothing, forKey: Keys.smoothing); applySmoothing() }
    }
    @Published var flickEnabled: Bool { didSet { defaults.set(flickEnabled, forKey: Keys.flickEnabled) } }
    @Published var flickThreshold: Double {
        didSet { defaults.set(flickThreshold, forKey: Keys.flickThreshold); flick.threshold = flickThreshold }
    }
    /// 0 = off, 1 = very sticky. iPad-style snapping to buttons, links, rows…
    @Published var magnetism: Double { didSet { defaults.set(magnetism, forKey: Keys.magnetism) } }
    @Published var showHighlight: Bool {
        didSet { defaults.set(showHighlight, forKey: Keys.showHighlight); if !showHighlight { setHighlight(nil) } }
    }
    /// What the pointer is currently stuck to, for the panel ("Button", "Link"…).
    @Published private(set) var stuckTo: String?

    /// Automatic recentering, like head-tracked spatial audio: hold still for 3 s and
    /// where you're aiming glides back to the center of the screen.
    enum AutoRecenter: String, CaseIterable, Identifiable {
        case off, offScreen, always
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: return "Off"
            case .offScreen: return "Off-screen"
            case .always: return "Always"
            }
        }
    }
    @Published var autoRecenter: AutoRecenter {
        didSet { defaults.set(autoRecenter.rawValue, forKey: Keys.autoRecenter); restSince = nil }
    }
    static let autoRecenterWait: TimeInterval = 3

    // App presence (saved). At least one of Dock / menu bar always stays on.
    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Keys.showDockIcon)
            if !showDockIcon && !showMenuBarIcon { showMenuBarIcon = true }
        }
    }
    @Published var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
            if !showMenuBarIcon && !showDockIcon { showDockIcon = true }
        }
    }
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var loginItemMessage: String?

    private enum Keys {
        static let enabled = "pointerEnabled", gain = "gain", smoothing = "smoothing"
        static let flickEnabled = "flickEnabled", flickThreshold = "flickThreshold"
        static let magnetism = "magnetism", showHighlight = "showHighlight", autoRecenter = "autoRecenter"
        static let showDockIcon = "showDockIcon", showMenuBarIcon = "showMenuBarIcon"
        static let calibration = "calibration"
    }

    private let defaults = UserDefaults.standard
    private let motion = MotionEngine()
    private let driver = CursorDriver()
    private var mapper = PointerMapper()
    private var flick = FlickDetector()
    private var filterX = OneEuroFilter()
    private var filterY = OneEuroFilter()

    private var lastSample: MotionSample?
    private var lastSampleWall = Date.distantPast
    private var needsReference = true
    private var sampleCount = 0
    private var rateWindowStart = Date()
    private var timer: Timer?

    // Pointer state
    private var history: [(t: TimeInterval, p: CGPoint)] = []
    private var lastPosted = CGPoint(x: -1, y: -1)
    private var freezeUntil: TimeInterval = 0
    private var lastPointerTime: TimeInterval?

    // Sticky pointer
    private let probe = HoverProbe()
    private var magnet = MagnetEngine()
    private var overlay: HighlightOverlay?
    private var highlighted: CGRect?

    // Auto-recenter
    private var restSince: TimeInterval?
    private var autoArmed = true                 // needs some movement between two auto-recenters
    private var glide: (from: simd_quatd, to: simd_quatd, start: TimeInterval)?
    private static let glideTime: TimeInterval = 0.6
    private static let offScreenLimit = 1.1      // aim this far past an edge counts as off-screen

    // Calibration state
    private var calCenter: simd_quatd?
    private var calRight: SIMD3<Double>?
    private var stillSince: TimeInterval?
    private static let holdTime = 0.9                 // seconds still before auto-capture
    private static let stillRate = 0.3                // rad/s
    private static let awayAngle = 4.0 * .pi / 180     // must turn this far before steps 2 and 3

    init() {
        let d = UserDefaults.standard
        _enabled = Published(initialValue: d.bool(forKey: Keys.enabled))
        _gain = Published(initialValue: d.object(forKey: Keys.gain) as? Double ?? 1.0)
        _smoothing = Published(initialValue: d.object(forKey: Keys.smoothing) as? Double ?? 0.5)
        _flickEnabled = Published(initialValue: d.object(forKey: Keys.flickEnabled) as? Bool ?? true)
        _flickThreshold = Published(initialValue: d.object(forKey: Keys.flickThreshold) as? Double ?? 1.0)
        _magnetism = Published(initialValue: d.object(forKey: Keys.magnetism) as? Double ?? 0.6)
        _showHighlight = Published(initialValue: d.object(forKey: Keys.showHighlight) as? Bool ?? true)
        _autoRecenter = Published(initialValue:
            AutoRecenter(rawValue: d.string(forKey: Keys.autoRecenter) ?? "") ?? .offScreen)
        let dock = d.object(forKey: Keys.showDockIcon) as? Bool ?? true
        let menuBar = d.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        _showDockIcon = Published(initialValue: dock)
        _showMenuBarIcon = Published(initialValue: menuBar || !dock)

        if let data = d.data(forKey: Keys.calibration),
           let c = try? JSONDecoder().decode(Calibration.self, from: data) {
            mapper.setCalibration(c)
            calibrated = true
        }
        flick.threshold = flickThreshold
        applySmoothing()
    }

    // MARK: Lifecycle

    func start() {
        motion.onSample = { [weak self] s in self?.handle(s) }
        motion.onStatus = { [weak self] status in self?.statusChanged(status) }
        motion.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func statusChanged(_ status: MotionEngine.Status) {
        switch status {
        case .unavailable: connection = .unavailable
        case .denied: connection = .denied
        case .waiting:
            connection = .waiting
            needsReference = true
        case .connected:
            connection = .connected
            needsReference = true
        }
    }

    private func tick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(rateWindowStart)
        var l = live
        l.hz = elapsed > 0 ? Double(sampleCount) / elapsed : 0
        live = l
        sampleCount = 0
        rateWindowStart = now

        if connection == .connected, now.timeIntervalSince(lastSampleWall) > 1.5 {
            connection = .waiting   // stream stopped: bud back in the case or switched device
            needsReference = true
        }
        let t = CursorDriver.isTrusted(prompt: false)
        if t != trusted { trusted = t }
    }

    // MARK: Per-sample pipeline

    private func handle(_ s: MotionSample) {
        lastSample = s
        lastSampleWall = Date()
        sampleCount += 1
        if connection != .connected { connection = .connected; needsReference = true }
        if needsReference, calibrated {
            glide = nil
            mapper.setReference(s.orientation)
            resetPointer()
            needsReference = false
        }

        var l = live
        l.bud = s.bud
        l.pitch = s.pitch * 180 / .pi
        l.yaw = s.yaw * 180 / .pi
        l.roll = s.roll * 180 / .pi

        let flicked = flick.update(acceleration: s.userAcceleration, at: s.timestamp)
        l.accel = flick.level
        l.peak = flick.peak

        if step != .idle {
            advanceCalibration(s)
            l.holdProgress = holdProgress(at: s.timestamp)
            l.preview = nil
            live = l
            return
        }
        l.holdProgress = 0

        updateGlide(at: s.timestamp)
        guard let n = mapper.normalized(s.orientation) else {
            l.preview = nil
            l.restProgress = 0
            live = l
            return
        }
        let offScreen = max(abs(n.x * gain), abs(n.y * gain)) > Self.offScreenLimit
        l.restProgress = updateAutoRecenter(s, offScreen: offScreen)
        let nx = min(max(n.x * gain, -1), 1)
        let ny = min(max(n.y * gain, -1), 1)
        l.preview = CGPoint(x: nx, y: ny)
        live = l

        if flicked && flickEnabled { lastClickAt = Date() }
        guard enabled, trusted else {
            releaseMagnet()
            return
        }

        let b = CGDisplayBounds(CGMainDisplayID())
        let rawX = Double(b.midX) + nx * Double(b.width) / 2
        let rawY = Double(b.midY) - ny * Double(b.height) / 2
        let fx = filterX.filter(rawX, at: s.timestamp)
        let fy = filterY.filter(rawY, at: s.timestamp)
        let aim = CGPoint(x: min(max(fx, Double(b.minX)), Double(b.maxX) - 1),
                          y: min(max(fy, Double(b.minY)), Double(b.maxY) - 1))

        // Sticky pointer: find what's clickable under the aim, then pull toward it.
        let dt = lastPointerTime.map { s.timestamp - $0 } ?? 0
        lastPointerTime = s.timestamp
        if magnetism > 0 { probe.probe(at: aim, now: s.timestamp) } else { probe.clear() }
        let snapped = magnet.apply(aim: aim, hit: probe.latest, strength: magnetism, dt: dt)
        let p = CGPoint(x: min(max(snapped.x, b.minX), b.maxX - 1),
                        y: min(max(snapped.y, b.minY), b.maxY - 1))
        let stuck = magnet.captured
        if stuckTo != stuck?.label { stuckTo = stuck?.label }
        setHighlight(showHighlight ? stuck?.frame : nil)

        history.append((t: s.timestamp, p: p))
        if let first = history.first, s.timestamp - first.t > 0.5 {
            history.removeAll { s.timestamp - $0.t > 0.5 }
        }

        if flicked && flickEnabled {
            // Click where you were aiming just before the flick swung the bud.
            let target = history.last(where: { $0.t <= s.timestamp - 0.1 })?.p ?? p
            driver.click(at: target)
            lastPosted = target
            freezeUntil = s.timestamp + 0.22
        } else if s.timestamp >= freezeUntil,
                  hypot(p.x - lastPosted.x, p.y - lastPosted.y) >= 0.5 {
            driver.move(to: p)
            lastPosted = p
        }
    }

    private func resetPointer() {
        filterX.reset()
        filterY.reset()
        history.removeAll()
        freezeUntil = 0
        lastPointerTime = nil
        releaseMagnet()
    }

    // MARK: Auto-recenter

    /// Returns 0…1: how far along the 3-second rest is (for the panel).
    private func updateAutoRecenter(_ s: MotionSample, offScreen: Bool) -> Double {
        let still = simd_length(s.rotationRate) < Self.stillRate
        if !still { autoArmed = true }
        let wanted: Bool
        switch autoRecenter {
        case .off: wanted = false
        case .offScreen: wanted = offScreen
        case .always: wanted = true
        }
        guard wanted, still, autoArmed, glide == nil else {
            restSince = nil
            return 0
        }
        let since = restSince ?? s.timestamp
        restSince = since
        let progress = (s.timestamp - since) / Self.autoRecenterWait
        guard progress >= 1 else { return progress }

        // Glide the center to where you're aiming instead of jumping.
        if let from = mapper.reference {
            glide = (from: from, to: s.orientation, start: s.timestamp)
        }
        restSince = nil
        autoArmed = false
        return 0
    }

    private func updateGlide(at t: TimeInterval) {
        guard let g = glide else { return }
        let x = min(1, (t - g.start) / Self.glideTime)
        let eased = x * x * (3 - 2 * x)          // smoothstep
        mapper.setReference(simd_slerp(g.from, g.to, eased))
        if x >= 1 { glide = nil }
    }

    private func releaseMagnet() {
        magnet.reset()
        probe.clear()
        if stuckTo != nil { stuckTo = nil }
        setHighlight(nil)
    }

    private func setHighlight(_ frame: CGRect?) {
        guard frame != highlighted else { return }
        highlighted = frame
        MainActor.assumeIsolated {   // motion samples arrive on the main queue
            if overlay == nil, frame != nil { overlay = HighlightOverlay() }
            overlay?.show(frame)
        }
    }

    private func applySmoothing() {
        // 0 → raw and twitchy (4 Hz cutoff), 1 → very smooth (0.2 Hz cutoff)
        let cutoff = 4.0 * pow(0.05, smoothing)
        filterX.minCutoff = cutoff
        filterY.minCutoff = cutoff
    }

    // MARK: Commands

    func toggleEnabled() { enabled.toggle() }

    private func enabledChanged() {
        guard enabled else { return }
        if !trusted { requestAccessibility() }
        if !calibrated { startCalibration() }
        resetPointer()
    }

    /// Space / ⌃⌥R. During calibration it captures the current step instead.
    func recenter() {
        if step != .idle { captureCalibration(); return }
        guard calibrated else { startCalibration(); return }
        guard let s = lastSample else { return }
        glide = nil
        restSince = nil
        mapper.setReference(s.orientation)
        resetPointer()
    }

    func startCalibration() {
        step = .center
        calCenter = nil
        calRight = nil
        stillSince = nil
    }

    func cancelCalibration() {
        guard step != .idle else { return }
        step = .idle
        stillSince = nil
    }

    func resetCalibration() {
        cancelCalibration()
        mapper.setCalibration(nil)
        defaults.removeObject(forKey: Keys.calibration)
        calibrated = false
        releaseMagnet()
    }

    /// e.g. "±18° side to side, ±11° up and down"
    var calibrationSummary: String? {
        guard let c = mapper.calibration else { return nil }
        return String(format: "±%.0f° side to side, ±%.0f° up and down", c.hAngle * 180 / .pi, c.vAngle * 180 / .pi)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemMessage = nil
        } catch {
            loginItemMessage = "Couldn't change this: \(error.localizedDescription) Move Flickpoint to Applications and try again."
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginItemMessage = "Allow Flickpoint under System Settings → General → Login Items."
        }
    }

    func requestAccessibility() {
        trusted = CursorDriver.isTrusted(prompt: true)
        if !trusted { CursorDriver.openAccessibilitySettings() }
    }

    // MARK: Calibration

    private func holdProgress(at t: TimeInterval) -> Double {
        guard let since = stillSince else { return 0 }
        return min(1, (t - since) / Self.holdTime)
    }

    private func advanceCalibration(_ s: MotionSample) {
        let still = simd_length(s.rotationRate) < Self.stillRate
        var farEnough = true
        if step != .center, let c = calCenter {
            let turn = PointerMapper.turn(from: c, to: s.orientation)
            switch step {
            case .right: farEnough = simd_length(turn) > Self.awayAngle
            case .top:
                // Must have moved away from the line between center and right edge.
                if let r = calRight, simd_length(r) > 0 {
                    let h = simd_normalize(r)
                    farEnough = simd_length(turn - simd_dot(turn, h) * h) > Self.awayAngle
                }
            default: break
            }
        }
        if still && farEnough {
            if stillSince == nil { stillSince = s.timestamp }
            if holdProgress(at: s.timestamp) >= 1 { captureCalibration() }
        } else {
            stillSince = nil
        }
    }

    /// Captures the current step now (auto after holding still, or Space / the button).
    func captureCalibration() {
        guard let s = lastSample else { return }
        stillSince = nil
        switch step {
        case .idle:
            return
        case .center:
            calCenter = s.orientation
            step = .right
        case .right:
            guard let c = calCenter else { step = .center; return }
            let turn = PointerMapper.turn(from: c, to: s.orientation)
            guard simd_length(turn) >= PointerMapper.minAngle else { return }
            calRight = turn
            step = .top
        case .top:
            guard let c = calCenter, let r = calRight else { step = .center; return }
            let turn = PointerMapper.turn(from: c, to: s.orientation)
            guard let cal = PointerMapper.makeCalibration(center: c, right: r, top: turn) else { return }
            glide = nil
            restSince = nil
            mapper.setCalibration(cal)
            mapper.setReference(c)
            if let data = try? JSONEncoder().encode(cal) { defaults.set(data, forKey: Keys.calibration) }
            calibrated = true
            needsReference = false
            resetPointer()
            step = .idle
        }
    }

    // MARK: Words

    var guidance: String {
        switch connection {
        case .checking: return "Starting…"
        case .unavailable: return "This Mac can't read headphone motion. Flickpoint needs macOS 14 or later."
        case .denied: return "Motion access is off. Allow Flickpoint under System Settings → Privacy & Security."
        case .waiting:
            return "Waiting for motion headphones (AirPods Pro, AirPods 3rd gen or newer, AirPods Max). To hold a bud in your hand, turn off Automatic Ear Detection."
        case .connected: break
        }
        switch step {
        case .center: return "Step 1 of 3 · Aim at the center of the screen and hold still."
        case .right: return "Step 2 of 3 · Now aim at the right edge and hold still."
        case .top: return "Step 3 of 3 · Now aim at the top edge and hold still."
        case .idle: break
        }
        if !calibrated { return "Not calibrated yet. Press R to calibrate." }
        if !trusted { return "Allow Accessibility so Flickpoint can move the pointer." }
        if !enabled { return "Pointer control is off. ⌃⌥P turns it on from anywhere." }
        return flickEnabled ? "Ready. Aim to point, flick to click. Space recenters."
                            : "Ready. Aim to point. Space recenters."
    }

    var guidanceSymbol: String {
        switch connection {
        case .unavailable, .denied: return "exclamationmark.triangle"
        case .waiting, .checking: return "antenna.radiowaves.left.and.right"
        case .connected: break
        }
        if step != .idle { return "scope" }
        if !calibrated || !trusted { return "exclamationmark.circle" }
        return enabled ? "checkmark.circle" : "pause.circle"
    }

    var connectionText: String {
        switch connection {
        case .checking: return "Starting"
        case .unavailable: return "Unsupported"
        case .denied: return "No motion access"
        case .waiting: return "Waiting for headphones"
        case .connected: return "Connected · \(live.bud) bud"
        }
    }

    var statusLine: String {
        switch connection {
        case .connected: return "\(connectionText) · \(Int(live.hz.rounded())) Hz"
        default: return connectionText
        }
    }
}

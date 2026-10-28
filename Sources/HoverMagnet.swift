import AppKit
import ApplicationServices

/// Something clickable under the pointer, in global top-left screen coordinates.
struct Magnet: Equatable {
    var frame: CGRect
    var role: String
    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    var label: String {
        switch role {
        case "AXButton", "AXMenuButton", "AXPopUpButton": return "Button"
        case "AXLink": return "Link"
        case "AXCheckBox": return "Checkbox"
        case "AXRadioButton": return "Option / tab"
        case "AXMenuItem", "AXMenuBarItem": return "Menu item"
        case "AXRow", "AXCell": return "Row"
        case "AXTextField", "AXComboBox", "AXTextArea": return "Text field"
        case "AXDockItem": return "Dock item"
        case "AXDisclosureTriangle": return "Disclosure"
        default: return "Control"
        }
    }
}

// MARK: - Sticky behaviour

/// iPad-trackpad-style magnetism: once the pointer is over a control it is pulled toward
/// the control's center and stays until you clearly aim away from it.
struct MagnetEngine {
    private(set) var captured: Magnet?
    private var offset = CGVector.zero          // eased (shown point − aimed point)

    mutating func reset() {
        captured = nil
        offset = .zero
    }

    /// - Parameters:
    ///   - p: where you are actually aiming (smoothed, on screen)
    ///   - hit: the latest clickable element found under the pointer, if any
    ///   - strength: 0 (off) … 1 (very sticky)
    mutating func apply(aim p: CGPoint, hit: Magnet?, strength s: Double, dt: Double) -> CGPoint {
        if s <= 0 {
            captured = nil
        } else {
            let escape = 10 + 30 * s            // how far past the edge you must aim to break free
            if let h = hit, h.frame.contains(p), h != captured {
                captured = h                    // moved onto a (different) control: snap to it
            } else if let c = captured, !c.frame.insetBy(dx: -escape, dy: -escape).contains(p) {
                captured = nil                  // aimed clearly away: let go
            }
        }

        var target = p
        if let c = captured {
            // How much of your movement still shows while stuck (1 = all of it).
            let wide = c.frame.width > 3 * c.frame.height
            let kx = wide ? 1 - 0.45 * s : 1 - 0.85 * s
            let ky = 1 - 0.85 * s
            target = CGPoint(x: c.center.x + (p.x - c.center.x) * kx,
                             y: c.center.y + (p.y - c.center.y) * ky)
            let inner = c.frame.insetBy(dx: min(3, c.frame.width / 3), dy: min(3, c.frame.height / 3))
            target.x = min(max(target.x, inner.minX), inner.maxX)
            target.y = min(max(target.y, inner.minY), inner.maxY)
        }

        // Ease into and out of the snap over ~60 ms so it glides instead of jumping.
        let a = 1 - exp(-max(dt, 0) / 0.06)
        offset.dx += (target.x - p.x - offset.dx) * a
        offset.dy += (target.y - p.y - offset.dy) * a
        return CGPoint(x: p.x + offset.dx, y: p.y + offset.dy)
    }
}

// MARK: - Finding clickable things (Accessibility API)

/// Asks the app under the pointer what is there, off the main thread, at most ~30 times a second.
final class HoverProbe {
    private(set) var latest: Magnet?
    private var inFlight = false
    private var lastStart: TimeInterval = 0
    private let queue = DispatchQueue(label: "flickpoint.hover", qos: .userInteractive)
    private let systemWide: AXUIElement = {
        let e = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(e, 0.05)   // never wait long on a busy app
        return e
    }()

    private static let clickableRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXMenuItem", "AXMenuBarItem", "AXDisclosureTriangle", "AXDockItem", "AXComboBox",
        "AXTextField", "AXTextArea", "AXCell", "AXRow", "AXIncrementor", "AXColorWell",
    ]

    func clear() { latest = nil }

    /// Call from the main thread on every pointer update.
    func probe(at p: CGPoint, now: TimeInterval) {
        guard !inFlight, now - lastStart >= 1.0 / 30 else { return }
        inFlight = true
        lastStart = now
        let systemWide = self.systemWide
        queue.async { [weak self] in
            let found = HoverProbe.clickable(at: p, systemWide: systemWide)
            DispatchQueue.main.async {
                guard let self else { return }
                self.latest = found
                self.inFlight = false
            }
        }
    }

    private static func clickable(at p: CGPoint, systemWide: AXUIElement) -> Magnet? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &hit) == .success,
              var element = hit else { return nil }

        // The hit is often a label or image inside the control, so walk up a few parents.
        for _ in 0..<5 {
            let role = string(element, "AXRole") ?? ""
            if role == "AXWindow" || role == "AXApplication" || role == "AXScrollArea" { return nil }
            if clickableRoles.contains(role) || hasPress(element) {
                guard let f = frame(element), usable(f) else { return nil }
                return Magnet(frame: f, role: role)
            }
            guard let parent = attribute(element, "AXParent"),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return nil
    }

    /// Big things (whole lists, web pages, windows) shouldn't attract the pointer.
    private static func usable(_ f: CGRect) -> Bool {
        f.width >= 6 && f.height >= 6 && f.height <= 160 && f.width * f.height <= 90_000
    }

    private static func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ e: AXUIElement, _ name: String) -> String? {
        attribute(e, name) as? String
    }

    private static func hasPress(_ e: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(e, &names) == .success,
              let list = names as? [String] else { return false }
        return list.contains("AXPress")
    }

    private static func frame(_ e: AXUIElement) -> CGRect? {
        guard let pv = attribute(e, "AXPosition"), let sv = attribute(e, "AXSize"),
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(pv, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeBitCast(sv, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

// MARK: - Highlight

/// A click-through rounded highlight drawn around the control the pointer is stuck to.
@MainActor
final class HighlightOverlay {
    private let window: NSWindow
    private let shape = CAShapeLayer()
    private var shownFrame: CGRect?
    private static let pad: CGFloat = 4

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.setAccessibilityElement(false)
        window.alphaValue = 0

        let view = NSView()
        view.wantsLayer = true
        shape.lineWidth = 2
        view.layer?.addSublayer(shape)
        window.contentView = view
    }

    /// `frame` is in global top-left coordinates (as Accessibility reports it); nil hides it.
    func show(_ frame: CGRect?) {
        guard frame != shownFrame else { return }
        shownFrame = frame
        guard let f = frame, let primary = NSScreen.screens.first else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                window.animator().alphaValue = 0
            }
            return
        }
        let pad = Self.pad
        let rect = NSRect(x: f.minX - pad, y: primary.frame.height - f.maxY - pad,
                          width: f.width + 2 * pad, height: f.height + 2 * pad)
        let wasHidden = window.alphaValue < 0.01 || !window.isVisible
        window.setFrame(rect, display: true, animate: false)

        let bounds = CGRect(origin: .zero, size: rect.size).insetBy(dx: 1, dy: 1)
        let radius = min(10, bounds.height / 2, bounds.width / 2)
        let accent = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 1.000, green: 0.478, blue: 0.322, alpha: 1)
                : NSColor(srgbRed: 0.886, green: 0.314, blue: 0.165, alpha: 1)
        }
        var stroke = accent.withAlphaComponent(0.85).cgColor
        var fill = accent.withAlphaComponent(0.16).cgColor
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            stroke = accent.withAlphaComponent(0.85).cgColor
            fill = accent.withAlphaComponent(0.16).cgColor
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = CGRect(origin: .zero, size: rect.size)
        shape.path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        shape.strokeColor = stroke
        shape.fillColor = fill
        CATransaction.commit()

        if wasHidden {
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                window.animator().alphaValue = 1
            }
        }
    }
}

import AppKit
import ApplicationServices
import CoreGraphics

/// Posts real mouse events so hover, clicks and double-clicks work in every app.
/// Needs Accessibility permission.
final class CursorDriver {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var lastClickTime: TimeInterval = -10
    private var lastClickPoint = CGPoint(x: -1000, y: -1000)
    private var clickCount = 0

    static func isTrusted(prompt: Bool) -> Bool {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func move(to p: CGPoint) {
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    func click(at p: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        let near = hypot(p.x - lastClickPoint.x, p.y - lastClickPoint.y) < 6
        let interval = MainActor.assumeIsolated { NSEvent.doubleClickInterval }   // we're on main
        clickCount = (now - lastClickTime <= interval && near) ? clickCount + 1 : 1
        lastClickTime = now
        lastClickPoint = p

        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
            e?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            e?.post(tap: .cghidEventTap)
        }
    }
}

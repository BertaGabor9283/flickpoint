import Carbon
import Foundation

/// System-wide hotkeys via Carbon. Needs no extra permission.
final class HotKeys {
    static let shared = HotKeys()

    static let controlOption = UInt32(controlKey | optionKey)
    enum Key {
        static let p: UInt32 = 35   // kVK_ANSI_P
        static let r: UInt32 = 15   // kVK_ANSI_R
        static let c: UInt32 = 8    // kVK_ANSI_C
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false

    func register(keyCode: UInt32, modifiers: UInt32, _ handler: @escaping () -> Void) {
        if !installed { install() }
        let id = UInt32(handlers.count + 1)
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x464C_4B50), id: id) // 'FLKP'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref) }
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func install() {
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotKeys.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

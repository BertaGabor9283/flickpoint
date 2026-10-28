import AppKit
import Combine
import SwiftUI

@main
enum FlickpointMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// A regular Mac app: main window, Dock icon (with its own menu), the menus across the top,
/// and a menu bar icon with a compact panel. Each of Dock / menu bar can be switched off in Settings.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    let model = AppModel()
    let nav = Navigator()

    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let quickMenu = NSMenu()
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NSApp.setActivationPolicy(model.showDockIcon ? .regular : .accessory)
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpPopover()
        observeSettings()
        registerHotKeys()
        installKeyMonitor()
        model.start()
        showMainWindow(model.calibrated ? .live : .calibration)
    }

    /// Clicking the Dock icon (or opening the app again) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(nil)
        return false
    }

    /// Closing the window keeps Flickpoint running so the pointer keeps working.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: Main window

    func showMainWindow(_ page: Navigator.Page?) {
        if mainWindow == nil {
            let controller = NSHostingController(rootView: MainView(model: model, nav: nav))
            controller.sizingOptions = [.minSize]
            controller.sceneBridgingOptions = [.title, .toolbars]
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.title = "Flickpoint"
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 920, height: 680))
            if !window.setFrameUsingName("FlickpointMainWindow") { window.center() }
            _ = window.setFrameAutosaveName("FlickpointMainWindow")
            mainWindow = window
        }
        if let page { nav.page = page }
        popover.performClose(nil)
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openLive() { showMainWindow(.live) }
    @objc private func openCalibration() { showMainWindow(.calibration) }
    @objc private func openSettings() { showMainWindow(.settings) }
    @objc private func openHelp() { showMainWindow(.help) }

    // MARK: Menu bar icon + compact panel

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "Flickpoint"
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Flickpoint"
        }
        item.isVisible = model.showMenuBarIcon
        statusItem = item
        quickMenu.delegate = self
        updateIcon(model.enabled)
    }

    private func setUpPopover() {
        let panel = MenuPanel(model: model) { [weak self] page in self?.showMainWindow(page) }
        let controller = NSHostingController(rootView: panel)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
    }

    private func updateIcon(_ on: Bool) {
        guard let button = statusItem?.button else { return }
        let name = on ? "cursorarrow.motionlines" : "cursorarrow"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: on ? "Flickpoint on" : "Flickpoint off")
        image?.isTemplate = true
        button.image = image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            popover.performClose(nil)
            guard let item = statusItem else { return }
            item.menu = quickMenu      // attach only for this click, so left-click keeps opening the panel
            sender.performClick(nil)
            item.menu = nil
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: Settings that change the app's shape

    private func observeSettings() {
        model.$enabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.updateIcon(on) }
            .store(in: &cancellables)

        model.$showMenuBarIcon
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in
                self?.statusItem?.isVisible = on
                if !on { self?.popover.performClose(nil) }
            }
            .store(in: &cancellables)

        model.$showDockIcon
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in
                _ = NSApp.setActivationPolicy(on ? .regular : .accessory)
                // Switching policy can push the app to the background; bring the window back.
                Task { @MainActor [weak self] in
                    NSApp.activate()
                    self?.mainWindow?.makeKeyAndOrderFront(nil)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Keys

    private func registerHotKeys() {
        let mods = HotKeys.controlOption
        HotKeys.shared.register(keyCode: HotKeys.Key.p, modifiers: mods) { [weak self] in self?.model.toggleEnabled() }
        HotKeys.shared.register(keyCode: HotKeys.Key.r, modifiers: mods) { [weak self] in self?.model.recenter() }
        HotKeys.shared.register(keyCode: HotKeys.Key.c, modifiers: mods) { [weak self] in
            self?.model.startCalibration()
            self?.showMainWindow(.calibration)
        }
    }

    /// Space / R / Esc on the Live and Calibration pages and in the menu bar panel (as in the original demo).
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let inPanel = self.popover.isShown && event.window === self.popover.contentViewController?.view.window
            let inWindow = event.window === self.mainWindow
                && (self.nav.current == .live || self.nav.current == .calibration)
            guard inPanel || inWindow else { return event }
            switch event.keyCode {
            case 49: self.model.recenter(); return nil                  // Space
            case 15:                                                    // R
                self.model.startCalibration()
                if inWindow { self.nav.page = .calibration }
                return nil
            case 53:                                                    // Esc
                if self.model.step != .idle { self.model.cancelCalibration(); return nil }
                if inPanel { self.popover.performClose(nil); return nil }
                return event
            default: return event
            }
        }
    }

    // MARK: Menus across the top of the screen

    private func buildMainMenu() {
        let main = NSMenu()

        // Flickpoint
        let appMenu = submenu(in: main, "Flickpoint")
        appMenu.addItem(withTitle: "About Flickpoint",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(openSettings), ","))
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(services)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Flickpoint", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Flickpoint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit (standard, so copy/paste and undo behave everywhere)
        let edit = submenu(in: main, "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Control
        let control = submenu(in: main, "Control")
        control.addItem(item("Pointer Control", #selector(togglePointer), "p", [.control, .option]))
        control.addItem(item("Recenter", #selector(recenter), "r", [.control, .option]))
        control.addItem(item("Calibrate…", #selector(calibrate), "c", [.control, .option]))
        control.addItem(.separator())
        control.addItem(item("Allow Accessibility…", #selector(allowAccessibility), ""))

        // View
        let view = submenu(in: main, "View")
        view.addItem(item("Live", #selector(openLive), "1"))
        view.addItem(item("Calibration", #selector(openCalibration), "2"))
        view.addItem(item("Settings", #selector(openSettings), "3"))
        view.addItem(item("Help", #selector(openHelp), "4"))

        // Window
        let window = submenu(in: main, "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(.separator())
        window.addItem(item("Flickpoint", #selector(openLive), "0"))
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        // Help
        let help = submenu(in: main, "Help")
        help.addItem(item("Flickpoint Help", #selector(openHelp), "?"))
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    private func submenu(in main: NSMenu, _ title: String) -> NSMenu {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        holder.submenu = menu
        main.addItem(holder)
        return menu
    }

    /// A menu item that talks to this delegate.
    private func item(_ title: String, _ action: Selector, _ key: String,
                      _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if !key.isEmpty { item.keyEquivalentModifierMask = mods }
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePointer)?:
            menuItem.state = model.enabled ? .on : .off
            return true
        case #selector(recenter)?, #selector(calibrate)?:
            return model.connection == .connected
        case #selector(allowAccessibility)?:
            return !model.trusted
        default:
            return true
        }
    }

    // MARK: Dock menu (right-click the Dock icon)

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let toggle = item("Pointer Control", #selector(togglePointer), "")
        toggle.state = model.enabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(item("Recenter", #selector(recenter), ""))
        menu.addItem(item("Calibrate…", #selector(calibrate), ""))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ""))
        return menu
    }

    // MARK: Quick menu (right-click the menu bar icon)

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === quickMenu else { return }
        menu.removeAllItems()
        let status = NSMenuItem(title: model.statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let toggle = item("Pointer Control", #selector(togglePointer), "p", [.control, .option])
        toggle.state = model.enabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(item("Recenter", #selector(recenter), "r", [.control, .option]))
        menu.addItem(item("Calibrate…", #selector(calibrate), "c", [.control, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Open Flickpoint", #selector(openLive), ""))
        menu.addItem(item("Settings…", #selector(openSettings), ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Flickpoint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: Actions

    @objc private func togglePointer() { model.toggleEnabled() }
    @objc private func recenter() { model.recenter() }
    @objc private func calibrate() { model.startCalibration(); showMainWindow(.calibration) }
    @objc private func allowAccessibility() { model.requestAccessibility() }
}

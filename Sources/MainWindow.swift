import AppKit
import SwiftUI

/// Which page the main window shows. Shared so menus and hotkeys can switch pages.
final class Navigator: ObservableObject {
    enum Page: String, CaseIterable, Identifiable {
        case live, calibration, settings, help
        var id: String { rawValue }
        var title: String {
            switch self {
            case .live: return "Live"
            case .calibration: return "Calibration"
            case .settings: return "Settings"
            case .help: return "Help"
            }
        }
        var symbol: String {
            switch self {
            case .live: return "dot.radiowaves.left.and.right"
            case .calibration: return "scope"
            case .settings: return "slider.horizontal.3"
            case .help: return "questionmark.circle"
            }
        }
    }

    @Published var page: Page? = .live
    var current: Page { page ?? .live }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: Navigator

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.page) {
                ForEach(Navigator.Page.allCases) { page in
                    Label(page.title, systemImage: page.symbol).tag(page)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) {
                ConnectionLabel(model: model)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        } detail: {
            Group {
                switch nav.current {
                case .live: LiveView(model: model, nav: nav)
                case .calibration: CalibrationView(model: model)
                case .settings: SettingsView(model: model)
                case .help: HelpView()
                }
            }
            .navigationTitle(nav.current.title)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { model.recenter() } label: {
                        Label("Recenter", systemImage: "scope")
                    }
                    .help("Recenter (⌃⌥R)")
                    .disabled(model.connection != .connected)

                    Toggle(isOn: $model.enabled) {
                        Label("Pointer control", systemImage: "cursorarrow.motionlines")
                    }
                    .toggleStyle(.switch)
                    .help("Pointer control on / off (⌃⌥P)")
                }
            }
        }
        .tint(Color.brand)
        .frame(minWidth: 760, minHeight: 560)
    }
}

// MARK: - Live

struct LiveView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: Navigator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.enabled ? "Pointer control is on" : "Pointer control is off")
                            .font(.title2.weight(.semibold))
                        ConnectionLabel(model: model).font(.callout)
                    }
                    Spacer()
                    RateBadge(model: model)
                }

                GuidanceCard(model: model)

                HStack(alignment: .top, spacing: 20) {
                    LivePreview(model: model)
                        .frame(maxWidth: 380)
                    readouts
                        .frame(minWidth: 180, alignment: .leading)
                }

                RecenterCountdown(model: model)
                FlickSection(model: model)

                HStack {
                    Button("Recenter (Space)") { model.recenter() }
                        .disabled(model.connection != .connected)
                    Button("Calibrate… (R)") {
                        model.startCalibration()
                        nav.page = .calibration
                    }
                    .disabled(model.connection != .connected)
                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private var readouts: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
            row("Pitch", degrees(model.live.pitch))
            row("Yaw", degrees(model.live.yaw))
            row("Roll", degrees(model.live.roll))
            Divider().gridCellUnsizedAxes(.horizontal)
            row("Bud", model.connection == .connected ? model.live.bud : "—")
            row("Stuck to", model.stuckTo ?? "—")
            row("Calibrated", model.calibrated ? "Yes" : "No")
            row("Accessibility", model.trusted ? "Allowed" : "Needed")
        }
        .font(.callout)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func degrees(_ v: Double) -> String {
        model.connection == .connected ? String(format: "%+.1f°", v) : "—"
    }
}

// MARK: - Calibration

struct CalibrationView: View {
    @ObservedObject var model: AppModel

    private let steps: [(AppModel.CalibrationStep, String, String)] = [
        (.center, "Center", "Aim at the middle of the screen and hold still."),
        (.right, "Right edge", "Turn until you're aiming at the right edge, then hold still."),
        (.top, "Top edge", "Go back to the middle, aim up at the top edge, then hold still."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Teach Flickpoint how you hold the bud and how far you like to turn. Each step captures itself after you hold still for about a second.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(steps, id: \.0) { item in
                        stepRow(item.0, item.1, item.2)
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                if model.step != .idle {
                    ProgressView(value: model.live.holdProgress) {
                        Text("Hold still…").font(.caption)
                    }
                }

                HStack {
                    if model.step == .idle {
                        Button(model.calibrated ? "Calibrate Again" : "Start Calibration") { model.startCalibration() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.connection != .connected)
                    } else {
                        Button("Capture Now (Space)") { model.captureCalibration() }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel (Esc)") { model.cancelCalibration() }
                    }
                    Spacer()
                    if model.calibrated && model.step == .idle {
                        Button("Forget Calibration", role: .destructive) { model.resetCalibration() }
                    }
                }

                if model.connection != .connected {
                    GuidanceCard(model: model)
                }

                if let summary = model.calibrationSummary, model.step == .idle {
                    LabeledContent("Your range", value: summary)
                }

                LivePreview(model: model).frame(maxWidth: 320)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tips").font(.headline)
                    Text("• Holding one bud in your hand? Turn off Automatic Ear Detection first (System Settings → your AirPods), or the bud stops sending motion when it leaves your ear.")
                    Text("• Wearing the buds? Calibrate with small head turns: you'll steer with your head.")
                    Text("• Hold the bud the same way each time; recenter (Space) is enough between sessions.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private func stepRow(_ step: AppModel.CalibrationStep, _ title: String, _ detail: String) -> some View {
        let state = stepState(step)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(state == .current ? Color.brand : (state == .done ? Color.green : Color.secondary.opacity(0.25)))
                    .frame(width: 26, height: 26)
                if state == .done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(step.rawValue)").font(.caption.weight(.bold))
                        .foregroundStyle(state == .current ? Color.white : Color.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        .opacity(state == .upcoming && model.step != .idle ? 0.6 : 1)
    }

    private enum StepState { case done, current, upcoming }

    private func stepState(_ step: AppModel.CalibrationStep) -> StepState {
        if model.step == .idle { return model.calibrated ? .done : .upcoming }
        if step.rawValue < model.step.rawValue { return .done }
        if step == model.step { return .current }
        return .upcoming
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Pointer") {
                ValueSlider(title: "Reach", value: $model.gain, range: 0.5...2.0,
                            text: String(format: "%.1f×", model.gain))
                ValueSlider(title: "Smoothing", value: $model.smoothing, range: 0...1,
                            text: "\(Int(model.smoothing * 100))%")
            }

            Section {
                ValueSlider(title: "Stickiness", value: $model.magnetism, range: 0...1,
                            text: model.magnetism < 0.01 ? "Off" : "\(Int(model.magnetism * 100))%")
                Toggle("Highlight what the pointer sticks to", isOn: $model.showHighlight)
                    .disabled(model.magnetism < 0.01)
            } header: {
                Text("Sticky pointer")
            } footer: {
                Text("Like an iPad trackpad: the pointer glides onto buttons, links and rows and stays until you aim clearly away.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Auto-recenter", selection: $model.autoRecenter) {
                    ForEach(AppModel.AutoRecenter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                RecenterCountdown(model: model)
            } header: {
                Text("Recentering")
            } footer: {
                Text(autoRecenterHint).foregroundStyle(.secondary)
            }

            Section("Clicking") {
                Toggle("Flick to click", isOn: $model.flickEnabled)
                ValueSlider(title: "Flick strength", value: $model.flickThreshold, range: 0.4...2.5,
                            text: String(format: "%.1f g", model.flickThreshold))
                    .disabled(!model.flickEnabled)
                FlickSection(model: model)
            }

            Section {
                Toggle("Show in the Dock", isOn: $model.showDockIcon)
                Toggle("Show in the menu bar", isOn: $model.showMenuBarIcon)
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin },
                                                       set: { model.setLaunchAtLogin($0) }))
                if let message = model.loginItemMessage {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("App")
            } footer: {
                Text("One of Dock or menu bar always stays on so you can reach Flickpoint.")
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if model.trusted {
                        Text("Allowed").foregroundStyle(.secondary)
                    } else {
                        Button("Allow…") { model.requestAccessibility() }
                    }
                }
                LabeledContent("Motion") {
                    Text(model.connection == .denied ? "Denied in Privacy & Security" : "OK")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var autoRecenterHint: String {
        switch model.autoRecenter {
        case .off: return "Recenter yourself with Space or ⌃⌥R."
        case .offScreen: return "Aim off the screen and hold still 3 s: that direction glides back to the center."
        case .always: return "Hold still 3 s anywhere and that direction becomes the center, like AirPods spatial audio. A resting pointer will slide to the middle."
        }
    }
}

// MARK: - Help

struct HelpView: View {
    private let hotkeys: [(String, String, String)] = [
        ("Anywhere", "⌃⌥P", "Pointer control on / off"),
        ("Anywhere", "⌃⌥R", "Recenter"),
        ("Anywhere", "⌃⌥C", "Calibrate"),
        ("Live & Calibration pages", "Space", "Recenter, or capture the calibration step"),
        ("Live & Calibration pages", "R", "Start calibration"),
        ("Live & Calibration pages", "Esc", "Cancel calibration"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Getting started") {
                    numbered(1, "Connect motion-capable AirPods (AirPods Pro, AirPods 3rd gen or newer, AirPods Max).")
                    numbered(2, "Allow motion access and Accessibility when macOS asks.")
                    numbered(3, "Calibrate: center, right edge, top edge.")
                    numbered(4, "Turn on pointer control (⌃⌥P). Aim to point, flick your wrist to click, flick twice to double-click.")
                }

                section("Keyboard shortcuts") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        ForEach(Array(hotkeys.enumerated()), id: \.offset) { _, item in
                            GridRow {
                                Text(item.1).font(.body.monospaced()).foregroundStyle(Color.brand)
                                Text(item.2)
                                Text(item.0).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                section("Good to know") {
                    bullet("Holding a single bud needs Automatic Ear Detection turned off, otherwise it stops sending motion.")
                    bullet("The AirPods case has no motion sensor; only the buds work.")
                    bullet("Sticky pointer works in apps that describe their buttons to macOS (Apple apps, Safari, Chrome…).")
                    bullet("Works on the main display only.")
                    bullet("While pointer control is on it overrides the trackpad. ⌃⌥P hands it back.")
                    bullet("After rebuilding the app, macOS may forget the Accessibility permission. Remove Flickpoint from Privacy & Security → Accessibility and add it again.")
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
    }

    private func numbered(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.callout.weight(.bold)).foregroundStyle(Color.brand).frame(width: 16)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

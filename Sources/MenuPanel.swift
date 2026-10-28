import AppKit
import SwiftUI

/// The compact panel that drops down from the menu bar icon.
struct MenuPanel: View {
    @ObservedObject var model: AppModel
    var openWindow: (Navigator.Page) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flickpoint").font(.headline)
                    ConnectionLabel(model: model).font(.caption)
                }
                Spacer()
                RateBadge(model: model, size: 24)
            }

            Toggle(isOn: $model.enabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pointer control")
                    Text("⌃⌥P").font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            GuidanceCard(model: model, compact: true)

            LivePreview(model: model)
            RecenterCountdown(model: model)

            HStack {
                Button("Recenter") { model.recenter() }
                    .disabled(model.connection != .connected)
                Button("Calibrate…") {
                    model.startCalibration()
                    openWindow(.calibration)
                }
                .disabled(model.connection != .connected)
            }
            .controlSize(.small)

            Divider()

            HStack {
                Button("Open Flickpoint") { openWindow(.live) }
                Button("Settings…") { openWindow(.settings) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
        .tint(Color.brand)
    }
}

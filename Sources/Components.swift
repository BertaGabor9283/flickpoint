import AppKit
import SwiftUI

extension Color {
    /// Flickpoint coral. Lighter in dark mode so it keeps contrast.
    static let brand = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.000, green: 0.478, blue: 0.322, alpha: 1)   // #FF7A52
            : NSColor(srgbRed: 0.886, green: 0.314, blue: 0.165, alpha: 1)   // #E2502A
    })
}

/// Green / orange / red dot plus "Connected · Left bud".
struct ConnectionLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(model.connectionText).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch model.connection {
        case .connected: return .green
        case .waiting, .checking: return .orange
        case .unavailable, .denied: return .red
        }
    }
}

/// Big "50 Hz" readout.
struct RateBadge: View {
    @ObservedObject var model: AppModel
    var size: CGFloat = 40

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(model.connection == .connected ? "\(Int(model.live.hz.rounded()))" : "–")
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.brand)
            Text("Hz").font(size > 30 ? .headline : .caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Update rate")
    }
}

/// The tinted instruction card that follows the app's state.
struct GuidanceCard: View {
    @ObservedObject var model: AppModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.guidance, systemImage: model.guidanceSymbol)
                .font(compact ? .caption : .callout)
                .fixedSize(horizontal: false, vertical: true)
            if model.step != .idle {
                ProgressView(value: model.live.holdProgress)
                    .accessibilityLabel("Hold still progress")
                HStack {
                    Button("Capture now (Space)") { model.captureCalibration() }
                    Button("Cancel (Esc)") { model.cancelCalibration() }
                }
                .controlSize(.small)
            } else if model.connection == .connected && !model.trusted {
                Button("Allow Accessibility…") { model.requestAccessibility() }
                    .controlSize(.small)
            }
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A small picture of the screen with a dot where the bud is aiming.
struct PreviewPad: View {
    var point: CGPoint?
    var clicked: Bool
    var aspect: CGFloat

    static var screenAspect: CGFloat {
        let b = CGDisplayBounds(CGMainDisplayID())
        return b.height > 0 ? b.width / b.height : 16 / 10
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: 0)); p.addLine(to: CGPoint(x: w / 2, y: h))
                    p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if let pt = point {
                    let x = (pt.x + 1) / 2 * w
                    let y = (1 - (pt.y + 1) / 2) * h
                    Circle()
                        .stroke(Color.brand, lineWidth: 2)
                        .frame(width: 26, height: 26)
                        .opacity(clicked ? 1 : 0)
                        .position(x: x, y: y)
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 12, height: 12)
                        .position(x: x, y: y)
                } else {
                    Text("No pointer yet")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: w, height: h)
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .accessibilityLabel("Pointer preview")
    }
}

/// Live preview bound to the model.
struct LivePreview: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PreviewPad(point: model.live.preview,
                   clicked: Date().timeIntervalSince(model.lastClickAt) < 0.25,
                   aspect: PreviewPad.screenAspect)
    }
}

struct FlickMeter: View {
    var level: Double
    var peak: Double
    var threshold: Double
    var maxG: Double = 3

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(level >= threshold ? Color.brand : Color.brand.opacity(0.4))
                    .frame(width: max(h, w * min(level / maxG, 1)))
                Rectangle().fill(Color.brand)
                    .frame(width: 2, height: h)
                    .offset(x: w * min(peak / maxG, 1) - 1)
                Rectangle().fill(Color.primary)
                    .frame(width: 2, height: h + 6)
                    .offset(x: w * min(threshold / maxG, 1) - 1)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Flick strength meter")
    }
}

/// Meter plus the numbers above it.
struct FlickSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Flick").font(.callout.weight(.medium))
                Spacer()
                Text(String(format: "now %.2f g · peak %.2f g · clicks at %.1f g",
                            model.live.accel, model.live.peak, model.flickThreshold))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            FlickMeter(level: model.live.accel, peak: model.live.peak, threshold: model.flickThreshold)
        }
    }
}

/// "Recentering in 1.4 s" while auto-recenter counts down.
struct RecenterCountdown: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.live.restProgress > 0 {
            HStack(spacing: 8) {
                ProgressView(value: model.live.restProgress)
                Text(String(format: "Recentering in %.1f s",
                            max(0, AppModel.autoRecenterWait * (1 - model.live.restProgress))))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

/// Label, slider and value on one row.
struct ValueSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var text: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range).accessibilityLabel(title)
                Text(text).monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
            }
        }
    }
}

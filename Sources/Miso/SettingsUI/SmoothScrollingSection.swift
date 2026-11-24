import MisoCore
import SwiftUI

/// Smooth scrolling applies to all devices and apps. Other scopes show it read-only.
struct SmoothScrollingSection: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope

    var body: some View {
        Section {
            if scope == .global {
                controls
            } else {
                LabeledContent("Smooth scrolling") { Text(summary) }
            }
        } footer: {
            if scope != .global {
                Text("Smooth scrolling applies to every mouse and app. Change it in All Devices & Apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        let smoothing = Binding(
            get: { model.settings.smoothing },
            set: { model.settings.smoothScrolling = $0 }
        )
        Toggle(isOn: smoothing.enabled) {
            Text("Smooth scrolling")
            Text("Each wheel notch glides to rest instead of jumping.")
        }
        if smoothing.wrappedValue.enabled {
            LabeledContent {
                HStack(spacing: 10) {
                    Text("Short").font(.callout).foregroundStyle(.secondary)
                    Slider(value: smoothing.glide, in: ScrollSmoothing.glideRange, step: 0.01) {
                        Text("Glide")
                    }
                    .labelsHidden()
                    Text("Long").font(.callout).foregroundStyle(.secondary)
                    Text(Self.milliseconds(smoothing.wrappedValue.glide))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            } label: {
                Text("Glide")
                Text("Longer is smoother. Shorter stops sooner when you stop the wheel.")
            }
        }
    }

    private var summary: String {
        let smoothing = model.settings.smoothing
        return smoothing.enabled ? "On, \(Self.milliseconds(smoothing.glide)) glide" : "Off"
    }

    private static func milliseconds(_ seconds: Double) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }
}

import MisoCore
import SwiftUI

/// Smooth scrolling controls. Applies to all devices and apps.
struct SmoothScrollingSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let smoothing = Binding(
            get: { model.settings.smoothing },
            set: { model.settings.smoothScrolling = $0 }
        )
        Section {
            Toggle("Smooth scrolling", isOn: smoothing.enabled)
            if smoothing.wrappedValue.enabled {
                LabeledContent("Glide") {
                    HStack(spacing: 10) {
                        Text("Short").font(.callout).foregroundStyle(.secondary)
                        Slider(value: smoothing.glide, in: ScrollSmoothing.glideRange, step: 0.01) {
                            Text("Glide")
                        }
                        .labelsHidden()
                        Text("Long").font(.callout).foregroundStyle(.secondary)
                        Text("\(Int((smoothing.wrappedValue.glide * 1000).rounded())) ms")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
        } header: {
            Label("Smooth Scrolling", systemImage: "water.waves")
        } footer: {
            Text("Each wheel step glides to rest and carries on from the current speed. A longer glide is smoother. A shorter glide stops sooner when you stop the wheel.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

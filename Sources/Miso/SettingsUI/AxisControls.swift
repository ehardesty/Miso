import MisoCore
import SwiftUI

struct AxisControls: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope
    let axis: WritableKeyPath<InputProfile, AxisSettings>
    let overrides: WritableKeyPath<ProfileOverrides, ProfileOverrides.Axis>

    var body: some View {
        let modes = model.modes(for: scope, axis: axis)
        ProfileControl(
            model: model, scope: scope, field: axis.appending(path: \.mode),
            overrideField: overrides.appending(path: \.mode), overrideTitle: "Override Acceleration"
        ) { mode in
            Picker("Acceleration", selection: mode) {
                ForEach(AccelerationMode.allCases) { Text($0.pointerTitle).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ForEach(modes) { mode in
            let title = modes.count > 1 ? "\(mode.pointerTitle) speed" : "Speed"
            ProfileControl(
                model: model, scope: scope, field: axis.appending(path: AxisSettings.speedField(for: mode)),
                overrideField: overrides.appending(path: ProfileOverrides.Axis.speedField(for: mode)),
                overrideTitle: "Override \(title)"
            ) { SpeedSlider(title: title, speed: $0) }
        }
        if modes.contains(.boost) {
            ProfileControl(
                model: model, scope: scope, field: axis.appending(path: \.boost),
                overrideField: overrides.appending(path: \.boost), overrideTitle: "Override Boost"
            ) { PointerBoostControl(amount: $0) }
        }
    }
}

/// Logarithmic slider so 1× sits in the middle of 0.25×…4×.
struct SpeedSlider: View {
    let title: String
    @Binding var speed: Double
    var valueText: (Double) -> String = \.multiplierText
    var accessibilityText: ((Double) -> String)?
    var valueWidth: CGFloat = 48
    var stepsPerUnit = 100.0

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Image(systemName: "tortoise")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(value: exponent, in: -2...2) {
                    Text(title)
                } minimumValueLabel: {
                    EmptyView()
                } maximumValueLabel: {
                    EmptyView()
                }
                .labelsHidden()
                .accessibilityValue((accessibilityText ?? valueText)(speed))
                Image(systemName: "hare")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(valueText(speed))
                    .monospacedDigit()
                    .frame(width: valueWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .contextMenu {
            Button("Reset to \(valueText(1))") { speed = 1 }
        }
    }

    private var exponent: Binding<Double> {
        Binding(
            get: { log2(min(max(speed, 0.25), 4)) },
            set: { value in
                // Snap near 1× so the default is easy to return to.
                let snapped = abs(value) < 0.06 ? 0 : value
                speed = (pow(2, snapped) * stepsPerUnit).rounded() / stepsPerUnit
            }
        )
    }
}

private struct PointerBoostControl: View {
    @Binding var amount: Double

    var body: some View {
        LabeledContent("Boost") {
            HStack(spacing: 10) {
                Slider(value: boost, in: 0.1...2) { Text("Boost") }
                    .labelsHidden()
                    .accessibilityValue(boostText)
                Text(boostText)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    private var boostText: String { "+\(Int((boost.wrappedValue * 100).rounded()))%" }

    private var boost: Binding<Double> {
        Binding(get: { min(max(amount, 0.1), 2) }, set: { amount = ($0 * 20).rounded() / 20 })
    }
}

private extension AccelerationMode {
    var pointerTitle: String {
        switch self {
        case .linear: "Off"
        case .system: "macOS"
        case .boost: "Boost"
        }
    }
}

extension Double {
    var multiplierText: String {
        formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}

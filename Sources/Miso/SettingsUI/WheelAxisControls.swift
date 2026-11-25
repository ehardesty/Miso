import MisoCore
import SwiftUI

struct WheelAxisControls: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope
    let axis: ScrollAxis

    var body: some View {
        let (settings, overrides, _, _) = axis.profileFields
        let modes = model.modes(for: scope, axis: settings)
        ProfileControl(
            model: model, scope: scope, field: settings.appending(path: \.mode),
            overrideField: overrides.appending(path: \.mode), overrideTitle: "Override Wheel Mode"
        ) { mode in
            Picker("Wheel mode", selection: mode) {
                ForEach([AccelerationMode.system, .linear, .boost]) { Text($0.wheelTitle).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ForEach(modes) { mode in
            let title = mode == .system && modes.count > 1 ? "macOS speed" : mode.wheelSpeedTitle
            ProfileControl(
                model: model, scope: scope, field: settings.appending(path: AxisSettings.speedField(for: mode)),
                overrideField: overrides.appending(path: ProfileOverrides.Axis.speedField(for: mode)),
                overrideTitle: "Override \(title)"
            ) { speed in
                if mode == .system {
                    SpeedSlider(title: title, speed: speed)
                } else {
                    SpeedSlider(
                        title: title, speed: speed, valueText: \.linesText,
                        accessibilityText: { "\($0.linesText) per wheel step" },
                        stepsPerUnit: 20
                    )
                }
            }
        }
        if modes.contains(.boost) {
            ProfileControl(
                model: model, scope: scope, field: settings.appending(path: \.boost),
                overrideField: overrides.appending(path: \.boost), overrideTitle: "Override Fast-Scroll Boost"
            ) { WheelBoostControl(boost: $0) }
            ProfileControl(
                model: model, scope: scope, field: settings.appending(path: \.wheelRamp),
                overrideField: overrides.appending(path: \.wheelRamp), overrideTitle: "Override Wheel Ramp"
            ) { WheelRampControl(ramp: $0) }
        }
    }
}

private struct WheelBoostControl: View {
    @Binding var boost: Double

    var body: some View {
        LabeledContent("Fast-scroll boost") {
            HStack(spacing: 10) {
                Slider(value: sliderValue, in: AxisSettings.wheelBoostRange, step: 0.5) { Text("Fast-scroll boost") }
                    .labelsHidden()
                    .accessibilityValue(capText)
                Text(capText)
                    .monospacedDigit()
                    .frame(width: SettingsLayout.valueWidth, alignment: .trailing)
                    .help("+\(Int((amount * 100).rounded()))%")
                    .accessibilityHidden(true)
            }
        }
    }

    private var amount: Double { AxisSettings(mode: .boost, boost: boost).wheelAccelerationAmount }

    private var capText: String { "Up to \((1 + amount).multiplierText)" }

    private var sliderValue: Binding<Double> {
        Binding(get: { amount }, set: { boost = $0 })
    }
}

private extension AccelerationMode {
    var wheelTitle: String {
        switch self {
        case .system: "macOS"
        case .linear: "Fixed"
        case .boost: "Custom"
        }
    }

    var wheelSpeedTitle: String {
        switch self {
        case .system: "Speed"
        case .linear: "Wheel step distance"
        case .boost: "Slow scroll distance"
        }
    }
}

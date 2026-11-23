import MisoCore
import SwiftUI

/// Mode, boost, ramp, and distance rows for one wheel axis.
///
/// Uses the same `AxisSettings` encoding as the pointer: acceleration below zero
/// is Fixed, zero is macOS, above zero is Custom with that value as the boost cap.
/// `speed` is a multiplier in macOS mode and lines per wheel step otherwise.
struct WheelAxisControls: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope
    let axis: WritableKeyPath<InputProfile, AxisSettings>
    let overrides: WritableKeyPath<ProfileOverrides, ProfileOverrides.Axis>

    var body: some View {
        let modes = effectiveModes
        let distance = DistanceControl(modes)
        ProfileControl(
            model: model, scope: scope, field: axis.appending(path: \.acceleration),
            overrideField: overrides.appending(path: \.acceleration), overrideTitle: "Override Wheel Mode"
        ) { WheelModeControl(acceleration: $0) }
        if modes.contains(.custom) {
            ProfileControl(
                model: model, scope: scope, field: axis.appending(path: \.wheelRamp),
                overrideField: overrides.appending(path: \.wheelRamp), overrideTitle: "Override Wheel Ramp"
            ) { WheelRampControl(ramp: $0) }
        }
        ProfileControl(
            model: model, scope: scope, field: axis.appending(path: \.speed),
            overrideField: overrides.appending(path: \.speed),
            overrideTitle: distance.overrideTitle
        ) { speed in
            switch distance {
            case .multiplier:
                SpeedSlider(title: "Speed", speed: speed)
            case .lines(let slowOnly):
                SpeedSlider(
                    title: slowOnly ? "Slow scroll distance" : "Wheel step distance", speed: speed,
                    valueText: Self.linesText,
                    accessibilityText: { "\(Self.linesText($0)) per wheel step" },
                    valueWidth: 72,
                    stepsPerUnit: 20
                )
            case .variesByMouse:
                SpeedSlider(title: "Scroll distance", speed: speed, valueText: Self.numberText, stepsPerUnit: 20)
                    .help("A multiplier in macOS mode, or lines per wheel step in Fixed and Custom.")
            }
        }
    }

    /// App scopes resolve through each connected mouse, so an app that inherits
    /// Custom from a mouse still shows the Custom-only rows.
    private var effectiveModes: Set<WheelMode> {
        var modes: Set<WheelMode> = [WheelMode(model.profile(for: scope)[keyPath: axis].acceleration)]
        if case let .app(id) = scope {
            let connectedModes = model.devices.map { device in
                WheelMode(model.settings.profile(device: device.id, app: id)[keyPath: axis].acceleration)
            }
            if !connectedModes.isEmpty { modes = Set(connectedModes) }
        }
        return modes
    }

    private enum DistanceControl {
        case multiplier, lines(slowOnly: Bool), variesByMouse

        init(_ modes: Set<WheelMode>) {
            if modes.contains(.system) {
                self = modes.count == 1 ? .multiplier : .variesByMouse
            } else {
                self = .lines(slowOnly: modes.contains(.custom))
            }
        }

        var overrideTitle: String {
            switch self {
            case .multiplier: "Override Speed"
            case .lines(let slowOnly): slowOnly ? "Override Slow Scroll Distance" : "Override Wheel Step Distance"
            case .variesByMouse: "Override Scroll Distance"
            }
        }
    }

    private static func linesText(_ lines: Double) -> String {
        let number = numberText(lines)
        return lines == 1 ? "\(number) line" : "\(number) lines"
    }

    private static func numberText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct WheelModeControl: View {
    @Binding var acceleration: Double

    var body: some View {
        Picker("Wheel mode", selection: mode) {
            ForEach(WheelMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        if WheelMode(acceleration) == .custom {
            LabeledContent("Fast-scroll boost") {
                HStack(spacing: 10) {
                    Slider(value: boost, in: AxisSettings.wheelBoostRange, step: 0.5) { Text("Fast-scroll boost") }
                        .labelsHidden()
                        .accessibilityValue(capText)
                    Text(capText)
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                        .help(percentText)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var amount: Double { AxisSettings(acceleration: acceleration).wheelAccelerationAmount }

    private var percentText: String { "+\(Int((amount * 100).rounded()))%" }

    private var capText: String { "Up to \((1 + amount).multiplierText)" }

    private var mode: Binding<WheelMode> {
        Binding(get: { WheelMode(acceleration) }, set: { acceleration = $0.defaultValue })
    }

    private var boost: Binding<Double> {
        Binding(get: { amount }, set: { acceleration = $0 })
    }
}

private enum WheelMode: CaseIterable, Identifiable {
    case system, fixed, custom

    init(_ acceleration: Double) {
        let amount = AxisSettings(acceleration: acceleration).wheelAccelerationAmount
        self = amount < 0 ? .fixed : amount == 0 ? .system : .custom
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "macOS"
        case .fixed: "Fixed"
        case .custom: "Custom"
        }
    }

    var defaultValue: Double {
        switch self {
        case .system: 0
        case .fixed: -1
        case .custom: AxisSettings.wheelBoostRange.lowerBound
        }
    }
}

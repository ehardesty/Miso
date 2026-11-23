import MisoCore
import SwiftUI

/// Speed and acceleration rows shared by the pointer and both wheel axes.
struct AxisControls: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope
    let axis: WritableKeyPath<InputProfile, AxisSettings>
    let overrides: WritableKeyPath<ProfileOverrides, ProfileOverrides.Axis>

    var body: some View {
        ProfileControl(
            model: model, scope: scope, field: axis.appending(path: \.speed),
            overrideField: overrides.appending(path: \.speed), overrideTitle: "Override Speed"
        ) { SpeedSlider(title: "Speed", speed: $0) }
        ProfileControl(
            model: model, scope: scope, field: axis.appending(path: \.acceleration),
            overrideField: overrides.appending(path: \.acceleration), overrideTitle: "Override Acceleration"
        ) { AccelerationControl(acceleration: $0) }
    }
}

/// Logarithmic slider so 1× sits in the middle of 0.25×…4×.
struct SpeedSlider: View {
    let title: String
    @Binding var speed: Double

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
                .accessibilityValue(speed.multiplierText)
                Image(systemName: "hare")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(speed.multiplierText)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .contextMenu {
            Button("Reset to 1×") { speed = 1 }
        }
    }

    private var exponent: Binding<Double> {
        Binding(
            get: { log2(min(max(speed, 0.25), 4)) },
            set: { value in
                // Snap near 1× so the default is easy to return to.
                let snapped = abs(value) < 0.06 ? 0 : value
                speed = (pow(2, snapped) * 100).rounded() / 100
            }
        )
    }
}

struct AccelerationControl: View {
    @Binding var acceleration: Double

    var body: some View {
        Picker("Acceleration", selection: mode) {
            ForEach(AccelerationMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        if AccelerationMode(acceleration) == .boost {
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
    }

    private var boostText: String { "+\(Int((acceleration * 100).rounded()))%" }

    private var mode: Binding<AccelerationMode> {
        Binding(get: { AccelerationMode(acceleration) }, set: { acceleration = $0.defaultValue })
    }

    private var boost: Binding<Double> {
        Binding(get: { min(max(acceleration, 0.1), 2) }, set: { acceleration = ($0 * 20).rounded() / 20 })
    }
}

enum AccelerationMode: CaseIterable, Identifiable {
    case linear, system, boost

    init(_ value: Double) {
        self = value < 0 ? .linear : value == 0 ? .system : .boost
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .linear: "Off"
        case .system: "macOS"
        case .boost: "Boost"
        }
    }

    var defaultValue: Double {
        switch self {
        case .linear: -1
        case .system: 0
        case .boost: 0.5
        }
    }
}

extension Double {
    var multiplierText: String {
        formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}

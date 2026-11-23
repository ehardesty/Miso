import MisoCore
import SwiftUI

/// Ramp shape and the wheel rates where Custom boost starts and reaches its cap.
struct WheelRampControl: View {
    @Binding var ramp: WheelRamp

    var body: some View {
        Picker("Ramp", selection: curve) {
            ForEach(WheelRamp.Curve.allCases, id: \.self) { curve in
                Text(curve.title).tag(curve).help(curve.help)
            }
        }
        .pickerStyle(.segmented)
        .help(ramp.curve.help)
        .accessibilityHint(ramp.curve.help)
        RateRow(title: "Boost starts at", rate: startRate,
                stepperRange: WheelRamp.rateRange.lowerBound...(ramp.fullRate - 1))
        RateRow(title: "Full boost at", rate: fullRate,
                stepperRange: (ramp.startRate + 1)...WheelRamp.rateRange.upperBound)
    }

    private var curve: Binding<WheelRamp.Curve> {
        Binding(
            get: { ramp.curve },
            set: { ramp = WheelRamp(startRate: ramp.startRate, fullRate: ramp.fullRate, curve: $0) }
        )
    }

    private var startRate: Binding<Int> {
        Binding(
            get: { ramp.startRate },
            set: { ramp = WheelRamp(startRate: min($0, ramp.fullRate - 1), fullRate: ramp.fullRate, curve: ramp.curve) }
        )
    }

    private var fullRate: Binding<Int> {
        Binding(
            get: { ramp.fullRate },
            set: { ramp = WheelRamp(startRate: ramp.startRate, fullRate: $0, curve: ramp.curve) }
        )
    }
}

/// Slider for coarse moves plus a stepper for single-step trial adjustments.
private struct RateRow: View {
    let title: String
    @Binding var rate: Int
    let stepperRange: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: sliderValue, in: range) { Text(title) }
                    .labelsHidden()
                    .accessibilityValue(spokenText)
                HStack(spacing: 4) {
                    Text(rate.wheelRateText)
                        .monospacedDigit()
                        .accessibilityHidden(true)
                    Stepper(title, value: $rate, in: stepperRange)
                        .labelsHidden()
                        .accessibilityValue(spokenText)
                }
                .frame(width: SettingsLayout.valueWidth, alignment: .trailing)
            }
        }
    }

    private var range: ClosedRange<Double> {
        Double(WheelRamp.rateRange.lowerBound)...Double(WheelRamp.rateRange.upperBound)
    }

    private var spokenText: String { rate.spokenWheelRate }

    private var sliderValue: Binding<Double> {
        Binding(get: { Double(rate) }, set: { rate = Int($0.rounded()) })
    }
}

extension Int {
    var wheelRateText: String { "\(self) \(self == 1 ? "step" : "steps")/s" }
    var spokenWheelRate: String { "\(self) wheel \(self == 1 ? "step" : "steps") per second" }
}

private extension WheelRamp.Curve {
    var title: String {
        switch self {
        case .gradual: "Gradual"
        case .linear: "Linear"
        case .quick: "Quick"
        }
    }

    var help: String {
        switch self {
        case .gradual: "Gradual saves more of the boost for fast turns."
        case .linear: "Linear builds boost evenly between the two rates."
        case .quick: "Quick gives short flicks more boost."
        }
    }
}

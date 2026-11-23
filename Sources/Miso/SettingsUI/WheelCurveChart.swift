import Charts
import MisoCore
import SwiftUI

/// Lines per wheel step that Custom applies across the runtime's rate range.
struct WheelCurveChart: View {
    let curve: AxisSettings
    let inspectedRate: Double
    /// Rates measured by the live test, already checked against `curve`.
    var liveRate: Double?
    var peakRate: Double?
    var liveIdle = true

    static let signal = Color(red: 0, green: 0.494, blue: 0.471)
    private static let rates = Array(WheelRamp.rateRange)
    private static let ceilings = [1.0, 2, 4, 8, 12, 20, 40]

    var body: some View {
        let ramp = curve.wheelRamp
        Chart {
            ForEach(Self.rates, id: \.self) { rate in
                LineMark(x: .value("Steps/s", rate), y: .value("Lines per step", lines(Double(rate))))
                    .lineStyle(StrokeStyle(lineWidth: 2.7, lineCap: .round))
                    .foregroundStyle(Self.signal)
            }
            threshold(ramp.startRate, title: "Starts", position: .topLeading)
            threshold(ramp.fullRate, title: "Full", position: .topTrailing)
            PointMark(x: .value("Steps/s", inspectedRate), y: .value("Lines per step", lines(inspectedRate)))
                .symbol {
                    Circle().strokeBorder(Self.signal, lineWidth: 2)
                        .background(Circle().fill(.background))
                        .frame(width: 11, height: 11)
                }
                .accessibilityLabel("Inspected rate")
            if let peakRate {
                PointMark(x: .value("Steps/s", peakRate), y: .value("Lines per step", lines(peakRate)))
                    .symbol(.diamond)
                    .symbolSize(40)
                    .foregroundStyle(Self.signal.opacity(0.45))
                    .accessibilityLabel("Peak this pass")
            }
            if let liveRate {
                PointMark(x: .value("Steps/s", liveRate), y: .value("Lines per step", lines(liveRate)))
                    .symbol {
                        Circle().fill(Self.signal)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                            .frame(width: 13, height: 13)
                            .opacity(liveIdle ? 0.4 : 1)
                    }
                    .accessibilityLabel("Last measured wheel rate")
            }
        }
        .chartXScale(domain: 0...Double(WheelRamp.rateRange.upperBound),
                     range: .plotDimension(startPadding: 12, endPadding: 24))
        .chartYScale(domain: 0...ceiling)
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, through: WheelRamp.rateRange.upperBound, by: 20))) {
                AxisValueLabel(centered: false, anchor: .top, collisionResolution: .disabled)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: ceiling / 4)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxisLabel("Estimated wheel rate · steps/s", position: .bottom, alignment: .center)
        .frame(height: 200)
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary)
    }

    private func lines(_ rate: Double) -> Double { curve.wheelLinesPerStep(atRate: rate) }

    private var ceiling: Double {
        let highest = lines(Double(WheelRamp.rateRange.upperBound))
        return Self.ceilings.first { $0 >= highest } ?? Self.ceilings[Self.ceilings.count - 1]
    }

    private func threshold(_ rate: Int, title: String, position: AnnotationPosition) -> some ChartContent {
        RuleMark(x: .value("Steps/s", rate))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .annotation(position: position, spacing: 2, overflowResolution: .init(x: .fit(to: .plot))) {
                Text("\(title) \(rate)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
    }

    private var summary: String {
        let ramp = curve.wheelRamp
        return "Custom wheel response, \(ramp.curve.rawValue) ramp from \(ramp.startRate) to \(ramp.fullRate) steps per second. "
            + "\(lines(0).linesText) per step when slow, up to \(lines(Double(WheelRamp.rateRange.upperBound)).linesText)."
    }
}

extension Double {
    var linesText: String {
        let number = formatted(.number.precision(.fractionLength(0...2)))
        return self == 1 ? "\(number) line" : "\(number) lines"
    }
}

import MisoCore
import SwiftUI

/// Custom wheel curve for the selected scope, with a simulated rate and a live wheel test.
struct WheelCurvePanel: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope
    let axis: WritableKeyPath<InputProfile, AxisSettings>
    @State private var previewID: String?
    @State private var inspectedRate = 38.0
    @StateObject private var live = WheelLiveTest()

    var body: some View {
        let curve = curve
        let result = curve.mode == .boost ? liveResult(curve) : .waiting
        Section {
            if curve.mode == .boost {
                chartRow(curve, result)
                inspector(curve)
                liveTestRow(curve, result)
            } else {
                Text("\(deviceName) doesn't use Custom for this wheel in \(model.title(for: scope)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(probeAxis == .vertical ? "Vertical Wheel Response" : "Horizontal Wheel Response")
                Spacer()
                if case .app = scope, !model.devices.isEmpty {
                    Picker("Preview with", selection: previewSelection) {
                        ForEach(model.devices) { Text($0.name).tag($0.id) }
                    }
                    .font(.callout)
                    .fixedSize()
                    .help("App settings combine with each mouse's own settings")
                }
            }
        }
        .onChange(of: curve) { live.clearMessage() }
        .onChange(of: model.devices) { live.clearMessage() }
    }

    // MARK: Curve

    private var probeAxis: QuartzWheelAxis { axis == \InputProfile.verticalWheel ? .vertical : .horizontal }

    /// The mouse the curve is drawn for. Global scope draws inherited settings for any mouse.
    private var device: String? {
        switch scope {
        case .global: nil
        case let .device(id): id
        case .app:
            model.devices.first { $0.id == previewID }?.id ?? model.devices.first?.id
        }
    }

    private var previewSelection: Binding<String> {
        Binding(get: { device ?? "" }, set: { previewID = $0 })
    }

    private var curve: AxisSettings {
        switch scope {
        case .global: model.settings.global[keyPath: axis]
        case let .device(id): model.settings.profile(device: id, app: nil)[keyPath: axis]
        case let .app(id): model.settings.profile(device: device, app: id)[keyPath: axis]
        }
    }

    private var deviceName: String { device.map { model.title(for: .device($0)) } ?? "This mouse" }

    private func chartRow(_ curve: AxisSettings, _ result: WheelLiveResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    chartTitle
                    Spacer(minLength: 16)
                    capKey(curve)
                }
                VStack(alignment: .leading, spacing: 4) {
                    chartTitle
                    capKey(curve)
                }
            }
            WheelCurveChart(curve: curve, inspectedRate: inspectedRate, liveRate: result.rates?.last,
                            peakRate: result.rates?.peak, liveIdle: live.idle || result.rates?.preview == true)
        }
        .padding(.vertical, 4)
    }

    private var chartTitle: some View {
        Text("Scroll distance · lines per wheel step")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func capKey(_ curve: AxisSettings) -> some View {
        let ramp = curve.wheelRamp
        return HStack(spacing: 14) {
            keyItem("Boost starts", ramp.startRate.wheelRateText)
            keyItem("Full boost", ramp.fullRate.wheelRateText)
            keyItem("Max boost", curve.wheelBoost(atRate: Double(ramp.fullRate)).multiplierText)
        }
        .font(.caption)
        .fixedSize()
    }

    private func keyItem(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit().fontWeight(.medium)
        }
        .accessibilityElement(children: .combine)
    }

    private func inspector(_ curve: AxisSettings) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Inspect rate") {
                Text(Int(inspectedRate).wheelRateText).monospacedDigit()
            }
            HStack(spacing: 16) {
                Slider(value: Binding(get: { inspectedRate }, set: { inspectedRate = $0.rounded() }),
                       in: 0...Double(WheelRamp.rateRange.upperBound)) {
                    Text("Inspect rate")
                }
                .labelsHidden()
                .tint(WheelCurveChart.signal)
                .accessibilityValue(Int(inspectedRate).spokenWheelRate)
                figure(curve.wheelLinesPerStep(atRate: inspectedRate).decimalText, "Lines per step")
                figure(curve.wheelBoost(atRate: inspectedRate).multiplierText, "Multiplier")
            }
            Text("Move the slider to see how far each notch scrolls at that speed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func liveTestRow(_ curve: AxisSettings, _ result: WheelLiveResult) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scroll to test")
                switch result {
                case let .unavailable(reason): note(reason, symbol: "info.circle")
                case let .message(text): note(text, symbol: "exclamationmark.circle")
                case .waiting, .reading: EmptyView()
                }
                if let rates = result.rates {
                    if rates.preview {
                        Text("Preview at the last measured speeds. Scroll again to test.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    readings(curve, last: rates.last, peak: rates.peak)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if case .unavailable = result {} else {
                WheelTestTarget(model: model, live: live, axis: probeAxis)
                    .frame(minWidth: 156, maxWidth: probeAxis == .vertical ? 200 : 260)
            }
        }
        .padding(.vertical, 2)
    }

    private func note(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func figure(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize()
        }
        // Fixed width keeps the slider from resizing while its value changes.
        .frame(width: 84, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func readings(_ curve: AxisSettings, last: Double, peak: Double?) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                Text("")
                Text("Steps/s")
                Text("Lines/step")
                Text("Boost")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            readingRow("Last", curve, last)
            if let peak { readingRow("Peak", curve, peak) }
        }
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
        .opacity(live.idle ? 0.7 : 1)
    }

    private func readingRow(_ title: String, _ curve: AxisSettings, _ rate: Double) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text("\(Int(rate.rounded()))")
            Text(curve.wheelLinesPerStep(atRate: rate).decimalText)
            Text(curve.wheelBoost(atRate: rate).multiplierText)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Live test

    private func liveResult(_ curve: AxisSettings) -> WheelLiveResult {
        if let reason = unavailableReason { return .unavailable(reason) }
        guard let reading = live.reading else { return .waiting }
        let last = reading.last
        switch last.input {
        case .gesture:
            return .message("Trackpad and Magic Mouse scrolling uses gestures that Miso leaves to macOS.")
        case .unknownMouse:
            return .message("Miso hasn't matched the device that scrolled to a connected mouse.")
        case .wheelInactive:
            return .message("Try a connected mouse that uses Custom in Miso.")
        case .continuous, .noSteps, .otherAxis, .steps: break
        }
        if let device = last.device, !model.devices.contains(where: { $0.id == device }) { return .waiting }
        let name = last.device.map { model.title(for: .device($0)) } ?? "That mouse"
        let fit = model.settings.fit(of: last, to: curve, axis: axis, device: device)
        switch fit {
        case .otherMouse: return .message("That scroll came from \(name). This curve is for \(deviceName).")
        case .otherSettings: return .message(mismatchReason(last, name: name))
        case .matches, .preview: break
        }
        switch last.input {
        case .continuous, .noSteps:
            return .message("Use Slow scroll distance to adjust how far this mouse scrolls. Live speed and boost need a wheel Miso can measure.")
        case .otherAxis:
            return .message(probeAxis == .vertical ? "That scroll was horizontal. Use the vertical wheel here."
                : "That scroll was vertical. Use the horizontal wheel or tilt here.")
        case .steps:
            let peak = reading.peak.flatMap {
                model.settings.fit(of: $0, to: curve, axis: axis, device: device) == fit ? $0.rate : nil
            }
            return .reading(last: last.rate, peak: peak, preview: fit == .preview)
        case .gesture, .unknownMouse, .wheelInactive:
            return .waiting
        }
    }

    /// Why live readings can't measure this curve, before any scrolling.
    private var unavailableReason: String? {
        let miso = Bundle.main.bundleIdentifier
        if case let .app(id) = scope, id != miso {
            return "The live test measures scrolling in Miso's window, where \(model.appName(for: id))'s "
                + "settings don't apply. Use Inspect rate to read this curve."
        }
        guard model.settings.enabled else { return "Turn on Miso to test with your mouse." }
        switch model.status {
        case .listening: break
        case .permissionRequired, .stopped:
            return "Live testing needs Input Monitoring and Accessibility. Grant them in Status."
        case let .unavailable(reason): return reason
        }
        if let device, !model.devices.contains(where: { $0.id == device }) {
            return "Connect \(deviceName) to test it live."
        }
        return model.devices.isEmpty ? "Connect a mouse to test it live." : nil
    }

    private func mismatchReason(_ sample: WheelSample, name: String) -> String {
        let miso = Bundle.main.bundleIdentifier
        if let app = sample.app, app != miso {
            return "\(model.appName(for: app)) was the active app, so its settings applied. Click Miso's window, then scroll."
        }
        if case .app = scope {
            return "Miso wasn't the active app, so its settings didn't apply. Click Miso's window, then scroll."
        }
        if let device = sample.device, sample.app != nil,
           model.settings.profile(device: device, app: nil)[keyPath: axis].hasSameWheelResponse(as: curve) {
            return "Miso's own app settings change this wheel while you test here. Choose Miso in the settings menu to test them."
        }
        return "\(name) has its own settings for this wheel. Choose it in the settings menu to test them."
    }
}

private extension Double {
    var decimalText: String { formatted(.number.precision(.fractionLength(0...2))) }
}

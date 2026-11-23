import Dispatch
import MisoCore
import SwiftUI

/// Main-side end of a `WheelProbe`. The probe is installed only while the
/// pointer is over an eligible test target, so the input thread does no extra
/// work otherwise.
@MainActor
final class WheelLiveTest: ObservableObject {
    @Published private(set) var reading: WheelProbe.Reading?
    @Published private(set) var idle = true

    private var probe: WheelProbe?
    private var lastReading: UInt64 = 0
    private var idleCheck: DispatchWorkItem?
    private static let idleDelay: UInt64 = 1_200_000_000

    func start(_ axis: QuartzWheelAxis, model: SettingsModel) {
        stop(model)
        clearMessage()
        let probe = WheelProbe(axis: axis) { [weak self] source, reading in
            MainActor.assumeIsolated { self?.receive(reading, from: source) }
        }
        self.probe = probe
        model.setWheelProbe(probe)
    }

    func clearMessage() {
        if let reading, reading.last.input != .steps { self.reading = nil }
    }

    /// Readings already queued from a stopped probe are ignored.
    func stop(_ model: SettingsModel) {
        guard let probe else { return }
        model.removeWheelProbe(probe)
        self.probe = nil
        idleCheck?.cancel()
        idleCheck = nil
        if !idle { idle = true }
    }

    private func receive(_ reading: WheelProbe.Reading, from source: WheelProbe) {
        guard source === probe else { return }
        if self.reading != reading { self.reading = reading }
        if idle { idle = false }
        lastReading = DispatchTime.now().uptimeNanoseconds
        if idleCheck == nil { scheduleIdleCheck(after: Self.idleDelay) }
    }

    /// One pending work item, pushed back while readings keep arriving.
    private func scheduleIdleCheck(after delay: UInt64) {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.idleCheck = nil
                let elapsed = DispatchTime.now().uptimeNanoseconds - self.lastReading
                if elapsed >= Self.idleDelay {
                    self.idle = true
                } else {
                    self.scheduleIdleCheck(after: Self.idleDelay - elapsed)
                }
            }
        }
        idleCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(delay)), execute: work)
    }
}

/// What the live test can truthfully show for the curve on screen.
enum WheelLiveResult: Equatable {
    case waiting
    case unavailable(String)
    case message(String)
    case reading(last: Double, peak: Double?, preview: Bool)

    var rates: (last: Double, peak: Double?, preview: Bool)? {
        guard case let .reading(last, peak, preview) = self else { return nil }
        return (last, peak, preview)
    }
}

/// The real scroll target. Scrolling it with the mouse wheel moves the live marker.
struct WheelTestTarget: View {
    @Environment(\.controlActiveState) private var activeState
    @ObservedObject var model: SettingsModel
    @ObservedObject var live: WheelLiveTest
    let axis: QuartzWheelAxis
    @State private var hovering = false
    private var armed: Bool { hovering && activeState == .key }

    var body: some View {
        target
            .onHover { hovering = $0 }
            .onChange(of: armed) { _, armed in
                if armed { live.start(axis, model: model) } else { live.stop(model) }
            }
            .onDisappear {
                hovering = false
                live.stop(model)
            }
    }

    private var target: some View {
        Group {
            if axis == .vertical {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) { ForEach(rows, id: \.self, content: row) }
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) { ForEach(rows, id: \.self, content: row) }
                }
            }
        }
        .defaultScrollAnchor(.center)
        .scrollIndicators(.never)
        .frame(height: axis == .vertical ? 140 : 64)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(armed ? WheelCurveChart.signal : Color.secondary.opacity(0.3))
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Text(armed ? "Scroll with your mouse wheel" : "Point here to test")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
                .padding(6)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Scroll test area")
        .accessibilityHint("Scroll here with the mouse wheel to measure the live wheel rate.")
    }

    private var rows: Range<Int> { 0..<4_000 }

    private func row(_ index: Int) -> some View {
        Text("\(index - 2_000)")
            .font(.callout.monospacedDigit())
            .foregroundStyle(index % 10 == 0 ? .primary : .secondary)
            .frame(width: axis == .vertical ? nil : 44, height: axis == .vertical ? 18 : 44,
                   alignment: axis == .vertical ? .leading : .center)
            .padding(.horizontal, 10)
    }
}

import CoreGraphics
import Foundation
import MisoCore
import os

enum QuartzWheelAxis {
    case vertical, horizontal

    var fields: (lines: CGEventField, fixed: CGEventField, points: CGEventField) {
        switch self {
        case .vertical:
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1)
        case .horizontal:
            (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
        }
    }
}

/// Collects one axis of wheel samples on the input thread while the live test
/// is armed. Main receives the latest reading at most 20 times per second.
final class WheelProbe: @unchecked Sendable {
    struct Reading: Equatable {
        var last: WheelSample
        /// Fastest stepped sample in the current pass.
        var peak: WheelSample?
    }

    private struct State {
        var reading: Reading?
        var lastTime: UInt64 = 0
        var scheduled = false
    }

    /// A pause this long starts a new pass, well past the runtime's 80 ms rate reset.
    private static let passGap: UInt64 = 500_000_000

    let axis: QuartzWheelAxis
    private let deliver: (WheelProbe, Reading) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// `deliver` runs on the main queue.
    init(axis: QuartzWheelAxis, deliver: @escaping (WheelProbe, Reading) -> Void) {
        self.axis = axis
        self.deliver = deliver
    }

    func record(_ input: WheelSample.Input) {
        record(WheelSample(input: input), at: DispatchTime.now().uptimeNanoseconds)
    }

    /// Call after the runtime has transformed `event`; `rates` are each axis's rate after it.
    func record(
        _ event: CGEvent, device: String, app: String?, profile: InputProfile, continuous: Bool,
        raw: (vertical: Double, horizontal: Double), rates: (vertical: Double, horizontal: Double),
        timestamp: UInt64
    ) {
        let vertical = axis == .vertical
        let steps = vertical ? raw.vertical : raw.horizontal
        let input: WheelSample.Input
        if !Self.moved(event, on: axis) {
            guard Self.moved(event, on: vertical ? .horizontal : .vertical) else { return }
            input = .otherAxis
        } else if continuous {
            input = .continuous
        } else if !steps.isFinite || steps == 0 {
            input = .noSteps
        } else {
            input = .steps
        }
        let sample = WheelSample(
            input: input, device: device, app: app,
            settings: vertical ? profile.verticalWheel : profile.horizontalWheel,
            rate: input == .steps ? (vertical ? rates.vertical : rates.horizontal) : 0
        )
        record(sample, at: timestamp)
    }

    private static func moved(_ event: CGEvent, on axis: QuartzWheelAxis) -> Bool {
        let fields = axis.fields
        return event.getIntegerValueField(fields.lines) != 0 || event.getDoubleValueField(fields.fixed) != 0
            || event.getDoubleValueField(fields.points) != 0
    }

    private func record(_ sample: WheelSample, at time: UInt64) {
        let schedule = state.withLock { state -> Bool in
            var peak = state.reading?.peak
            if let last = state.reading?.last, time >= state.lastTime, time - state.lastTime < Self.passGap,
               last.device == sample.device, last.app == sample.app, last.settings == sample.settings {
                // Same pass.
            } else {
                peak = nil
            }
            if sample.input == .steps, sample.rate >= peak?.rate ?? -1 { peak = sample }
            state.reading = Reading(last: sample, peak: peak)
            state.lastTime = time
            guard !state.scheduled else { return false }
            state.scheduled = true
            return true
        }
        guard schedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [self] in
            let reading = state.withLock { state -> Reading? in
                state.scheduled = false
                return state.reading
            }
            if let reading { deliver(self, reading) }
        }
    }
}

public struct WheelDelta: Equatable, Sendable {
    public var lines: Int64
    public var fixed: Double
    public var points: Double

    public init(lines: Int64, fixed: Double, points: Double) {
        self.lines = lines
        self.fixed = fixed
        self.points = points
    }
}

public struct WheelAxis: Sendable {
    private var lineRemainder = 0.0
    private var lastTimestamp: UInt64?
    private var lastDirection = 0.0

    public init() {}

    /// Update the three Quartz representations together. Only line-mode events
    /// use a remainder, so repeated sub-line inputs stay useful in line-only views.
    public mutating func transform(
        _ delta: WheelDelta,
        settings: AxisSettings,
        reversed: Bool,
        continuous: Bool,
        timestamp: UInt64,
        rawUnits: Double? = nil
    ) -> WheelDelta {
        guard settings != AxisSettings() || reversed else { return delta }
        let input: Double
        if continuous {
            input = delta.points
        } else if delta.lines != 0 {
            input = Double(delta.lines)
        } else {
            input = delta.fixed == 0 ? delta.points / 10 : delta.fixed
        }
        guard input.isFinite, input != 0 else { return delta }
        let direction = input.sign == .minus ? -1.0 : 1.0
        if direction != lastDirection { lineRemainder = 0 }

        var gain = settings.speedMultiplier * (reversed ? -1 : 1)
        let acceleration = settings.accelerationAmount
        if acceleration > 0, direction == lastDirection, let previous = lastTimestamp, timestamp > previous {
            let elapsed = Double(timestamp - previous) / 1_000_000
            let activity = min(1, max(0, (65 - elapsed) / 55))
            gain *= 1 + acceleration * activity
        }
        lastTimestamp = timestamp
        lastDirection = direction

        let linear = acceleration <= -1 && !continuous
        let linearUnits: Double
        if let rawUnits, rawUnits.isFinite, rawUnits != 0 {
            // HID reports precede macOS natural-scroll direction.
            linearUnits = abs(rawUnits) * direction
        } else {
            linearUnits = input
        }
        let lines = (linear ? linearUnits : input) * gain
        let fixed = (linear ? linearUnits : delta.fixed) * gain
        let points = (linear ? linearUnits * 10 : delta.points) * gain
        if continuous {
            return WheelDelta(lines: Self.integral(Double(delta.lines) * gain), fixed: fixed, points: points)
        }
        let sum = lines + lineRemainder
        let wholeLines = Self.integral(sum)
        // Some applications read only whole wheel lines. Keep every nonzero
        // detent visible there, even when finer encodings carry a fraction.
        let integral = wholeLines == 0 ? (lines < 0 ? -1 : 1) : wholeLines
        lineRemainder = wholeLines == 0 ? 0 : sum - Double(wholeLines)
        return WheelDelta(lines: integral, fixed: fixed, points: points)
    }

    private static func integral(_ value: Double) -> Int64 {
        guard value.isFinite else { return 0 }
        return Int64(min(Double(Int32.max), max(Double(Int32.min), value)))
    }
}

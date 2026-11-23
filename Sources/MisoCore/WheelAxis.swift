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
    /// Most recent rate used by the Custom response.
    public private(set) var stepsPerSecond = 0.0

    public init() {}

    /// Timestamp is the wheel event's monotonic time in nanoseconds.
    public mutating func transform(
        _ delta: WheelDelta,
        settings: AxisSettings,
        reversed: Bool,
        continuous: Bool,
        timestamp: UInt64,
        rawUnits: Double? = nil
    ) -> WheelDelta {
        guard settings.changesWheel || reversed else { return delta }
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
        let acceleration = settings.wheelAccelerationAmount
        let steps = rawUnits.flatMap { $0.isFinite && $0 != 0 ? abs($0) : nil }
        let custom = acceleration > 0 && !continuous && steps != nil
        if direction != lastDirection { lineRemainder = 0 }
        let sign = reversed ? -1.0 : 1.0
        var gain = settings.speedMultiplier * sign
        if custom, let steps {
            let rate = updateStepRate(steps: steps, direction: direction, at: timestamp)
            gain = settings.wheelLinesPerStep(atRate: rate) * sign
            lastTimestamp = timestamp
        } else {
            lastTimestamp = nil
            stepsPerSecond = 0
            if acceleration > 0 && gain == 1 {
                lineRemainder = 0
                return delta
            }
        }
        lastDirection = direction

        let usesSteps = !continuous && (custom || acceleration < 0)
        // HID reports precede macOS natural-scroll direction.
        let units = (steps ?? abs(input)) * direction
        let lines = (usesSteps ? units : input) * gain
        let fixed = (usesSteps ? units : delta.fixed) * gain
        let points = (usesSteps ? units * 10 : delta.points) * gain
        if continuous {
            return WheelDelta(lines: Self.integral(Double(delta.lines) * gain), fixed: fixed, points: points)
        }
        let sum = lines + lineRemainder
        let wholeLines = Self.integral(sum)
        // Custom carries fractional lines so apps that read whole lines can
        // approximate the same total distance. Preserve the old modes' minimum.
        if wholeLines == 0 && !custom {
            lineRemainder = 0
            return WheelDelta(lines: lines < 0 ? -1 : 1, fixed: fixed, points: points)
        }
        lineRemainder = sum - Double(wholeLines)
        return WheelDelta(lines: wholeLines, fixed: fixed, points: points)
    }

    private mutating func updateStepRate(steps: Double, direction: Double, at timestamp: UInt64) -> Double {
        guard direction == lastDirection, let previous = lastTimestamp, timestamp >= previous,
              timestamp - previous < 80_000_000 else {
            stepsPerSecond = 0
            return 0
        }
        let elapsed = Double(timestamp - previous) / 1_000_000
        if elapsed > 0 {
            // A short average keeps grouped or closely spaced reports from jumping to full boost.
            let speed = min(Double(WheelRamp.rateRange.upperBound), steps * 1_000 / elapsed)
            stepsPerSecond += (speed - stepsPerSecond) * min(1, elapsed / 32)
        }
        return stepsPerSecond
    }

    private static func integral(_ value: Double) -> Int64 {
        guard value.isFinite else { return 0 }
        return Int64(min(Double(Int32.max), max(Double(Int32.min), value)))
    }
}

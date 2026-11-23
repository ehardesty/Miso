public struct Swipe: Sendable {
    private let threshold: Double
    private var x = 0.0
    private var y = 0.0
    public private(set) var committed = false

    public init(threshold: Double) {
        self.threshold = threshold.isFinite ? min(200, max(10, threshold)) : 50
    }

    /// Signed displacement lets a corrected diagonal qualify later. The cross-axis
    /// tolerance grows with travel, keeping the angle stable at larger thresholds.
    public mutating func move(
        x deltaX: Double,
        y deltaY: Double,
        actions: [SwipeDirection: MouseAction]
    ) -> MouseAction? {
        guard !committed, deltaX.isFinite, deltaY.isFinite else { return nil }
        x += deltaX
        y += deltaY
        let horizontal = abs(x) > abs(y)
        let dominant = horizontal ? x : y
        let cross = horizontal ? y : x
        guard abs(dominant) >= threshold, abs(cross) <= abs(dominant) * 0.55 else { return nil }

        let direction: SwipeDirection
        if horizontal {
            direction = dominant < 0 ? .left : .right
        } else {
            direction = dominant < 0 ? .up : .down
        }
        guard let action = actions[direction] else { return nil }
        committed = true
        return action
    }
}

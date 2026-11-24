/// One axis of smoothed output in whole pixels. Frames post the motion up to
/// their own time, so the output can trail the curve by a fraction of a frame.
/// Keeping the posted total here lets reversal and cancellation start from
/// what apps actually received.
public struct SmoothedAxis: Sendable {
    private var animator: ScrollAnimator
    /// Whole pixels posted so far. The fraction carries to the next frame.
    public private(set) var posted = 0.0

    public init(glide: Double) {
        animator = ScrollAnimator(glide: glide)
    }

    /// A step against the remaining travel restarts from the posted total, so
    /// no more movement in the old direction reaches the app.
    public mutating func add(_ distance: Double, at time: Double) {
        guard distance.isFinite, distance != 0 else { return }
        if (animator.target - posted) * distance < 0 { animator.stop(at: posted) }
        animator.add(distance, at: time)
    }

    /// Whole pixels to post for a frame at `time`, capped per frame.
    public mutating func frame(at time: Double) -> Int32 {
        let distance = animator.position(at: time) - posted
        guard distance.isFinite else { return 0 }
        let step = min(10_000, max(-10_000, distance)).rounded(.towardZero)
        posted += step
        return Int32(step)
    }

    /// True when the motion has ended and every whole pixel has been posted.
    public mutating func isDrained(at time: Double) -> Bool {
        abs(animator.position(at: time) - posted) < 1 && animator.isSettled(at: time)
    }

    /// Discards remaining travel at what has already been posted.
    public mutating func stop() {
        animator.stop(at: posted)
    }
}

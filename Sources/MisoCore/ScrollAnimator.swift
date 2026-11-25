import Foundation

public struct ScrollSmoothing: Codable, Equatable, Sendable {
    public static let glideRange = 0.04...0.24
    public static let defaultGlide = 0.2
    /// Converts the wheel's line distance into the pixels apps receive.
    /// Chromium also scrolls 40 px per wheel line. How far a step moves is set
    /// by the wheel distance settings.
    public static let pixelsPerLine = 40.0

    private enum CodingKeys: String, CodingKey {
        case enabled, glide, useGesturePhases
        // Fields saved by the earlier prototype builds.
        case model, duration
    }

    public var enabled = true
    /// Seconds for one wheel step to glide to rest.
    public var glide = Self.defaultGlide
    public var useGesturePhases = false

    public init(enabled: Bool = true, glide: Double = Self.defaultGlide, useGesturePhases: Bool = false) {
        self.enabled = enabled
        self.glide = Self.clamp(glide, to: Self.glideRange, default: Self.defaultGlide)
        self.useGesturePhases = useGesturePhases
    }

    /// Each field falls back on its own, so a bad value never resets other settings.
    public init(from decoder: Decoder) throws {
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        let legacyModel = try? values.decode(String.self, forKey: .model)
        let legacyOn = legacyModel.map { ["overlap", "spring", "retarget", "adaptive"].contains($0) }
        self.init(
            enabled: (try? values.decode(Bool.self, forKey: .enabled)) ?? legacyOn ?? true,
            glide: (try? values.decode(Double.self, forKey: .glide))
                ?? (try? values.decode(Double.self, forKey: .duration)) ?? Self.defaultGlide,
            useGesturePhases: (try? values.decode(Bool.self, forKey: .useGesturePhases)) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(glide, forKey: .glide)
        try values.encode(useGesturePhases, forKey: .useGesturePhases)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, default fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

/// One axis of smoothed motion. Each wheel step bends the current glide toward
/// the new target with a fixed-length curve that keeps the current speed. It
/// does not rely on evenly spaced steps, so uneven wheels stay smooth.
///
/// Position is a pure function of time between steps, so the refresh rate only
/// changes how often motion is sampled. Motion ends exactly at the sum of the
/// distances given, minus travel discarded when the direction reverses.
/// Times are in seconds on one monotonic clock.
public struct ScrollAnimator: Sendable {
    /// The ease-out start fades in over the last quarter step of remaining
    /// travel. Earlier, the inherited speed keeps sustained scrolling even.
    private static let easeOutBlend = 4.0
    /// Like Chrome's wheel scrolling, a move up to this size uses the full glide.
    static let fullGlideDistance = 120.0
    /// Moves this large or larger use the shortest glide.
    static let shortestGlideDistance = 480.0
    /// The shortest glide as a fraction of the full glide, as in Chrome.
    static let shortestGlideFraction = 0.5

    public let glide: Double
    /// Length of the current curve, from `glide` and the size of the move.
    private var duration: Double
    private var start = -Double.infinity
    private var from = 0.0
    /// Where motion ends if no other step arrives.
    public private(set) var target = 0.0
    private var initialVelocity = 0.0
    /// Latest time sampled or added. A step timestamped before the latest
    /// sample starts from what that sample already showed.
    private var clock = -Double.infinity

    public init(glide: Double) {
        self.glide = min(ScrollSmoothing.glideRange.upperBound, max(ScrollSmoothing.glideRange.lowerBound, glide))
        duration = self.glide
    }

    /// Larger moves glide for less time, so a big boosted step lands sooner.
    static func duration(glide: Double, move: Double) -> Double {
        let fraction = (abs(move) - fullGlideDistance) / (shortestGlideDistance - fullGlideDistance)
        return glide * (1 - (1 - shortestGlideFraction) * min(1, max(0, fraction)))
    }

    private func progress(at time: Double) -> Double {
        min(1, max(0, (time - start) / duration))
    }

    /// Cubic Hermite from the starting velocity to rest at the target.
    private func value(at time: Double) -> Double {
        let u = progress(at: time)
        let tangent = initialVelocity * duration
        return from + (target - from) * (3 * u * u - 2 * u * u * u) + tangent * (u * u * u - 2 * u * u + u)
    }

    private func velocity(at time: Double) -> Double {
        let u = progress(at: time)
        guard u < 1 else { return 0 }
        let tangent = initialVelocity * duration
        return ((target - from) * (6 * u - 6 * u * u) + tangent * (3 * u * u - 4 * u + 1)) / duration
    }

    public mutating func position(at time: Double) -> Double {
        clock = max(clock, time)
        return value(at: clock)
    }

    /// Adds a wheel step. A step against the remaining travel drops that travel.
    public mutating func add(_ distance: Double, at time: Double) {
        guard distance.isFinite, distance != 0 else { return }
        clock = max(clock, time)
        let here = value(at: clock)
        var speed = velocity(at: clock)
        if (target - here) * distance < 0 || speed * distance < 0 {
            target = here
            speed = 0
        }
        start = clock
        from = here
        target += distance
        let span = target - from
        duration = Self.duration(glide: glide, move: span)
        // A longer curve than 3× span ÷ speed would have to slow down to avoid
        // overshooting. Shortening it keeps the inherited speed, as in Chrome.
        if speed * span > 0 {
            let keepsSpeed = 3 * span / speed
            duration = min(duration, max(glide * Self.shortestGlideFraction, keepsSpeed))
        }
        // As the previous glide runs out, start no slower than this step's own
        // ease-out, so a step just before or just after settling responds alike.
        let remaining = abs(span - distance)
        let weight = min(1, max(0, 1 - Self.easeOutBlend * remaining / abs(distance)))
        let floor = 3 * distance / duration * weight
        speed = distance > 0 ? max(speed, floor) : min(speed, floor)
        // A tangent within 3× the distance cannot overshoot. From rest, 3× is
        // the cubic ease-out, the quickest start without overshoot.
        let ratio = span == 0 ? 0 : min(3, max(0, speed * duration / span))
        initialVelocity = ratio * span / duration
    }

    /// True once the position has reached the target.
    public func isSettled(at time: Double) -> Bool {
        max(clock, time) - start >= duration
    }

    /// Stops at `position` and discards the remaining travel.
    public mutating func stop(at position: Double) {
        start = -Double.infinity
        from = position
        target = position
        initialVelocity = 0
        duration = glide
    }
}

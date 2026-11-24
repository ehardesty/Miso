import Foundation
import MisoCore
import Testing

private let glides = [ScrollSmoothing.glideRange.lowerBound, ScrollSmoothing.defaultGlide,
                      ScrollSmoothing.glideRange.upperBound]

/// Replays wheel steps while sampling at `rate` Hz, returning positions at `checkpoints`.
private func replay(
    glide: Double, rate: Double, steps: [(time: Double, distance: Double)], checkpoints: [Double]
) -> [Double] {
    var animator = ScrollAnimator(glide: glide)
    var pending = steps
    var results: [Double] = []
    var frame = 0.0
    for checkpoint in checkpoints {
        while true {
            let next = min(frame, checkpoint, pending.first?.time ?? .infinity)
            if let step = pending.first, step.time == next {
                animator.add(step.distance, at: step.time)
                pending.removeFirst()
                continue
            }
            _ = animator.position(at: next)
            if next == checkpoint { break }
            frame += 1 / rate
        }
        results.append(animator.position(at: checkpoint))
    }
    return results
}

@Test(arguments: glides)
func motionDoesNotDependOnTheRefreshRate(glide: Double) {
    let burst = [(0.0, 40.0), (0.031, 40.0), (0.052, 80.0), (0.067, 40.0), (0.40, -40.0)]
    let checkpoints = [0.02, 0.05, 0.12, 0.35, 0.45, 1.0]
    let at60 = replay(glide: glide, rate: 60, steps: burst, checkpoints: checkpoints)
    let at144 = replay(glide: glide, rate: 144, steps: burst, checkpoints: checkpoints)
    let at47 = replay(glide: glide, rate: 47.3, steps: burst, checkpoints: checkpoints)
    for index in checkpoints.indices {
        #expect(abs(at60[index] - at144[index]) < 0.02, "\(glide) at \(checkpoints[index])s")
        #expect(abs(at60[index] - at47[index]) < 0.02, "\(glide) at \(checkpoints[index])s")
    }
    // Same-direction steps all arrive. The reversal after settling moves back one step.
    #expect(abs(at60.last! - 160) < 0.001)
}

@Test func reversingDropsUnfinishedTravelAndMovesTheFullOppositeStep() {
    var animator = ScrollAnimator(glide: 0.09)
    animator.add(120, at: 0)
    let reversal = animator.position(at: 0.02)
    #expect(reversal > 0 && reversal < 120)
    animator.add(-40, at: 0.02)
    #expect(animator.position(at: 0.021) <= reversal + 0.5, "kept moving forward")
    #expect(abs(animator.position(at: 2) - (reversal - 40)) < 0.001)
    #expect(animator.isSettled(at: 2))
}

/// A wheel step timestamped before the latest sample starts from what that
/// sample already showed.
@Test func aStepArrivingBeforeTheShownFrameStartsFromWhatIsShown() {
    var animator = ScrollAnimator(glide: 0.09)
    animator.add(40, at: 0)
    let shown = animator.position(at: 0.0467)
    animator.add(-40, at: 0.035)
    #expect(abs(animator.position(at: 2) - (shown - 40)) < 0.001)

    var stopped = ScrollAnimator(glide: 0.09)
    stopped.add(40, at: 0)
    _ = stopped.position(at: 0.03)
    stopped.stop(at: 28)
    stopped.add(40, at: 0.05)
    #expect(abs(stopped.position(at: 2) - 68) < 0.001, "after stop")
}

/// A frame posts motion only up to its own time. A reversal that arrives
/// later must not post any more movement in the old direction.
@Test(arguments: glides)
func noOldDirectionMovementIsPostedAfterAReversal(glide: Double) {
    for frameRate in [60.0, 120.0] {
        var axis = SmoothedAxis(glide: glide)
        axis.add(40, at: 0)
        _ = axis.frame(at: 1 / frameRate)
        let shown = axis.posted
        axis.add(-40, at: 0.031)
        var time = 2 / frameRate
        while time < 1 {
            #expect(axis.frame(at: time) <= 0, "\(glide) at \(frameRate) Hz")
            time += 1 / frameRate
        }
        #expect(axis.posted == shown - 40, "\(glide) at \(frameRate) Hz")
    }
}

@Test(arguments: ["false", "{\"enabled\": \"yes\", \"glide\": 1e300}", "{\"model\": \"warp\"}"])
func aBadSmoothingValueKeepsTheOtherSavedSettings(saved: String) throws {
    var settings = Settings()
    settings.global.reverseVertical = true
    let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
    let edited = json.dropLast() + ",\"smoothScrolling\":\(saved)}"
    let decoded = try JSONDecoder().decode(Settings.self, from: Data(edited.utf8))
    #expect(decoded.global.reverseVertical)
    #expect(ScrollSmoothing.glideRange.contains(decoded.smoothScrolling?.glide ?? ScrollSmoothing.defaultGlide))
}

/// A step that arrives just before the previous glide settles must respond
/// like one that arrives just after, not with a slow start.
@Test(arguments: [0.08, 0.089, 0.091])
func aStepRespondsTheSameWhetherOrNotTheLastGlideHasSettled(gap: Double) {
    var fromRest = ScrollAnimator(glide: 0.09)
    fromRest.add(40, at: 0)
    let expected = fromRest.position(at: 0.016)

    var animator = ScrollAnimator(glide: 0.09)
    animator.add(40, at: 0)
    let before = animator.position(at: gap)
    animator.add(40, at: gap)
    #expect(animator.position(at: gap + 0.016) - before >= expected * 0.95)
}

/// Like Chrome, a large move glides for less time than a normal step does.
@Test func largeMovesGlideForLessTime() {
    var normal = ScrollAnimator(glide: 0.17)
    normal.add(40, at: 0)
    #expect(!normal.isSettled(at: 0.16))
    #expect(normal.isSettled(at: 0.17))

    var large = ScrollAnimator(glide: 0.17)
    large.add(480, at: 0)
    #expect(!large.isSettled(at: 0.084))
    #expect(large.isSettled(at: 0.0851))
    #expect(abs(large.position(at: 0.0851) - 480) < 0.001)
}

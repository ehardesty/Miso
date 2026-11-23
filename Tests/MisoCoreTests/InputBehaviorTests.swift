import MisoCore
import Testing

@Test func aCorrectedDiagonalCanTriggerOnlyOneBoundSwipe() {
    var swipe = Swipe(threshold: 50)
    let actions: [SwipeDirection: MouseAction] = [.right: .nextSpace, .left: .previousSpace]

    #expect(swipe.move(x: 70, y: 55, actions: actions) == nil)
    #expect(swipe.move(x: 0, y: -30, actions: actions) == .nextSpace)
    #expect(swipe.move(x: -170, y: 0, actions: actions) == nil)
}

@Test func anUnboundDirectionDoesNotConsumeTheHold() {
    var swipe = Swipe(threshold: 30)
    let actions: [SwipeDirection: MouseAction] = [.up: .missionControl]

    #expect(swipe.move(x: 0, y: 60, actions: actions) == nil)
    #expect(swipe.move(x: 0, y: -95, actions: actions) == .missionControl)
}

@Test func linearWheelUsesThePhysicalBurstAndPreservesDirection() {
    var axis = WheelAxis()
    let linear = AxisSettings(mode: .linear, speed: 2)
    let accelerated = WheelDelta(lines: -6, fixed: -6.5, points: -76)
    let output = axis.transform(
        accelerated, settings: linear, reversed: false, continuous: false,
        timestamp: 1_000_000_000, rawUnits: 3
    )

    #expect(output == WheelDelta(lines: -6, fixed: -6, points: -60))
    let reversed = axis.transform(
        accelerated, settings: linear, reversed: true, continuous: false,
        timestamp: 2_000_000_000, rawUnits: 3
    )
    #expect(reversed == WheelDelta(lines: 6, fixed: 6, points: 60))
}

@Test func slowWheelStillEmitsAWholeLineForAppsWithoutPreciseDeltas() {
    var axis = WheelAxis()
    let notch = WheelDelta(lines: 1, fixed: 1, points: 10)
    let output = axis.transform(
        notch, settings: AxisSettings(mode: .linear, speed: 0.25),
        reversed: false, continuous: false, timestamp: 1, rawUnits: 1
    )

    #expect(output == WheelDelta(lines: 1, fixed: 0.25, points: 2.5))
}

@Test(arguments: zip([0.5, 40.0], [2.0, 10.0]))
func customWheelStartsAtTheSetDistanceAndBoundsTheFastMultiplier(
    savedBoost: Double, expectedMultiplier: Double
) {
    var axis = WheelAxis()
    let custom = AxisSettings(mode: .boost, speed: 2, boost: savedBoost)
    let slow = WheelDelta(lines: 1, fixed: 0.1, points: 1)
    let fast = WheelDelta(lines: 12, fixed: 12.1, points: 121)
    let opposite = WheelDelta(lines: -2, fixed: -2, points: -20)
    func feed(_ delta: WheelDelta, steps: Double, at milliseconds: UInt64) -> WheelDelta {
        axis.transform(delta, settings: custom, reversed: false, continuous: false,
                       timestamp: milliseconds * 1_000_000, rawUnits: steps)
    }

    let base = WheelDelta(lines: 2, fixed: 2, points: 20)
    #expect(feed(slow, steps: -1, at: 1_000) == base)
    #expect(feed(slow, steps: -1, at: 1_400) == base)
    #expect(feed(slow, steps: -1, at: 1_500) == base)

    let rapid = (1...5).map { feed(fast, steps: -1, at: 1_500 + UInt64($0 * 19)) }
    let limit = base.points * expectedMultiplier
    #expect(rapid.allSatisfy { $0.points >= base.points && $0.points <= limit })
    #expect((rapid.last?.points ?? 0) > limit * 0.95)
    #expect(feed(opposite, steps: 1, at: 1_615) == WheelDelta(lines: -2, fixed: -2, points: -20))
    #expect(feed(slow, steps: -1, at: 1_623) == base)
    #expect(feed(fast, steps: -1, at: 2_000) == base)
}

@Test func customWheelScalesNativeDeltasWhenStepsAreUnavailable() {
    var axis = WheelAxis()
    let custom = AxisSettings(mode: .boost, boost: 2)
    let precise = WheelDelta(lines: 0, fixed: 0.3, points: 3)
    #expect(axis.transform(precise, settings: custom, reversed: false, continuous: false,
                           timestamp: 1, rawUnits: 0) == precise)
    let faster = AxisSettings(mode: .boost, speed: 2, boost: 2)
    let notch = WheelDelta(lines: 1, fixed: 0.1, points: 1)
    #expect(axis.transform(notch, settings: faster, reversed: false, continuous: false,
                           timestamp: 2) == WheelDelta(lines: 2, fixed: 0.2, points: 2))
    #expect(axis.transform(precise, settings: faster, reversed: true, continuous: true,
                           timestamp: 3, rawUnits: 1) == WheelDelta(lines: 0, fixed: -0.6, points: -6))
}

@Test(arguments: [WheelRamp.Curve.gradual: 15.0, .linear: 30.0, .quick: 45.0])
func customRampUsesTheSelectedThresholdsAndShape(curve: WheelRamp.Curve, intermediatePoints: Double) {
    var axis = WheelAxis()
    let settings = AxisSettings(
        mode: .boost, boost: 8, wheelRamp: WheelRamp(startRate: 30, fullRate: 35, curve: curve)
    )
    let notch = WheelDelta(lines: 1, fixed: 0.1, points: 1)
    func scroll(at milliseconds: UInt64) -> Double {
        axis.transform(notch, settings: settings, reversed: false, continuous: false,
                       timestamp: milliseconds * 1_000_000, rawUnits: -1).points
    }

    #expect(scroll(at: 1_000) == 10)
    #expect(scroll(at: 1_020) == intermediatePoints)
    #expect(scroll(at: 1_040) == 90)
    #expect(scroll(at: 1_200) == 10)
}

@Test func customWheelAccumulatesSubLineStepsForLineOnlyApps() {
    var axis = WheelAxis()
    let custom = AxisSettings(mode: .boost, speed: 0.25)
    let notch = WheelDelta(lines: 1, fixed: 0.1, points: 1)
    let output = (1...4).map {
        axis.transform(notch, settings: custom, reversed: false, continuous: false,
                       timestamp: UInt64($0) * 150_000_000, rawUnits: -1)
    }
    #expect(output.map(\.lines) == [0, 0, 0, 1])
    #expect(output.reduce(0) { $0 + $1.fixed } == 1)
}

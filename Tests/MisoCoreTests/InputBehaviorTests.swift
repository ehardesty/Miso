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
    let linear = AxisSettings(speed: 2, acceleration: -1)
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
        notch, settings: AxisSettings(speed: 0.25, acceleration: -1),
        reversed: false, continuous: false, timestamp: 1, rawUnits: 1
    )

    #expect(output == WheelDelta(lines: 1, fixed: 0.25, points: 2.5))
}

@Test func wheelBoostStopsOnAReversalAndAfterIdle() {
    var axis = WheelAxis()
    let notch = WheelDelta(lines: 1, fixed: 1, points: 10)
    let opposite = WheelDelta(lines: -1, fixed: -1, points: -10)
    let boost = AxisSettings(acceleration: 2)
    func feed(_ delta: WheelDelta, at timestamp: UInt64) -> WheelDelta {
        axis.transform(delta, settings: boost, reversed: false, continuous: false, timestamp: timestamp)
    }

    #expect(feed(notch, at: 1_000_000_000) == notch)
    #expect(feed(notch, at: 1_004_000_000).points == 30)
    #expect(feed(opposite, at: 1_008_000_000) == opposite)
    #expect(feed(opposite, at: 2_000_000_000) == opposite)
}

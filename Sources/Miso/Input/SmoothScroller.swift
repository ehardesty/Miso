import AppKit
import MisoCore
import QuartzCore

/// Turns stepped wheel input into continuous pixel scrolling on the input
/// thread. The display link only decides how often motion is sampled. The
/// animators decide where content is at each frame's start time.
final class SmoothScroller: NSObject {
    private static let modifierFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    /// Longer than any frame interval. A running link that misses it has stopped delivering frames.
    private static let stallInterval = 0.25

    private var settings = ScrollSmoothing()
    private var vertical = SmoothedAxis(glide: ScrollSmoothing.defaultGlide)
    private var horizontal = SmoothedAxis(glide: ScrollSmoothing.defaultGlide)
    private var link: CADisplayLink?
    /// A private source with no local-event suppression. Posting from a shared
    /// source by default ignores real mouse movement for 0.25 s after each event.
    private let source: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
        return source
    }()
    private var lastFrame = 0.0
    /// Set when frames stopped arriving. Input passes through until a frame proves the link works.
    private var stalled = false

    var isActive: Bool { settings.isOn && link != nil }

    /// Main thread only, because the link comes from an `NSScreen`.
    static func makeLink(for scroller: SmoothScroller) -> CADisplayLink? {
        guard let screen = NSScreen.main else { return nil }
        let link = screen.displayLink(target: scroller, selector: #selector(frame(_:)))
        link.isPaused = true
        return link
    }

    // Everything below runs on the input thread.

    /// Frames are delivered on the run loop of the thread that attaches the link.
    func attach(_ link: CADisplayLink) {
        let running = self.link?.isPaused == false
        self.link?.invalidate()
        link.isPaused = !running
        lastFrame = CACurrentMediaTime()
        stalled = false
        link.add(to: .current, forMode: .default)
        self.link = link
    }

    func configure(_ settings: ScrollSmoothing) {
        guard self.settings != settings else { return }
        self.settings = settings
        stalled = false
        vertical = SmoothedAxis(glide: settings.glide)
        horizontal = SmoothedAxis(glide: settings.glide)
        link?.isPaused = true
    }

    /// Returns true when the wheel event was consumed.
    func consume(_ event: CGEvent) -> Bool {
        guard isActive, let link else { return false }
        let now = CACurrentMediaTime()
        if !link.isPaused && now - lastFrame > Self.stallInterval {
            stop()
            stalled = true
            // Keep the link running so a working link can clear the stall.
            link.isPaused = false
        }
        // Pass input through rather than swallow it while frames are missing.
        // A cancel may have paused the link, so keep it running until a frame
        // proves it works.
        guard !stalled else {
            link.isPaused = false
            return false
        }
        guard event.flags.intersection(Self.modifierFlags).isEmpty else {
            // Zoom, horizontal shift-scroll, and app shortcuts keep their native events.
            stop()
            return false
        }
        let vertical = Self.lines(event, .scrollWheelEventFixedPtDeltaAxis1,
                                  .scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1)
        let horizontal = Self.lines(event, .scrollWheelEventFixedPtDeltaAxis2,
                                    .scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
        guard vertical != 0 || horizontal != 0 else { return false }
        self.vertical.add(vertical * ScrollSmoothing.pixelsPerLine, at: now)
        self.horizontal.add(horizontal * ScrollSmoothing.pixelsPerLine, at: now)
        if link.isPaused {
            lastFrame = now
            link.isPaused = false
        }
        return true
    }

    /// Discards remaining travel at what has already been posted, so the next step starts from what is shown.
    func stop() {
        vertical.stop()
        horizontal.stop()
        link?.isPaused = true
    }

    /// Ends the glide on each axis the event moves. The other axis keeps its
    /// pending travel, and the link pauses itself once both have drained.
    func cancel(movedBy event: CGEvent) {
        if Self.lines(event, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventDeltaAxis1,
                      .scrollWheelEventPointDeltaAxis1) != 0 { vertical.stop() }
        if Self.lines(event, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventDeltaAxis2,
                      .scrollWheelEventPointDeltaAxis2) != 0 { horizontal.stop() }
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        lastFrame = CACurrentMediaTime()
        stalled = false
        // The frame's start time, not its future display time, so input that
        // arrives after this callback is never later than the sample and is
        // never delayed by a refresh-dependent amount.
        let time = link.timestamp
        let dy = vertical.frame(at: time)
        let dx = horizontal.frame(at: time)
        // New events carry the current cursor location, so the cursor stays free.
        if dy != 0 || dx != 0, let event = CGEvent(
            scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0
        ) {
            ActionDelivery.post(event)
        }
        if vertical.isDrained(at: time) && horizontal.isDrained(at: time) { link.isPaused = true }
    }

    /// Line distance, using the same fallbacks as the wheel transform.
    private static func lines(_ event: CGEvent, _ fixed: CGEventField, _ whole: CGEventField,
                              _ points: CGEventField) -> Double {
        let precise = event.getDoubleValueField(fixed)
        if precise != 0 { return precise }
        let lines = event.getIntegerValueField(whole)
        if lines != 0 { return Double(lines) }
        return event.getDoubleValueField(points) / 10
    }
}

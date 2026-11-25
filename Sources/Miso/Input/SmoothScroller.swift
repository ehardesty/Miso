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
    /// The most pixels one posted event carries.
    private static let maximumStep = 10_000

    private enum ScrollPhase: Int64 {
        case began = 1, changed = 2, ended = 4, cancelled = 8, mayBegin = 128
    }

    private var settings = ScrollSmoothing()
    private var vertical = SmoothedAxis(glide: ScrollSmoothing.defaultGlide)
    private var horizontal = SmoothedAxis(glide: ScrollSmoothing.defaultGlide)
    private var link: CADisplayLink?
    private var lastGestureLocation: CGPoint?
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
    /// Checks for missing frames during a glide, independently of the display
    /// link and of wheel input. It exists only while a glide runs, so an idle
    /// input thread sleeps.
    private var watchdog: Timer?

    var isActive: Bool { settings.enabled && link != nil }

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
        link.isPaused = true
        stalled = false
        link.add(to: .current, forMode: .default)
        self.link = link
        setRunning(running)
    }

    /// Starts or pauses frames, and the watchdog with them. The watchdog's
    /// first check comes one stall interval after the glide starts.
    private func setRunning(_ running: Bool) {
        guard let link else { return }
        if running && link.isPaused {
            lastFrame = CACurrentMediaTime()
            let timer = Timer(timeInterval: Self.stallInterval, repeats: true) { [weak self] _ in
                self?.expireIfStalled()
            }
            RunLoop.current.add(timer, forMode: .default)
            watchdog?.invalidate()
            watchdog = timer
        } else if !running {
            watchdog?.invalidate()
            watchdog = nil
        }
        link.isPaused = !running
    }

    /// Wheel input, frames, and the watchdog share this check. When a running
    /// link has gone a stall interval without a frame, the rest of the glide
    /// posts at once, so no step is lost. Input then passes through until a
    /// frame proves the link works again.
    private func expireIfStalled() {
        guard let link, !link.isPaused, !stalled,
              CACurrentMediaTime() - lastFrame > Self.stallInterval else { return }
        post(vertical.flush(), horizontal.flush())
        finishGesture(.ended)
        stalled = true
        // The link keeps running so a working link can clear the stall.
        watchdog?.invalidate()
        watchdog = nil
    }

    func configure(_ settings: ScrollSmoothing) {
        guard self.settings != settings else { return }
        stop()
        self.settings = settings
        stalled = false
        vertical = SmoothedAxis(glide: settings.glide)
        horizontal = SmoothedAxis(glide: settings.glide)
    }

    /// Returns true when the wheel event was consumed.
    func consume(_ event: CGEvent) -> Bool {
        guard isActive, let link else { return false }
        let now = CACurrentMediaTime()
        expireIfStalled()
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
        let vertical = Self.lines(event, along: .vertical)
        let horizontal = Self.lines(event, along: .horizontal)
        guard vertical != 0 || horizontal != 0 else { return false }
        self.vertical.add(vertical * ScrollSmoothing.pixelsPerLine, at: now)
        self.horizontal.add(horizontal * ScrollSmoothing.pixelsPerLine, at: now)
        setRunning(true)
        return true
    }

    /// Discards remaining travel at what has already been posted, so the next step starts from what is shown.
    func stop() {
        finishGesture(.cancelled)
        vertical.stop()
        horizontal.stop()
        setRunning(false)
    }

    /// Hands off an active gesture to other scrolling input. Unphased glides
    /// can keep any pending travel on the axis that input did not move.
    func cancel(movedBy event: CGEvent) {
        let movesVertical = Self.lines(event, along: .vertical) != 0
        let movesHorizontal = Self.lines(event, along: .horizontal) != 0
        if settings.useGesturePhases {
            let phase = ScrollPhase(rawValue: event.getIntegerValueField(.scrollWheelEventScrollPhase))
            if movesVertical || movesHorizontal || phase == .mayBegin || phase == .began {
                stop()
                return
            }
        }
        if movesVertical { vertical.stop() }
        if movesHorizontal { horizontal.stop() }
    }

    func invalidate() {
        stop()
        link?.invalidate()
        link = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        // A late frame first settles a stall the same way the watchdog would.
        expireIfStalled()
        lastFrame = CACurrentMediaTime()
        stalled = false
        // The frame's start time, not its future display time, so input that
        // arrives after this callback is never later than the sample and is
        // never delayed by a refresh-dependent amount.
        let time = link.timestamp
        post(Int(vertical.frame(at: time)), Int(horizontal.frame(at: time)))
        if vertical.isDrained(at: time) && horizontal.isDrained(at: time) {
            finishGesture(.ended)
            setRunning(false)
        }
    }

    /// Posts the distance in events of at most `maximumStep` pixels per axis.
    private func post(_ dy: Int, _ dx: Int) {
        var remaining = (dy, dx)
        while remaining.0 != 0 || remaining.1 != 0 {
            let y = max(-Self.maximumStep, min(Self.maximumStep, remaining.0))
            let x = max(-Self.maximumStep, min(Self.maximumStep, remaining.1))
            remaining = (remaining.0 - y, remaining.1 - x)
            // New events carry the current cursor location, so the cursor stays free.
            guard let event = makeScrollEvent(y: y, x: x) else { return }
            if settings.useGesturePhases {
                let phase: ScrollPhase = lastGestureLocation == nil ? .began : .changed
                event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
                lastGestureLocation = event.location
            }
            ActionDelivery.post(event)
        }
    }

    private func finishGesture(_ phase: ScrollPhase) {
        guard let location = lastGestureLocation else { return }
        lastGestureLocation = nil
        guard let event = makeScrollEvent(y: 0, x: 0) else { return }
        // The pointer can move away before the last frame or a cancellation.
        event.location = location
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
        ActionDelivery.post(event)
    }

    private func makeScrollEvent(y: Int, x: Int) -> CGEvent? {
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(y), wheel2: Int32(x), wheel3: 0)
    }

    private static func lines(_ event: CGEvent, along axis: ScrollAxis) -> Double {
        let fields = axis.eventFields
        let precise = event.getDoubleValueField(fields.fixed)
        if precise != 0 { return precise }
        let lines = event.getIntegerValueField(fields.lines)
        if lines != 0 { return Double(lines) }
        return event.getDoubleValueField(fields.points) / 10
    }
}

import CoreGraphics
import Foundation
import os

/// A sleeping run loop owns the taps and input state. Work is submitted only
/// when configuration, lifecycle, or a vendor button event changes.
final class EventThread {
    private let runLoop: CFRunLoop

    init() {
        let started = DispatchSemaphore(value: 0)
        let loop = OSAllocatedUnfairLock<CFRunLoop?>(initialState: nil)
        let thread = Thread {
            let runLoop = CFRunLoopGetCurrent()!
            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            let source = CFRunLoopSourceCreate(nil, 0, &context)
            CFRunLoopAddSource(runLoop, source, .defaultMode)
            loop.withLock { $0 = runLoop }
            started.signal()
            CFRunLoopRun()
        }
        thread.name = "Miso Input"
        thread.qualityOfService = .userInteractive
        thread.start()
        started.wait()
        runLoop = loop.withLock { $0! }
    }

    func enqueue(_ work: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }

    deinit { CFRunLoopStop(runLoop) }
}

final class QuartzTap {
    private let port: CFMachPort
    private let source: CFRunLoopSource

    init?(observing types: [CGEventType], callback: CGEventTapCallBack, owner: UnsafeMutableRawPointer) {
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback, userInfo: owner
        ), let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return nil }
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
    }

    func setEnabled(_ enabled: Bool) { CGEvent.tapEnable(tap: port, enable: enabled) }

    deinit {
        CFRunLoopSourceInvalidate(source)
        CFMachPortInvalidate(port)
    }
}

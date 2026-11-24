import AppKit
import MisoCore
import MisoPlatform

enum ActionDelivery {
    static let marker: Int64 = 0x4D6F75736554776B

    static func perform(_ action: MouseAction, at location: CGPoint, navigationPID: pid_t?) {
        switch action {
        case .doNothing:
            break
        case let .mouseButton(number):
            click(number, at: location)
        case let .shortcut(shortcut):
            key(shortcut.keyCode, flags: shortcut.modifiers.eventFlags)
        case .back:
            if let navigationPID, NavigationSwipe.back.schedule(at: location, targetPID: navigationPID) { return }
            click(3, at: location)
        case .forward:
            if let navigationPID, NavigationSwipe.forward.schedule(at: location, targetPID: navigationPID) { return }
            click(4, at: location)
        case .previousSpace:
            systemKey(79)
        case .nextSpace:
            systemKey(81)
        case .missionControl:
            if !MTDockCommand("com.apple.expose.awake" as CFString) { systemKey(32) }
        case .appWindows:
            if !MTDockCommand("com.apple.expose.front.awake" as CFString) { systemKey(33) }
        case .showDesktop:
            if !MTDockCommand("com.apple.showdesktop.awake" as CFString) { systemKey(36) }
        }
    }

    static func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cgSessionEventTap)
    }

    static func mouseType(_ number: UInt8, like type: CGEventType) -> CGEventType {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return number == 0 ? .leftMouseDown : number == 1 ? .rightMouseDown : .otherMouseDown
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return number == 0 ? .leftMouseUp : number == 1 ? .rightMouseUp : .otherMouseUp
        default:
            return number == 0 ? .leftMouseDragged : number == 1 ? .rightMouseDragged : .otherMouseDragged
        }
    }

    static func rewrite(_ event: CGEvent, as number: UInt8) {
        event.type = mouseType(number, like: event.type)
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
    }

    static func mouseEvent(_ number: UInt8, pressed: Bool, at location: CGPoint) -> CGEvent? {
        guard number <= 31, let button = CGMouseButton(rawValue: UInt32(number)) else { return nil }
        return CGEvent(
            mouseEventSource: CGEventSource(stateID: .privateState),
            mouseType: mouseType(number, like: pressed ? .otherMouseDown : .otherMouseUp),
            mouseCursorPosition: location,
            mouseButton: button
        )
    }

    private static func click(_ number: UInt8, at location: CGPoint) {
        guard let down = mouseEvent(number, pressed: true, at: location),
              let up = mouseEvent(number, pressed: false, at: location) else { return }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        post(down)
        post(up)
    }

    private static func systemKey(_ identifier: UInt32) {
        var code: UInt16 = 0
        var flags: UInt32 = 0
        guard MTSymbolicHotKey(identifier, &code, &flags) else { return }
        key(code, flags: CGEventFlags(rawValue: UInt64(flags)))
    }

    private static let modifierKeys: [(CGEventFlags, CGKeyCode)] = [
        (.maskShift, 56), (.maskControl, 59), (.maskAlternate, 58), (.maskCommand, 55)
    ]

    private static func key(_ code: UInt16, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags

        // Bookend added modifiers without releasing keys the user is holding.
        // Build a complete sequence before posting the first event.
        var current = CGEventSource.flagsState(.combinedSessionState)
        var press: [CGEvent] = []
        var release: [CGEvent] = []
        for (flag, key) in modifierKeys where flags.contains(flag) && !current.contains(flag) {
            guard let added = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                  let removed = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
            added.type = .flagsChanged
            removed.type = .flagsChanged
            removed.flags = current
            current.insert(flag)
            added.flags = current
            press.append(added)
            release.append(removed)
        }

        for event in press { post(event) }
        post(down)
        post(up)
        for event in release.reversed() { post(event) }
    }
}

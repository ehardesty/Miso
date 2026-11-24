import AppKit
import MisoCore

enum NavigationSwipe: Int64 {
    case back = 0x04
    case forward = 0x08

    static func target(of app: NSRunningApplication?) -> pid_t? {
        switch app?.bundleIdentifier {
        case "com.apple.finder", "com.apple.Safari": app?.processIdentifier
        default: nil
        }
    }

    init?(button: MouseButton) {
        switch button {
        case .standard(3): self = .back
        case .standard(4): self = .forward
        default: return nil
        }
    }

    // Undocumented Quartz fields from LinearMouse's GestureKit.
    private static let gesture = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))
    private static let hidType = CGEventField(rawValue: 110)
    private static let direction = CGEventField(rawValue: 115)
    private static let phase = CGEventField(rawValue: 132)

    func schedule(at location: CGPoint, targetPID: pid_t) -> Bool {
        guard let gesture = Self.gesture, let hidType = Self.hidType,
              let direction = Self.direction, let phase = Self.phase,
              let begin = CGEvent(source: nil), let end = CGEvent(source: nil)
        else { return false }
        let navigationSwipe: Int64 = 16
        for event in [begin, end] {
            event.type = gesture
            event.location = location
            event.flags = []
            event.setIntegerValueField(hidType, value: navigationSwipe)
        }
        begin.setIntegerValueField(direction, value: rawValue)
        begin.setIntegerValueField(phase, value: 1)
        end.setIntegerValueField(phase, value: 4)
        // Safari needs session-wide posting, so recheck focus before sending.
        DispatchQueue.main.async {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else { return }
            ActionDelivery.post(begin)
            ActionDelivery.post(end)
        }
        return true
    }
}

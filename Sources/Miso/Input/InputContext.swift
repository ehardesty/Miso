import AppKit
import MisoCore

extension Modifiers {
    init(flags: CGEventFlags) {
        self = []
        if flags.contains(.maskShift) { insert(.shift) }
        if flags.contains(.maskControl) { insert(.control) }
        if flags.contains(.maskAlternate) { insert(.option) }
        if flags.contains(.maskCommand) { insert(.command) }
    }

    var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}

struct InputContext: Equatable {
    var settings = Settings()
    var mouseSenders: [UInt64: String] = [:]
    var vendorIDs: Set<String> = []
    var app: String?

    var nativeIDs: Set<String> { Set(mouseSenders.values) }

    func profile(device: String) -> InputProfile {
        settings.profile(device: device, app: app)
    }
}

enum InputStatus: Equatable {
    case stopped, permissionRequired, listening, unavailable(String)
}

struct VendorButtonEvent {
    let deviceID: String
    let button: MouseButton
    let pressed: Bool
}

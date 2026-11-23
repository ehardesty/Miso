import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var enabled = true
    public var global = InputProfile()
    public var deviceProfiles: [String: ProfileOverrides] = [:]
    public var appProfiles: [String: ProfileOverrides] = [:]

    public init() {}

    public func profile(device: String?, app: String?) -> InputProfile {
        var result = global
        if let device { deviceProfiles[device]?.apply(to: &result) }
        if let app { appProfiles[app]?.apply(to: &result) }
        return result
    }
}

public struct InputProfile: Codable, Equatable, Sendable {
    public var pointer = AxisSettings()
    public var verticalWheel = AxisSettings()
    public var horizontalWheel = AxisSettings()
    public var reverseVertical = false
    public var reverseHorizontal = false
    public var swipeThreshold = 50.0
    public var mappings: [ButtonMapping] = []

    public init() {}

    public var changesWheel: Bool {
        verticalWheel.changesWheel || horizontalWheel.changesWheel
            || reverseVertical || reverseHorizontal
    }

    public func mapping(for button: MouseButton, modifiers: Modifiers) -> ButtonMapping? {
        mappings.first { $0.button == button && $0.modifiers == modifiers && $0.isConfigured }
    }
}

public enum AccelerationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case linear, system, boost

    public var id: Self { self }
}

public struct AxisSettings: Codable, Equatable, Sendable {
    public static let wheelBoostRange = 1.0...9.0

    public var mode = AccelerationMode.system
    public var linearSpeed = 1.0
    public var systemSpeed = 1.0
    public var boostSpeed = 1.0
    public var boost = 0.5
    public var wheelRamp = WheelRamp()

    public init(mode: AccelerationMode = .system, speed: Double = 1, boost: Double = 0.5,
                wheelRamp: WheelRamp = WheelRamp()) {
        self.mode = mode
        self[keyPath: Self.speedField(for: mode)] = speed
        self.boost = boost
        self.wheelRamp = wheelRamp
    }

    public static func speedField(for mode: AccelerationMode) -> WritableKeyPath<Self, Double> {
        switch mode {
        case .linear: \.linearSpeed
        case .system: \.systemSpeed
        case .boost: \.boostSpeed
        }
    }

    public var speed: Double {
        switch mode {
        case .linear: linearSpeed
        case .system: systemSpeed
        case .boost: boostSpeed
        }
    }

    public var acceleration: Double {
        switch mode {
        case .linear: -1
        case .system: 0
        case .boost: boost
        }
    }

    /// Resolve only the fields the native pointer settings can apply.
    public var activePointer: AxisSettings {
        AxisSettings(mode: mode, speed: speed, boost: mode == .boost ? accelerationAmount : 0.5)
    }

    public var changesWheel: Bool { speed != 1 || acceleration != 0 }

    public var speedMultiplier: Double { speed.isFinite ? min(4, max(0.25, speed)) : 1 }
    public var accelerationAmount: Double { acceleration.isFinite ? min(2, max(-1, acceleration)) : 0 }
    public var wheelAccelerationAmount: Double {
        guard acceleration.isFinite else { return 0 }
        guard acceleration > 0 else { return max(-1, acceleration) }
        return min(Self.wheelBoostRange.upperBound, max(Self.wheelBoostRange.lowerBound, acceleration))
    }
}

public enum MouseButton: Codable, Equatable, Hashable, Sendable {
    case standard(UInt8)
    case logitech(UInt16)

    public var isPrimary: Bool { self == .standard(0) || self == .standard(1) }

    public var title: String {
        switch self {
        case .standard(0): "Left Click"
        case .standard(1): "Right Click"
        case .standard(2): "Middle Click"
        case .standard(3): "Back Button"
        case .standard(4): "Forward Button"
        case let .standard(number): "Button \(Int(number) + 1)"
        case .logitech(0x00C3), .logitech(0x00D0): "Gesture Button"
        case .logitech(0x01A0): "Haptic Sense Panel"
        case let .logitech(cid): String(format: "Logitech Control 0x%04X", cid)
        }
    }
}

public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
}

public struct Shortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum MouseAction: Codable, Equatable, Hashable, Sendable {
    case doNothing
    case mouseButton(UInt8)
    case shortcut(Shortcut)
    case back, forward, previousSpace, nextSpace, missionControl, appWindows, showDesktop

    public var title: String {
        switch self {
        case .doNothing: "Do Nothing"
        case let .mouseButton(number): MouseButton.standard(number).title
        case .shortcut: "Keyboard Shortcut"
        case .back: "Back"
        case .forward: "Forward"
        case .previousSpace: "Previous Space"
        case .nextSpace: "Next Space"
        case .missionControl: "Mission Control"
        case .appWindows: "App Exposé"
        case .showDesktop: "Show Desktop"
        }
    }
}

public enum SwipeDirection: String, CaseIterable, Codable, Hashable, Sendable {
    case up, down, left, right
}

public struct ButtonMapping: Codable, Equatable, Identifiable, Sendable {
    struct Trigger: Hashable {
        let button: MouseButton
        let modifiers: Modifiers
    }

    public var id = UUID()
    public var button: MouseButton
    public var modifiers: Modifiers
    public var tap: MouseAction?
    public var swipes: [SwipeDirection: MouseAction]

    public init(
        button: MouseButton,
        modifiers: Modifiers = [],
        tap: MouseAction? = nil,
        swipes: [SwipeDirection: MouseAction] = [:]
    ) {
        self.button = button
        self.modifiers = modifiers
        self.tap = tap
        self.swipes = swipes
    }

    public var isConfigured: Bool { tap != nil || !swipes.isEmpty }

    var trigger: Trigger { Trigger(button: button, modifiers: modifiers) }
}

public struct MouseDevice: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var transport: String
    public var dpi: MouseDPI?
    public var buttons: [MouseButton]

    public init(id: String, name: String, transport: String, dpi: MouseDPI? = nil, buttons: [MouseButton] = []) {
        self.id = id
        self.name = name
        self.transport = transport
        self.dpi = dpi
        self.buttons = buttons
    }
}

public struct MouseDPI: Equatable, Sendable {
    public var current: Int
    public var minimum: Int
    public var maximum: Int
    public var step: Int
    public var values: [Int]

    public init(current: Int, minimum: Int, maximum: Int, step: Int, values: [Int] = []) {
        self.current = current
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
        self.values = values
    }

    public func supports(_ value: Int) -> Bool {
        guard value >= minimum, value <= maximum else { return false }
        if !values.isEmpty { return values.contains(value) }
        return step > 0 && (value - minimum) % step == 0
    }
}

import Foundation

/// Absent fields inherit from the less specific profile. Keeping only edited
/// fields preserves later global changes in unrelated settings.
public struct ProfileOverrides: Codable, Equatable, Sendable {
    public struct Axis: Codable, Equatable, Sendable {
        public var mode: AccelerationMode?
        public var linearSpeed: Double?
        public var systemSpeed: Double?
        public var boostSpeed: Double?
        public var boost: Double?
        public var wheelRamp: WheelRamp?

        public static func speedField(for mode: AccelerationMode) -> WritableKeyPath<Self, Double?> {
            switch mode {
            case .linear: \.linearSpeed
            case .system: \.systemSpeed
            case .boost: \.boostSpeed
            }
        }

        func apply(to axis: inout AxisSettings) {
            if let mode { axis.mode = mode }
            if let linearSpeed { axis.linearSpeed = linearSpeed }
            if let systemSpeed { axis.systemSpeed = systemSpeed }
            if let boostSpeed { axis.boostSpeed = boostSpeed }
            if let boost { axis.boost = boost }
            if let wheelRamp { axis.wheelRamp = wheelRamp }
        }
    }

    public var pointer = Axis()
    public var verticalWheel = Axis()
    public var horizontalWheel = Axis()
    public var reverseVertical: Bool?
    public var reverseHorizontal: Bool?
    public var swipeThreshold: Double?
    private var mappings: [ButtonMapping]?
    private var editedButtons: [ButtonMapping]?

    public var appButtonMappings: [ButtonMapping] {
        get { editedButtons ?? [] }
        set { editedButtons = newValue.isEmpty ? nil : newValue }
    }

    public init() {}

    public mutating func setDeviceButtonMappings(_ value: [ButtonMapping], inheriting inherited: [ButtonMapping]) {
        mappings = value == inherited ? nil : value
    }

    public func apply(to profile: inout InputProfile) {
        pointer.apply(to: &profile.pointer)
        verticalWheel.apply(to: &profile.verticalWheel)
        horizontalWheel.apply(to: &profile.horizontalWheel)
        if let reverseVertical { profile.reverseVertical = reverseVertical }
        if let reverseHorizontal { profile.reverseHorizontal = reverseHorizontal }
        if let swipeThreshold { profile.swipeThreshold = swipeThreshold }
        if let mappings { profile.mappings = mappings }
        if let editedButtons {
            let configured = editedButtons.filter(\.isConfigured)
            let triggers = Set(configured.map(\.trigger))
            profile.mappings.removeAll { triggers.contains($0.trigger) }
            profile.mappings.append(contentsOf: configured)
        }
    }
}

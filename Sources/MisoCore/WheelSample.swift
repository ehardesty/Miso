/// One wheel event on a single axis as Miso's runtime handled it, for the live curve test.
public struct WheelSample: Equatable, Sendable {
    public enum Input: Equatable, Sendable {
        /// Stepped wheel input that Custom can ramp.
        case steps
        /// Continuous or step-less input: Custom applies only the slow-scroll distance.
        case continuous, noSteps
        /// Phased trackpad or Magic Mouse scrolling, which Miso leaves to macOS.
        case gesture
        /// Movement only on the other wheel axis.
        case otherAxis
        /// A sender Miso has not matched to a mouse.
        case unknownMouse
        /// No wheel transformations are active for the running profile.
        case wheelInactive
    }

    public enum Fit: Equatable, Sendable {
        case matches
        /// The same wheel now uses the displayed response. Apply it to the previously measured rate.
        case preview
        case otherMouse
        /// The runtime used settings that differ from the curve, such as a device or app override.
        case otherSettings
    }

    public var input: Input
    public var device: String?
    public var app: String?
    /// The axis settings the runtime resolved for this event.
    public var settings: AxisSettings?
    /// Estimated rate in steps/s behind the response; zero when the event did not ramp.
    public var rate: Double

    public init(input: Input, device: String? = nil, app: String? = nil,
                settings: AxisSettings? = nil, rate: Double = 0) {
        self.input = input
        self.device = device
        self.app = app
        self.settings = settings
        self.rate = rate
    }
}

extension Settings {
    /// Whether `sample` measured `curve`, drawn for `device` or, when nil, for any mouse.
    public func fit(
        of sample: WheelSample, to curve: AxisSettings,
        axis: KeyPath<InputProfile, AxisSettings>, device: String?
    ) -> WheelSample.Fit {
        guard let sampleDevice = sample.device, let used = sample.settings else { return .otherMouse }
        if let device, device != sampleDevice { return .otherMouse }
        let current = profile(device: sampleDevice, app: sample.app)[keyPath: axis]
        guard current.hasSameWheelResponse(as: curve) else { return .otherSettings }
        if used.hasSameWheelResponse(as: curve) { return .matches }
        return sample.input == .steps && used.wheelAccelerationAmount > 0 ? .preview : .otherSettings
    }
}

extension AxisSettings {
    public func hasSameWheelResponse(as other: AxisSettings) -> Bool {
        mode == other.mode && speedMultiplier == other.speedMultiplier
            && wheelAccelerationAmount == other.wheelAccelerationAmount
            && (mode != .boost || wheelRamp == other.wheelRamp)
    }
}

import CoreGraphics
import MisoCore

enum ScrollAxis: Hashable {
    case vertical, horizontal

    var profileFields: (
        settings: WritableKeyPath<InputProfile, AxisSettings>,
        overrides: WritableKeyPath<ProfileOverrides, ProfileOverrides.Axis>,
        reverse: WritableKeyPath<InputProfile, Bool>,
        reverseOverride: WritableKeyPath<ProfileOverrides, Bool?>
    ) {
        switch self {
        case .vertical: (\.verticalWheel, \.verticalWheel, \.reverseVertical, \.reverseVertical)
        case .horizontal: (\.horizontalWheel, \.horizontalWheel, \.reverseHorizontal, \.reverseHorizontal)
        }
    }

    func tuning(in profile: InputProfile) -> (settings: AxisSettings, reversed: Bool) {
        switch self {
        case .vertical: (profile.verticalWheel, profile.reverseVertical)
        case .horizontal: (profile.horizontalWheel, profile.reverseHorizontal)
        }
    }

    var eventFields: (lines: CGEventField, fixed: CGEventField, points: CGEventField) {
        switch self {
        case .vertical:
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1)
        case .horizontal:
            (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
        }
    }
}

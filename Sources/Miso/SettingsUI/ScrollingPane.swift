import MisoCore
import SwiftUI

struct ScrollingPane: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope

    var body: some View {
        Form {
            WheelSections(
                model: model, scope: scope, title: "Vertical Wheel", symbol: "arrow.up.and.down",
                axis: \.verticalWheel, overrides: \.verticalWheel,
                reverse: \.reverseVertical, reverseOverride: \.reverseVertical, showsNotes: true
            )
            WheelSections(
                model: model, scope: scope, title: "Horizontal Wheel", symbol: "arrow.left.and.right",
                axis: \.horizontalWheel, overrides: \.horizontalWheel,
                reverse: \.reverseHorizontal, reverseOverride: \.reverseHorizontal, showsNotes: false
            )
        }
        .formStyle(.grouped)
    }
}

/// A wheel's settings, followed by its Custom response and live test when Custom is in use.
private struct WheelSections: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope
    let title: String
    let symbol: String
    let axis: WritableKeyPath<InputProfile, AxisSettings>
    let overrides: WritableKeyPath<ProfileOverrides, ProfileOverrides.Axis>
    let reverse: WritableKeyPath<InputProfile, Bool>
    let reverseOverride: WritableKeyPath<ProfileOverrides, Bool?>
    let showsNotes: Bool

    var body: some View {
        Section {
            WheelAxisControls(model: model, scope: scope, axis: axis, overrides: overrides)
            ProfileControl(model: model, scope: scope, field: reverse,
                           overrideField: reverseOverride, overrideTitle: "Override Direction") {
                Toggle("Reverse direction", isOn: $0)
            }
        } header: {
            Label(title, systemImage: symbol)
        } footer: {
            if showsNotes {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In Custom, each notch scrolls the distance you set when you turn the wheel slowly. Turn the wheel faster to scroll farther per notch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ScopeNote(model: model, scope: scope)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
        }
        if model.modes(for: scope, axis: axis).contains(.boost) {
            // A separate live test for each wheel and scope.
            WheelCurvePanel(model: model, scope: scope, axis: axis).id(PanelID(scope: scope, axis: axis))
        }
    }
}

private struct PanelID: Hashable {
    let scope: SettingsScope
    let axis: KeyPath<InputProfile, AxisSettings>
}

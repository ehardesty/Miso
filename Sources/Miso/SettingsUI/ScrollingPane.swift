import SwiftUI

struct ScrollingPane: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope

    var body: some View {
        Form {
            SmoothScrollingSection(model: model, scope: scope)
            WheelSections(model: model, scope: scope, axis: .vertical)
            WheelSections(model: model, scope: scope, axis: .horizontal)
        }
        .formStyle(.grouped)
    }
}

private struct WheelSections: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope
    let axis: ScrollAxis

    var body: some View {
        let fields = axis.profileFields
        Section {
            WheelAxisControls(model: model, scope: scope, axis: axis)
            ProfileControl(model: model, scope: scope, field: fields.reverse,
                           overrideField: fields.reverseOverride, overrideTitle: "Override Direction") {
                Toggle("Reverse direction", isOn: $0)
            }
        } header: {
            Label(
                axis == .vertical ? "Vertical Wheel" : "Horizontal Wheel",
                systemImage: axis == .vertical ? "arrow.up.and.down" : "arrow.left.and.right"
            )
        } footer: {
            if axis == .vertical {
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
        if model.modes(for: scope, axis: fields.settings).contains(.boost) {
            WheelCurvePanel(model: model, scope: scope, axis: axis).id(PanelID(scope: scope, axis: axis))
        }
    }
}

private struct PanelID: Hashable {
    let scope: SettingsScope
    let axis: ScrollAxis
}

import MisoCore
import SwiftUI

struct ScrollingPane: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope

    var body: some View {
        Form {
            Section {
                WheelAxisControls(model: model, scope: scope, axis: \.verticalWheel, overrides: \.verticalWheel)
                ProfileControl(model: model, scope: scope, field: \.reverseVertical,
                               overrideField: \.reverseVertical, overrideTitle: "Override Direction") {
                    Toggle("Reverse direction", isOn: $0)
                }
            } header: {
                Label("Vertical Wheel", systemImage: "arrow.up.and.down")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom sets the distance for slow wheel steps and adds a capped boost for fast scrolling. With continuous wheels or missing step data, Custom scales macOS scrolling using the distance setting.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ScopeNote(model: model, scope: scope)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
            Section {
                WheelAxisControls(model: model, scope: scope, axis: \.horizontalWheel, overrides: \.horizontalWheel)
                ProfileControl(model: model, scope: scope, field: \.reverseHorizontal,
                               overrideField: \.reverseHorizontal, overrideTitle: "Override Direction") {
                    Toggle("Reverse direction", isOn: $0)
                }
            } header: {
                Label("Horizontal Wheel", systemImage: "arrow.left.and.right")
            }
        }
        .formStyle(.grouped)
    }
}

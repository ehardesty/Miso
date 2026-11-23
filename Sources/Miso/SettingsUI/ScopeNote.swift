import MisoCore
import SwiftUI

/// Explains where edits land when a device or app is selected.
struct ScopeNote: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope

    var body: some View {
        if let text {
            Label(text, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }

    private var text: String? {
        switch scope {
        case .global: nil
        case .device: "Changes here apply only to \(model.title(for: scope)). Other settings follow All Devices & Apps."
        case .app:
            "Changes here apply while \(model.title(for: scope)) is frontmost. "
                + "Settings you haven't changed here come from the mouse or All Devices & Apps."
        }
    }
}

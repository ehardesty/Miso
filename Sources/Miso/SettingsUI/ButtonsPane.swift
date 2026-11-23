import MisoCore
import SwiftUI

struct ButtonsPane: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope

    var body: some View {
        let mappings = model.mappingsBinding(for: scope)
        ScrollViewReader { proxy in
            Form {
                Section {
                    ButtonCaptureRow(model: model) { button in
                        let (id, note) = Self.reveal(button, in: &mappings.wrappedValue)
                        if let id {
                            // Wait one pass so a newly added section exists before scrolling to it.
                            DispatchQueue.main.async { withAnimation { proxy.scrollTo(id, anchor: .top) } }
                        }
                        return note
                    }
                    ProfileControl(model: model, scope: scope, field: \.swipeThreshold,
                                   overrideField: \.swipeThreshold, overrideTitle: "Override Swipe Distance") {
                        swipeDistance($0)
                    }
                } footer: {
                    ScopeNote(model: model, scope: scope)
                }
                if mappings.wrappedValue.isEmpty {
                    Section {
                        Text(isAppScope
                             ? "This app inherits its button mappings. Press a button to set an app-specific mapping."
                             : "All buttons behave normally. Press a button to change its click or assign swipe actions.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(mappings) { $mapping in
                    MappingEditor(mapping: $mapping, isAppOverride: isAppScope) {
                        let id = mapping.id
                        mappings.wrappedValue.removeAll { $0.id == id }
                    }
                    .id(mapping.id)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var isAppScope: Bool {
        if case .app = scope { true } else { false }
    }

    private func swipeDistance(_ distance: Binding<Double>) -> some View {
        LabeledContent("Swipe distance") {
            HStack(spacing: 10) {
                Slider(value: distance, in: 10...200, step: 5) {
                    Text("Swipe distance")
                }
                .labelsHidden()
                .accessibilityValue("\(Int(distance.wrappedValue)) points")
                Text("\(Int(distance.wrappedValue)) pt")
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Adds a mapping for a captured button, or finds its existing unmodified one.
    /// Returns the mapping to reveal and an inline note when nothing new was added.
    private static func reveal(_ button: MouseButton, in mappings: inout [ButtonMapping]) -> (UUID?, String?) {
        guard !button.isPrimary else { return (nil, "\(button.title) can't be remapped.") }
        if let existing = mappings.first(where: { $0.button == button && $0.modifiers.isEmpty }) {
            return (existing.id, "\(button.title) is already mapped.")
        }
        let mapping = ButtonMapping(button: button)
        mappings.append(mapping)
        return (mapping.id, nil)
    }
}

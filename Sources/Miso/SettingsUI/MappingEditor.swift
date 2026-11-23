import MisoCore
import SwiftUI

struct MappingEditor: View {
    @Binding var mapping: ButtonMapping
    let isAppOverride: Bool
    let onDelete: () -> Void

    var body: some View {
        Section {
            ActionPicker(
                title: "Click",
                symbol: "hand.tap",
                defaultTitle: defaultTapTitle,
                action: $mapping.tap
            )
            ForEach(SwipeDirection.allCases, id: \.self) { direction in
                ActionPicker(
                    title: "Hold and move \(direction.title.lowercased())",
                    symbol: direction.symbol,
                    defaultTitle: "No Action",
                    action: swipe(direction)
                )
            }
        } header: {
            HStack {
                Text(isVendorControl ? mapping.button.title : KeyNames.symbols(for: mapping.modifiers) + mapping.button.title)
                Spacer()
                if !isVendorControl {
                    ModifierToggles(modifiers: $mapping.modifiers)
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: isAppOverride ? "arrow.uturn.backward" : "trash")
                }
                .buttonStyle(.borderless)
                .help(isAppOverride ? "Use inherited mapping" : "Remove mapping")
                .accessibilityLabel(isAppOverride
                                    ? "Use inherited mapping for \(mapping.button.title)"
                                    : "Remove \(mapping.button.title) mapping")
            }
        } footer: {
            if isVendorControl {
                Label("While mapped, this control's built-in Logitech action is replaced.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var isVendorControl: Bool {
        if case .logitech = mapping.button { true } else { false }
    }

    private var defaultTapTitle: String {
        switch mapping.button {
        case .standard(let index): "\(MouseAction.mouseButton(index).title) (Default)"
        case .logitech: "No Action"
        }
    }

    private func swipe(_ direction: SwipeDirection) -> Binding<MouseAction?> {
        Binding(
            get: { mapping.swipes[direction] },
            set: { mapping.swipes[direction] = $0 }
        )
    }
}

/// Compact ⌃⌥⇧⌘ toggles. A mapping with modifiers only fires while they are held.
private struct ModifierToggles: View {
    @Binding var modifiers: Modifiers

    var body: some View {
        HStack(spacing: 2) {
            toggle("⌃", "Control", .control)
            toggle("⌥", "Option", .option)
            toggle("⇧", "Shift", .shift)
            toggle("⌘", "Command", .command)
        }
        .help("Only use this mapping while these keys are held")
    }

    private func toggle(_ glyph: String, _ name: String, _ flag: Modifiers) -> some View {
        Toggle(isOn: Binding(
            get: { modifiers.contains(flag) },
            set: { if $0 { modifiers.insert(flag) } else { modifiers.remove(flag) } }
        )) {
            Text(glyph).frame(width: 14)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .accessibilityLabel(name)
    }
}

extension SwipeDirection {
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }
}

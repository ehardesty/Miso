import MisoCore
import SwiftUI

/// Picks an outcome for a tap or swipe. `nil` means the button's default behavior.
struct ActionPicker: View {
    let title: String
    let symbol: String
    /// Label for the `nil` choice, e.g. "Middle Click" or "No Action".
    let defaultTitle: String
    @Binding var action: MouseAction?
    @State private var recording = false

    var body: some View {
        Picker(selection: choice) {
            Text(defaultTitle).tag(Choice.standard)
            Divider()
            ForEach(Self.presets, id: \.self) { action in
                Text(action.title).tag(Choice.action(action))
            }
            Divider()
            if case .shortcut(let shortcut)? = action {
                Text(KeyNames.title(for: shortcut)).tag(Choice.action(.shortcut(shortcut)))
            }
            Text("Keyboard Shortcut…").tag(Choice.recordShortcut)
        } label: {
            Label(title, systemImage: symbol)
        }
        .popover(isPresented: $recording, arrowEdge: .trailing) {
            ShortcutRecorder(
                onRecord: { action = .shortcut($0); recording = false },
                onCancel: { recording = false }
            )
        }
    }

    private var choice: Binding<Choice> {
        Binding(
            get: { action.map(Choice.action) ?? .standard },
            set: { choice in
                switch choice {
                case .standard: action = nil
                case .action(let value): action = value
                case .recordShortcut: recording = true
                }
            }
        )
    }

    private enum Choice: Hashable {
        case standard, recordShortcut
        case action(MouseAction)
    }

    static let presets: [MouseAction] = [
        .doNothing,
        .mouseButton(0), .mouseButton(1), .mouseButton(2), .mouseButton(3), .mouseButton(4),
        .back, .forward,
        .previousSpace, .nextSpace, .missionControl, .appWindows, .showDesktop,
    ]
}

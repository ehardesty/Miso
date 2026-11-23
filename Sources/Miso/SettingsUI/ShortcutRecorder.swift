import AppKit
import MisoCore
import SwiftUI

/// Captures the next key press in this window. Escape cancels.
struct ShortcutRecorder: View {
    let onRecord: (Shortcut) -> Void
    let onCancel: () -> Void
    @State private var monitor: Any?
    @State private var liveModifiers: Modifiers = []

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Press a Shortcut")
                .font(.headline)
            Text(liveModifiers.isEmpty ? "Esc to cancel" : KeyNames.symbols(for: liveModifiers))
                .font(.title3.monospaced())
                .foregroundStyle(.secondary)
                .frame(minHeight: 24)
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 240)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let modifiers = Modifiers(event.modifierFlags)
            if event.type == .flagsChanged {
                liveModifiers = modifiers
                return nil
            }
            if event.keyCode == 53, modifiers.isEmpty {
                onCancel()
            } else {
                onRecord(Shortcut(keyCode: event.keyCode, modifiers: modifiers))
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.command) { insert(.command) }
    }
}

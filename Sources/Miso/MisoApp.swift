import AppKit
import SwiftUI

@main
@MainActor
struct MisoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private static let menuBarIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MisoMenuBar", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 20, height: 20)
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarControls(model: delegate.model)
        } label: {
            Label {
                Text("Miso")
            } icon: {
                if let icon = Self.menuBarIcon {
                    Image(nsImage: icon)
                } else {
                    Image(systemName: "computermouse")
                }
            }
            .labelStyle(.iconOnly)
        }

        Window("Miso", id: "settings") {
            SettingsRootView(model: delegate.model)
        }
        .defaultSize(width: 830, height: 640)
        .windowResizability(.contentMinSize)
    }
}

private struct MenuBarControls: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Enable Miso", isOn: $model.settings.enabled)
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Miso") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = SettingsModel()
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start handling input even when the settings window is closed.
        _ = model
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        model.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

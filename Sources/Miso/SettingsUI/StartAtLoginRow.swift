import AppKit
import OSLog
import ServiceManagement
import SwiftUI

struct StartAtLoginRow: View {
    @State private var status = SMAppService.Status.notRegistered
    @State private var updateFailed = false

    var body: some View {
        Toggle(isOn: Binding(get: { isRegistered }, set: setRegistered)) {
            Label("Start at Login", systemImage: "clock")
        }
        .toggleStyle(.switch)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }

        if status == .requiresApproval || updateFailed {
            LabeledContent {
                Button("Open Login Items", action: SMAppService.openSystemSettingsLoginItems)
            } label: {
                Text(updateFailed ? "Couldn’t change Start at Login."
                     : "Allow Miso in System Settings to start it at login.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    private func refresh() {
        let current = SMAppService.mainApp.status
        if current != status { updateFailed = false }
        status = current
    }

    private func setRegistered(_ enabled: Bool) {
        refresh()
        updateFailed = false
        guard enabled != isRegistered else { return }

        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            updateFailed = true
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Miso", category: "LoginItem")
                .error("Failed to update login item: \(error.localizedDescription)")
        }
        status = service.status
        if enabled == isRegistered { updateFailed = false }
    }
}

import AppKit
import MisoCore
import SwiftUI

struct StatusPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.settings.enabled) {
                    InputStatusLabel(status: model.status, enabled: model.settings.enabled)
                }
                .toggleStyle(.switch)
                StartAtLoginRow()
                if let issue = model.logitechIssue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Remaps buttons and sends shortcuts.",
                    symbol: "accessibility",
                    granted: model.accessibilityAllowed,
                    request: model.requestAccessibility
                )
                PermissionRow(
                    title: "Input Monitoring",
                    detail: "Reads mouse movement, wheel and buttons.",
                    symbol: "hand.raised",
                    granted: model.inputMonitoringAllowed,
                    request: model.requestInputMonitoring
                )
            } header: {
                HStack {
                    Text("Permissions")
                    Spacer()
                    Button("Check Again", action: model.refreshPermissions)
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
            Section("Mice") {
                if model.devices.isEmpty {
                    Label("No supported mouse connected", systemImage: "computermouse")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.devices) { DeviceRow(device: $0) }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: model.refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }
}

private struct InputStatusLabel: View {
    let status: InputStatus
    let enabled: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Miso").font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var detail: String {
        guard enabled else { return "Off. Your mouse uses macOS defaults." }
        switch status {
        case .listening: return "Active"
        case .stopped: return "Starting…"
        case .permissionRequired: return "Waiting for permission"
        case .unavailable(let reason): return reason
        }
    }

    private var symbol: String {
        guard enabled else { return "pause.circle.fill" }
        switch status {
        case .listening: return "checkmark.circle.fill"
        case .stopped: return "circle.dotted"
        case .permissionRequired: return "lock.circle.fill"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        guard enabled else { return .secondary }
        switch status {
        case .listening: return .green
        case .stopped: return .secondary
        case .permissionRequired: return .orange
        case .unavailable: return .red
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow…", action: request)
            }
        } label: {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                Image(systemName: symbol)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(granted ? "Allowed" : "Not allowed")
    }
}

private struct DeviceRow: View {
    let device: MouseDevice

    var body: some View {
        LabeledContent {
            if let dpi = device.dpi {
                Text("\(dpi.current) DPI").monospacedDigit()
            }
        } label: {
            Label {
                Text(device.name)
                Text(device.transport)
            } icon: {
                Image(systemName: "computermouse.fill")
            }
        }
    }
}

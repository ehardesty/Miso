import MisoCore
import SwiftUI

struct PointerPane: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope

    var body: some View {
        Form {
            Section {
                AxisControls(model: model, scope: scope, axis: \.pointer, overrides: \.pointer)
            } header: {
                Text("Tracking")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let issue = model.pointerIssue {
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                    ScopeNote(model: model, scope: scope)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
            dpiSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var dpiSection: some View {
        switch scope {
        case .global:
            Section {
                if model.devices.isEmpty {
                    Text("No supported mouse connected.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.devices) { device in
                    DPIRow(model: model, device: device, showsName: true)
                }
                DPIErrorText(model: model)
            } header: {
                Text("Sensor Resolution")
            } footer: {
                DPIHint(model: model)
            }
        case .device(let id):
            Section {
                if let device = model.devices.first(where: { $0.id == id }) {
                    DPIRow(model: model, device: device, showsName: false)
                } else {
                    Text("Connect this mouse to change its resolution.")
                        .foregroundStyle(.secondary)
                }
                DPIErrorText(model: model)
            } header: {
                Text("Sensor Resolution")
            } footer: {
                DPIHint(model: model)
            }
        case .app:
            EmptyView()
        }
    }
}

private struct DPIHint: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        if model.devices.contains(where: { $0.dpi != nil }) {
            Text("With acceleration Off, sensor resolution is the most reliable way to change physical tracking.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }
}

private struct DPIErrorText: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        if let error = model.dpiError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
        }
    }
}

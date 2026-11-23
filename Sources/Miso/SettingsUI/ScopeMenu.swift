import MisoCore
import SwiftUI

struct ScopeMenu: View {
    @ObservedObject var model: SettingsModel
    @Binding var scope: SettingsScope

    var body: some View {
        Menu {
            Picker("Settings For", selection: $scope) {
                Label("All Devices & Apps", systemImage: "globe").tag(SettingsScope.global)
            }
            .pickerStyle(.inline)
            if !deviceIDs.isEmpty {
                Picker("Mice", selection: $scope) {
                    ForEach(deviceIDs, id: \.self) { id in
                        Label(model.title(for: .device(id)), systemImage: "computermouse")
                            .tag(SettingsScope.device(id))
                    }
                }
                .pickerStyle(.inline)
            }
            if !appIDs.isEmpty {
                Picker("Apps", selection: $scope) {
                    ForEach(appIDs, id: \.self) { id in
                        Label(model.appName(for: id), systemImage: "app")
                            .tag(SettingsScope.app(id))
                    }
                }
                .pickerStyle(.inline)
            }
            Divider()
            Button("Add App…") {
                if let id = model.addAppProfile() { scope = .app(id) }
            }
            if case .app(let id) = scope {
                Button("Remove \(model.appName(for: id))", role: .destructive) {
                    scope = .global
                    model.removeAppProfile(id)
                }
            }
        } label: {
            Label(model.title(for: scope), systemImage: symbol)
                .labelStyle(.titleAndIcon)
        }
        .help("Choose which mouse or app these settings apply to")
        .accessibilityLabel("Settings for \(model.title(for: scope))")
    }

    private var symbol: String {
        switch scope {
        case .global: "globe"
        case .device: "computermouse"
        case .app: "app"
        }
    }

    private var deviceIDs: [String] {
        var ids = model.devices.map(\.id)
        for id in model.settings.deviceProfiles.keys.sorted() where !ids.contains(id) { ids.append(id) }
        return ids
    }

    private var appIDs: [String] {
        model.settings.appProfiles.keys.sorted {
            model.appName(for: $0).localizedStandardCompare(model.appName(for: $1)) == .orderedAscending
        }
    }
}

struct ResetProfileButton: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope
    @State private var confirming = false

    var body: some View {
        Button {
            confirming = true
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
        .help("Reset settings for \(model.title(for: scope))")
        .confirmationDialog(message, isPresented: $confirming) {
            Button("Reset", role: .destructive) { model.resetProfile(scope) }
        }
    }

    private var message: String {
        switch scope {
        case .global: "Reset pointer, scrolling and button settings to defaults?"
        case .device: "Reset \(model.title(for: scope)) to match All Devices & Apps?"
        case .app: "Reset \(model.title(for: scope)) to use the mouse and All Devices & Apps settings?"
        }
    }
}

import MisoCore
import SwiftUI

extension SettingsModel {
    func mappingsBinding(for scope: SettingsScope) -> Binding<[ButtonMapping]> {
        Binding(get: { self.buttonMappings(for: scope) }, set: { self.setButtonMappings($0, for: scope) })
    }

    func title(for scope: SettingsScope) -> String {
        switch scope {
        case .global: "All Devices & Apps"
        case .device(let id): devices.first { $0.id == id }?.name ?? "Disconnected Mouse"
        case .app(let id): appName(for: id)
        }
    }

    func modes(for scope: SettingsScope, axis: KeyPath<InputProfile, AxisSettings>) -> [AccelerationMode] {
        if case let .app(id) = scope, !devices.isEmpty {
            let modes = Set(devices.map { settings.profile(device: $0.id, app: id)[keyPath: axis].mode })
            return AccelerationMode.allCases.filter { modes.contains($0) }
        }
        return [profile(for: scope)[keyPath: axis].mode]
    }
}

struct ProfileControl<Value: Equatable, Control: View>: View {
    @ObservedObject var model: SettingsModel
    let scope: SettingsScope
    let field: WritableKeyPath<InputProfile, Value>
    let overrideField: WritableKeyPath<ProfileOverrides, Value?>
    let overrideTitle: String
    @ViewBuilder let control: (Binding<Value>) -> Control

    var body: some View {
        let value = Binding(
            get: { model.profile(for: scope)[keyPath: field] },
            set: { model.setProfileValue($0, at: field, overrideField: overrideField, for: scope) }
        )
        if case let .app(id) = scope {
            let override = Binding(
                get: { model.settings.appProfiles[id]?[keyPath: overrideField] != nil },
                set: { model.setAppOverride($0 ? inheritedValue : nil, at: overrideField, app: id) }
            )
            Toggle(overrideTitle, isOn: override)
            if override.wrappedValue { control(value) }
        } else {
            control(value)
        }
    }

    private var inheritedValue: Value {
        let values = model.devices.map { model.profile(for: .device($0.id))[keyPath: field] }
        if let first = values.first, values.dropFirst().allSatisfy({ $0 == first }) {
            return first
        }
        return model.settings.global[keyPath: field]
    }
}

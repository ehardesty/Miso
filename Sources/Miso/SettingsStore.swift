import Foundation
import MisoCore

enum SettingsStore {
    private static let key = "Miso.Settings"

    // Keep recovery records from earlier builds available for restoring Logitech controls.
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MouseTweaks", isDirectory: true)
    }

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return settings
    }

    static func save(_ settings: Settings) {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: key) }
    }
}

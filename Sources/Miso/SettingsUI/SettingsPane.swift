enum SettingsPane: String, CaseIterable, Identifiable {
    case status, pointer, scrolling, buttons

    var id: Self { self }

    var title: String {
        switch self {
        case .status: "Status"
        case .pointer: "Pointer"
        case .scrolling: "Scrolling"
        case .buttons: "Buttons & Gestures"
        }
    }

    var symbol: String {
        switch self {
        case .status: "power.circle"
        case .pointer: "cursorarrow.motionlines"
        case .scrolling: "scroll"
        case .buttons: "computermouse"
        }
    }

    var usesScope: Bool { self != .status }
}

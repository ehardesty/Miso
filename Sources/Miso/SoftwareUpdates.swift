import AppKit
import Combine
import Sparkle

@MainActor
final class SoftwareUpdates: ObservableObject {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )
    private var observations = Set<AnyCancellable>()

    init?(bundle: Bundle) {
        guard bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              bundle.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return nil }
    }

    func start() {
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheck = $0 }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticChecks = $0 }
            .store(in: &observations)
        controller.startUpdater()
    }

    func check() {
        guard canCheck else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}

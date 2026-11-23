import AppKit
import ApplicationServices
import Combine
import MisoCore
import UniformTypeIdentifiers

enum SettingsScope: Hashable {
    case global, device(String), app(String)
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard oldValue != settings else { return }
            SettingsStore.save(settings)
            apply()
        }
    }
    @Published private(set) var status: InputStatus = .stopped
    @Published private(set) var devices: [MouseDevice] = []
    @Published private(set) var inputMonitoringAllowed = false
    @Published private(set) var accessibilityAllowed = false
    @Published private(set) var isRecordingButton = false
    @Published private(set) var recordedButton: MouseButton?
    @Published private(set) var dpiError: String?
    @Published private(set) var pointerIssue: String?
    @Published private(set) var logitechIssue: String?

    private let input = InputService()
    private let pointer = PointerSettings()
    private let logitech = LogitechDevices(journal: ControlJournal(
        url: SettingsStore.supportDirectory.appendingPathComponent("control-recovery.json")
    ))
    private var nativeMice: [NativeMouse] = []
    private var app: String?
    private var observers: [NSObjectProtocol] = []
    private var unlockObserver: NSObjectProtocol?
    private var deviceRefresh: Task<Void, Never>?
    private var recheckRoutingOnRefresh = false
    private var sleeping = false
    private var terminating = false

    init() {
        settings = SettingsStore.load()
        app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        input.onStatus = { [weak self] status in
            guard let self, self.status != status else { return }
            self.status = status
            self.apply()
        }
        input.onButton = { [weak self] button in
            guard let self, self.isRecordingButton else { return }
            self.recordedButton = button
            self.isRecordingButton = false
            self.apply()
        }
        input.onRecordingCancelled = { [weak self] in self?.cancelButtonRecording() }
        logitech.onButton = { [weak self] event in self?.input.handleVendor(event) }
        logitech.onCancel = { [weak self] id in self?.input.cancelVendor(deviceID: id) }
        logitech.onInventory = { [weak self] in self?.refreshMice() }
        logitech.onTopology = { [weak self] in
            guard let self else { return }
            self.refreshMice()
            self.scheduleDeviceRefresh()
        }
        observeWorkspace()
        refreshPermissions()
    }

    func profile(for scope: SettingsScope) -> InputProfile {
        switch scope {
        case .global: settings.global
        case let .device(id): settings.profile(device: id, app: nil)
        case let .app(id): settings.profile(device: nil, app: id)
        }
    }

    func setProfileValue<Value: Equatable>(
        _ value: Value, at field: WritableKeyPath<InputProfile, Value>,
        overrideField: WritableKeyPath<ProfileOverrides, Value?>, for scope: SettingsScope
    ) {
        switch scope {
        case .global: settings.global[keyPath: field] = value
        case let .device(id):
            var overrides = settings.deviceProfiles[id] ?? ProfileOverrides()
            overrides[keyPath: overrideField] = value == settings.global[keyPath: field] ? nil : value
            saveDeviceOverrides(overrides, device: id)
        case let .app(id):
            setAppOverride(value, at: overrideField, app: id)
        }
    }

    func setAppOverride<Value>(_ value: Value?, at field: WritableKeyPath<ProfileOverrides, Value?>, app id: String) {
        settings.appProfiles[id, default: ProfileOverrides()][keyPath: field] = value
    }

    func buttonMappings(for scope: SettingsScope) -> [ButtonMapping] {
        if case let .app(id) = scope {
            return settings.appProfiles[id]?.appButtonMappings ?? []
        }
        return profile(for: scope).mappings
    }

    func setButtonMappings(_ mappings: [ButtonMapping], for scope: SettingsScope) {
        switch scope {
        case .global: settings.global.mappings = mappings
        case let .device(id):
            var overrides = settings.deviceProfiles[id] ?? ProfileOverrides()
            overrides.setDeviceButtonMappings(mappings, inheriting: settings.global.mappings)
            saveDeviceOverrides(overrides, device: id)
        case let .app(id):
            settings.appProfiles[id, default: ProfileOverrides()].appButtonMappings = mappings
        }
    }

    private func saveDeviceOverrides(_ overrides: ProfileOverrides, device id: String) {
        settings.deviceProfiles[id] = overrides == ProfileOverrides() ? nil : overrides
    }

    func resetProfile(_ scope: SettingsScope) {
        switch scope {
        case .global: settings.global = InputProfile()
        case let .device(id): settings.deviceProfiles[id] = nil
        case let .app(id): settings.appProfiles[id] = ProfileOverrides()
        }
    }

    func addAppProfile() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        if settings.appProfiles[id] == nil { settings.appProfiles[id] = ProfileOverrides() }
        return id
    }

    func appName(for id: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
    }

    func removeAppProfile(_ id: String) {
        settings.appProfiles[id] = nil
    }

    func setDPI(_ dpi: Int, for deviceID: String) {
        dpiError = nil
        logitech.setDPI(dpi, deviceID: deviceID) { [weak self] actual, success in
            guard !success else { return }
            self?.dpiError = actual.map { "The mouse reported \($0) DPI after the change." }
                ?? "The DPI change could not be verified. Reconnect the mouse and try again."
        }
    }

    func setWheelProbe(_ probe: WheelProbe) { input.setWheelProbe(probe) }

    func removeWheelProbe(_ probe: WheelProbe) { input.removeWheelProbe(probe) }

    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refreshPermissions()
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        refreshPermissions()
    }

    func refreshPermissions() {
        let ax = AXIsProcessTrusted()
        let inputAllowed = CGPreflightListenEventAccess()
        if accessibilityAllowed != ax { accessibilityAllowed = ax }
        if inputMonitoringAllowed != inputAllowed { inputMonitoringAllowed = inputAllowed }
        if inputAllowed {
            logitech.start()
            logitech.retryMissingMice()
        }
        pointer.recheck()
        refreshMice()
        if ax && inputAllowed { input.resumeIfPaused() }
    }

    func beginButtonRecording() {
        guard accessibilityAllowed, inputMonitoringAllowed else { return }
        recordedButton = nil
        isRecordingButton = true
        input.recordButton(true)
        apply()
    }

    func cancelButtonRecording() {
        guard isRecordingButton else { return }
        isRecordingButton = false
        input.recordButton(false)
        apply()
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let activated = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let next = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
                guard self.app != next.bundleIdentifier else { return }
                self.app = next.bundleIdentifier
                self.apply()
            }
        }
        let sleep = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = true
                self.cancelButtonRecording()
                self.logitech.suspend(true)
                self.apply()
            }
        }
        let wake = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = false
                self.logitech.suspend(false)
                self.scheduleDeviceRefresh()
            }
        }
        observers = [activated, sleep, wake]
        // Locking the screen can leave the system awake, so didWake alone misses it.
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.recheckRoutingOnRefresh = true
                self.scheduleDeviceRefresh()
            }
        }
    }

    private func scheduleDeviceRefresh() {
        guard !sleeping, !terminating else { return }
        deviceRefresh?.cancel()
        deviceRefresh = Task { [weak self] in
            // The HID event service may appear shortly after the device callback.
            for delay in [Duration.milliseconds(300), .seconds(1)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, !self.sleeping, !self.terminating else { return }
                self.refreshPermissions()
                guard self.recheckRoutingOnRefresh else { continue }
                self.recheckRoutingOnRefresh = false
                if self.inputMonitoringAllowed { self.logitech.recheckButtonRouting() }
            }
        }
    }

    private func refreshMice() {
        nativeMice = NativeMouse.connected()
        apply()
    }

    private func apply() {
        guard !terminating else { return }
        let vendorMice = logitech.mice
        var senderIDs: [UInt64: String] = [:]
        var seen = Set<String>()
        var list: [MouseDevice] = []
        let nativeMatches = nativeMice.map { vendorMatch($0, in: vendorMice) }
        let matchCounts = Dictionary(grouping: nativeMatches.compactMap { $0 }, by: \.descriptor.id)
        for (native, candidate) in zip(nativeMice, nativeMatches) {
            let match = candidate.flatMap { matchCounts[$0.descriptor.id]?.count == 1 ? $0 : nil }
            let descriptor = match?.descriptor ?? native.model
            senderIDs[native.sender] = descriptor.id
            if seen.insert(descriptor.id).inserted { list.append(descriptor) }
        }
        for mouse in vendorMice where seen.insert(mouse.descriptor.id).inserted { list.append(mouse.descriptor) }
        list.sort { ($0.name, $0.id) < ($1.name, $1.id) }
        if devices != list { devices = list }

        let blocked = vendorMice.filter(\.unavailableControls).map(\.descriptor.name)
        let captureIssue = blocked.isEmpty ? nil
            : "Miso could not verify button routing for \(blocked.joined(separator: ", ")). Quit other mouse utilities and reconnect the mouse."
        if logitechIssue != captureIssue { logitechIssue = captureIssue }

        let allowed = accessibilityAllowed && inputMonitoringAllowed && !sleeping
        let effectiveApp = app.flatMap { settings.appProfiles[$0] == nil ? nil : $0 }
        var effective = settings
        if sleeping { effective.enabled = false }
        input.configure(.init(
            settings: effective, mouseSenders: senderIDs,
            vendorIDs: Set(vendorMice.map(\.descriptor.id)), app: effectiveApp
        ), allowed: allowed)
        let unsupported = pointer.apply(to: nativeMice, deviceIDs: senderIDs, settings: effective, app: effectiveApp)
        let issue = unsupported.isEmpty ? nil : "macOS rejected pointer settings for \(unsupported.joined(separator: ", "))."
        if pointerIssue != issue { pointerIssue = issue }

        var policy: [String: Set<UInt16>] = [:]
        let systemAllowsRouting: Bool
        if case .unavailable = status { systemAllowsRouting = false } else { systemAllowsRouting = true }
        if allowed && systemAllowsRouting {
            for mouse in vendorMice {
                let id = mouse.descriptor.id
                let profile = effective.profile(device: id, app: effectiveApp)
                let buttons = isRecordingButton ? mouse.descriptor.buttons
                    : effective.enabled ? profile.mappings.filter { $0.isConfigured && $0.modifiers.isEmpty }.map(\.button) : []
                let cids = Set(buttons.compactMap { button -> UInt16? in
                    if case let .logitech(cid) = button { return cid }
                    return nil
                })
                if !cids.isEmpty { policy[id] = cids }
            }
        }
        logitech.configure(policy)
    }

    private func vendorMatch(_ native: NativeMouse, in mice: [LogitechMouse]) -> LogitechMouse? {
        guard native.vendor == 0x046D else { return nil }
        let compatible = mice.filter { mouse in
            if native.product == 0xC548 {
                return mouse.directProduct == nil && native.location != nil && mouse.location == native.location
            }
            return mouse.directProduct == native.product
        }
        if let serial = native.serial, !serial.isEmpty {
            let identified = compatible.filter { $0.serial == serial }
            if identified.count == 1 { return identified[0] }
        }
        if let location = native.location, location != 0 {
            let located = compatible.filter { $0.location == location }
            if located.count == 1 { return located[0] }
        }
        let nativeCount = nativeMice.count { $0.vendor == native.vendor && $0.product == native.product }
        return nativeCount == 1 && compatible.count == 1 ? compatible[0] : nil
    }

    func shutdown(_ completion: @escaping () -> Void) {
        terminating = true
        deviceRefresh?.cancel()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
        if let unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
        }
        let cleanup = DispatchGroup()
        cleanup.enter()
        input.shutdown { cleanup.leave() }
        cleanup.enter()
        logitech.shutdown { cleanup.leave() }
        pointer.restoreAll()
        cleanup.notify(queue: .main, execute: completion)
    }
}

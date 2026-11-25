import Foundation
import MisoCore
import os

struct LogitechMouse: Equatable, Sendable {
    var descriptor: MouseDevice
    let directProduct: Int?
    let location: Int?
    let serial: String?
    let slot: UInt8
    let buttonFeature: UInt8?
    let reconnectFeature: UInt8?
    var preferredDPI: Int?
    var needsDPIRestore = false
    var captured: Set<UInt16> = []
    var unavailableControls = false
}

struct LogitechInventory: Sendable {
    let mice: [LogitechMouse]
    let nonMouseSlots: Set<UInt8>
}

/// Keeps mutable HID++ state on the endpoint's command queue, outside the event tap.
final class LogitechSession: @unchecked Sendable {
    private static let logger = Logger(subsystem: "dev.mousetweaks.MouseTweaks", category: "DPI")

    private struct Route {
        var mouse: LogitechMouse
        let identityIndex: UInt8
        let dpi: LogitechDPI?
        let controls: Set<UInt16>
    }

    private let endpoint: any LogitechTransport
    private let journal: ControlJournal
    private let defaults: UserDefaults
    private var routes: [UInt8: Route] = [:]
    private var receiverNotificationWrite: [UInt8]?

    init(endpoint: any LogitechTransport, journal: ControlJournal, defaults: UserDefaults = .standard) {
        self.endpoint = endpoint
        self.journal = journal
        self.defaults = defaults
    }

    func discover(shouldRestoreDPI: () -> Bool) -> LogitechInventory {
        // Existing leases are recovered before replacing any session; receiver
        // slots can be reassigned without unplugging the receiver.
        for slot in routes.keys { clear(slot: slot) }

        enableReceiverNotifications()
        let slots = endpoint.isBolt ? Array(UInt8(1)...6) : [UInt8(0xFF)]
        var nonMouseSlots = Set<UInt8>()
        let discovered = slots.compactMap { probe(slot: $0, nonMouseSlots: &nonMouseSlots) }
        routes = Dictionary(uniqueKeysWithValues: discovered.map { ($0.mouse.slot, $0) })

        for slot in routes.keys {
            clear(slot: slot)
            guard let mouse = routes[slot]?.mouse, mouse.needsDPIRestore, let preferredDPI = mouse.preferredDPI,
                  shouldRestoreDPI() else { continue }
            let previous = mouse.descriptor.dpi.map { String($0.current) } ?? "unavailable"
            let observed = writeDPI(preferredDPI, slot: slot)
            if observed == preferredDPI { routes[slot]?.mouse.needsDPIRestore = false }
            let readback = observed.map(String.init) ?? "unverified"
            Self.logger.notice("DPI restore requested \(preferredDPI, privacy: .public), previously \(previous, privacy: .public), readback \(readback, privacy: .public)")
        }
        return LogitechInventory(mice: mice, nonMouseSlots: nonMouseSlots)
    }

    private func enableReceiverNotifications() {
        guard endpoint.isBolt, var flags = endpoint.receiverRegister(write: nil), flags.count == 3,
              flags[1] & 1 == 0 else { return }
        // Change only the wireless-event bit in the 24-bit receiver
        // notification register. Unknown bits and other tools' bits remain.
        flags[1] |= 1
        receiverNotificationWrite = flags
        _ = endpoint.receiverRegister(write: flags)
    }

    func shutdown() {
        _ = configure([:])
        guard let written = receiverNotificationWrite,
              var current = endpoint.receiverRegister(write: nil), current == written else { return }
        current[1] &= ~UInt8(1)
        _ = endpoint.receiverRegister(write: current)
    }

    private func probe(slot: UInt8, nonMouseSlots: inout Set<UInt8>) -> Route? {
        let features = LogitechFeatures(endpoint: endpoint, slot: slot)
        guard let identityIndex = features.feature(0x0003, timeout: endpoint.isBolt ? 0.2 : 0.6),
              let nameIndex = features.feature(0x0005),
              let kind = features.call(nameIndex, 2)?.first else { return nil }
        guard kind == 3 || kind == 5 else {
            nonMouseSlots.insert(slot)
            return nil
        }
        guard let identity = features.identity(index: identityIndex) else { return nil }
        let name = features.name(index: nameIndex) ?? endpoint.name
        let dpi = LogitechDPI.discover(on: features)
        let buttons = features.feature(0x1B04)
        let controls = Set(buttons.map(features.controls) ?? [])
        let reconnect = features.feature(0x1D4B)
        let deviceID = "logitech:" + identity
        let preferredDPI = defaults.object(forKey: Self.dpiPreferenceKey(deviceID)) as? Int
        let mouse = MouseDevice(
            id: deviceID, name: name, transport: endpoint.isBolt ? "Logi Bolt" : endpoint.transport,
            dpi: dpi?.capability, buttons: (0..<5).map { .standard(UInt8($0)) } + controls.sorted().map(MouseButton.logitech)
        )
        return Route(
            mouse: LogitechMouse(
                descriptor: mouse,
                directProduct: endpoint.isBolt ? nil : endpoint.product,
                location: endpoint.location, serial: endpoint.serial, slot: slot,
                buttonFeature: buttons, reconnectFeature: reconnect,
                preferredDPI: preferredDPI,
                needsDPIRestore: preferredDPI.map { dpi?.needsRestore(to: $0) ?? true } ?? false
            ),
            identityIndex: identityIndex, dpi: dpi, controls: controls
        )
    }

    var mice: [LogitechMouse] { routes.values.map(\.mouse).sorted { $0.slot < $1.slot } }

    func writeDPI(_ requested: Int, deviceID: String) -> (actual: Int?, success: Bool) {
        guard let slot = routes.first(where: { $0.value.mouse.descriptor.id == deviceID })?.key else {
            return (nil, false)
        }
        let observed = writeDPI(requested, slot: slot)
        let success = observed == requested
        if success {
            defaults.set(requested, forKey: Self.dpiPreferenceKey(deviceID))
            routes[slot]?.mouse.preferredDPI = requested
            routes[slot]?.mouse.needsDPIRestore = false
        }
        return (observed, success)
    }

    private func writeDPI(_ requested: Int, slot: UInt8) -> Int? {
        guard var route = routes[slot], let dpi = route.dpi, dpi.capability.supports(requested) else { return nil }
        let features = LogitechFeatures(endpoint: endpoint, slot: slot)
        guard matches(route, features: features) else { return nil }
        guard let observed = dpi.write(requested, on: features) else { return nil }
        route.mouse.descriptor.dpi?.current = observed
        routes[slot] = route
        return observed
    }

    private static func dpiPreferenceKey(_ deviceID: String) -> String {
        "Miso.DPI.\(deviceID)"
    }

    func configure(_ policy: [String: Set<UInt16>]) -> [LogitechMouse] {
        for slot in routes.keys {
            guard var route = routes[slot], let index = route.mouse.buttonFeature else { continue }
            let id = route.mouse.descriptor.id
            let desired = (policy[id] ?? []).intersection(route.controls)
            let claims = journal.claims(for: id)
            let remove = Set(claims.keys).subtracting(desired)
            let add = desired.subtracting(route.mouse.captured)
            guard !remove.isEmpty || !add.isEmpty else {
                route.mouse.unavailableControls = false
                routes[slot] = route
                continue
            }

            let features = LogitechFeatures(endpoint: endpoint, slot: slot)
            guard matches(route, features: features) else {
                route.mouse.captured = []
                route.mouse.unavailableControls = true
                routes[slot] = route
                continue
            }

            var failed = false
            for cid in remove {
                failed = !release(cid, deviceID: id, features: features, index: index) || failed
                route.mouse.captured.remove(cid)
            }
            for cid in add {
                if claims[cid] != nil, !release(cid, deviceID: id, features: features, index: index) {
                    failed = true
                    continue
                }
                guard let baseline = features.reporting(cid, index: index), !baseline.hasConflictingMode,
                      baseline.target == cid, journal.update(baseline, deviceID: id, cid: cid) else {
                    failed = true
                    continue
                }
                if let written = features.setDiverted(true, cid: cid, index: index),
                   written.flags == baseline.flags | 1, written.target == baseline.target {
                    route.mouse.captured.insert(cid)
                } else {
                    failed = true
                    _ = release(cid, deviceID: id, features: features, index: index)
                }
            }
            route.mouse.unavailableControls = failed
            routes[slot] = route
        }
        return mice
    }

    private func clear(slot: UInt8) {
        guard var route = routes[slot], let index = route.mouse.buttonFeature else { return }
        let id = route.mouse.descriptor.id
        let claims = journal.claims(for: id)
        guard !claims.isEmpty else { return }
        let features = LogitechFeatures(endpoint: endpoint, slot: slot)
        guard matches(route, features: features) else { return }
        var unresolved = false
        for cid in claims.keys {
            unresolved = !release(cid, deviceID: id, features: features, index: index) || unresolved
        }
        route.mouse.captured = []
        route.mouse.unavailableControls = unresolved
        routes[slot] = route
    }

    private func release(_ cid: UInt16, deviceID: String, features: LogitechFeatures, index: UInt8) -> Bool {
        guard let baseline = journal.claims(for: deviceID)[cid] else { return true }
        guard let current = features.reporting(cid, index: index) else { return false }
        if current.isDiverted {
            guard current.flags == baseline.flags | 1, current.target == baseline.target,
                  features.setDiverted(false, cid: cid, index: index) == baseline else { return false }
        }
        return journal.update(nil, deviceID: deviceID, cid: cid)
    }

    private func matches(_ route: Route, features: LogitechFeatures) -> Bool {
        // Root lookup on each write avoids relying on a cached feature index
        // after a receiver slot changes or a device wakes.
        guard let index = features.feature(0x0003) else { return false }
        return features.identity(index: index) == route.mouse.descriptor.id.replacingOccurrences(of: "logitech:", with: "")
            && index == route.identityIndex
    }
}

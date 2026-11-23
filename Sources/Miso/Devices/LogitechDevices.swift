import Foundation
import IOKit
import IOKit.hid
import MisoCore

@MainActor
final class LogitechDevices {
    private struct Connection: Sendable {
        let endpoint: HIDEndpoint
        let session: LogitechSession
        var mice: [LogitechMouse] = []
        var scanning = false
        var needsScan = false
        var applying = false
        var policyChanged = false
        var unknownSlotProbe: [UInt8: UInt64] = [:]
        var nonMouseSlots: Set<UInt8> = []
        var knownMouseSlots: Set<UInt8> = []
    }

    var onInventory: (() -> Void)?
    var onTopology: (() -> Void)?
    var onButton: ((VendorButtonEvent) -> Void)?
    var onCancel: ((String) -> Void)?

    private let journal: ControlJournal
    private var manager: IOHIDManager?
    private var connections: [UInt64: Connection] = [:]
    private var held: [String: Set<UInt16>] = [:]
    private var desired: [String: Set<UInt16>] = [:]
    private var suspended = false
    private var closing = false

    init(journal: ControlJournal) { self.journal = journal }

    var mice: [LogitechMouse] { connections.values.flatMap(\.mice) }

    func start() {
        guard manager == nil, !closing else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            ["VendorID": 0x046D, "PrimaryUsagePage": 0xFF00],
            ["VendorID": 0x046D, "PrimaryUsagePage": 0xFF43],
            ["DeviceUsagePage": 1, "DeviceUsage": 2]
        ] as CFArray)
        let owner = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context, result == kIOReturnSuccess else { return }
            MainActor.assumeIsolated {
                Unmanaged<LogitechDevices>.fromOpaque(context).takeUnretainedValue().added(device)
            }
        }, owner)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<LogitechDevices>.fromOpaque(context).takeUnretainedValue().removed(device)
            }
        }, owner)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = manager
    }

    private func added(_ device: IOHIDDevice) {
        guard !closing else { return }
        onTopology?()
        guard let endpoint = HIDEndpoint(device) else { return }
        let id = endpoint.registryID
        guard connections[id] == nil else {
            endpoint.invalidate()
            return
        }
        endpoint.onNotification = { [weak self] frame in
            MainActor.assumeIsolated { self?.receive(frame, on: id) }
        }
        connections[id] = Connection(endpoint: endpoint, session: LogitechSession(endpoint: endpoint, journal: journal))
        scan(id)
    }

    private func removed(_ device: IOHIDDevice) {
        if let entry = connections.first(where: { CFEqual($0.value.endpoint.device, device) }),
           let connection = connections.removeValue(forKey: entry.key) {
            cancel(connection.mice)
            connection.endpoint.invalidate()
            onInventory?()
        }
        onTopology?()
    }

    func rescan() {
        for id in Array(connections.keys) { scan(id) }
    }

    func retryMissingMice() {
        let ids = connections.compactMap { id, connection -> UInt64? in
            guard connection.endpoint.isBolt, !connection.scanning else { return nil }
            let present = Set(connection.mice.map(\.slot))
            return present.isEmpty || !connection.knownMouseSlots.isSubset(of: present) ? id : nil
        }
        for id in ids { scan(id) }
    }

    func suspend(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        if value {
            cancel(mice)
            for id in Array(connections.keys) { applyPolicy(id) }
        } else {
            rescan()
        }
    }

    private func scan(_ id: UInt64) {
        guard !suspended, !closing, let connection = connections[id] else { return }
        if connection.scanning {
            connections[id]?.needsScan = true
            return
        }
        cancel(connection.mice)
        connections[id]?.scanning = true
        connection.endpoint.queue.async { [weak self] in
            let inventory = connection.session.discover()
            DispatchQueue.main.async {
                guard let self, self.connections[id]?.endpoint === connection.endpoint else { return }
                let foundSlots = Set(inventory.mice.map(\.slot))
                self.connections[id]?.nonMouseSlots.formUnion(inventory.nonMouseSlots)
                self.connections[id]?.nonMouseSlots.subtract(foundSlots)
                self.connections[id]?.knownMouseSlots.formUnion(foundSlots)
                self.connections[id]?.knownMouseSlots.subtract(inventory.nonMouseSlots)
                self.connections[id]?.scanning = false
                self.publish(inventory.mice, for: id)
                if self.connections[id]?.needsScan == true {
                    self.connections[id]?.needsScan = false
                    self.scan(id)
                } else {
                    self.applyPolicy(id)
                }
            }
        }
    }

    func configure(_ desired: [String: Set<UInt16>]) {
        guard self.desired != desired else { return }
        self.desired = desired
        for id in Array(connections.keys) { applyPolicy(id) }
    }

    private func applyPolicy(_ id: UInt64) {
        guard !closing, let connection = connections[id], !connection.scanning else { return }
        if connection.applying {
            connections[id]?.policyChanged = true
            return
        }
        connections[id]?.applying = true
        let policy = suspended ? [:] : desired
        connection.endpoint.queue.async { [weak self] in
            let devices = connection.session.configure(policy)
            DispatchQueue.main.async {
                guard let self, !self.closing, self.connections[id]?.endpoint === connection.endpoint else { return }
                self.connections[id]?.applying = false
                self.publish(devices, for: id)
                if self.connections[id]?.policyChanged == true {
                    self.connections[id]?.policyChanged = false
                    self.applyPolicy(id)
                }
            }
        }
    }

    func setDPI(_ requested: Int, deviceID: String, completion: @escaping (Int?, Bool) -> Void) {
        guard !closing, !suspended,
              let connection = connections.values.first(where: { entry in
                  entry.mice.contains { $0.descriptor.id == deviceID }
              }), !connection.scanning else {
            completion(nil, false)
            return
        }
        let id = connection.endpoint.registryID
        connection.endpoint.queue.async { [weak self] in
            let result = connection.session.writeDPI(requested, deviceID: deviceID)
            let devices = connection.session.mice
            DispatchQueue.main.async {
                guard let self, self.connections[id]?.endpoint === connection.endpoint else {
                    completion(nil, false)
                    return
                }
                self.publish(devices, for: id)
                completion(result.actual, result.success)
            }
        }
    }

    private func publish(_ devices: [LogitechMouse], for id: UInt64) {
        guard let previous = connections[id]?.mice, devices != previous else { return }
        for old in previous {
            if let new = devices.first(where: { $0.descriptor.id == old.descriptor.id }), new.captured == old.captured {
                continue
            }
            cancel([old])
        }
        connections[id]?.mice = devices
        onInventory?()
    }

    private func receive(_ frame: HIDPPFrame, on id: UInt64) {
        guard !suspended, !closing, let connection = connections[id] else { return }
        let isBoltSlot = connection.endpoint.isBolt && (1...6).contains(frame.device)
        if isBoltSlot, frame.feature == 0x41, frame.address == 0x10 {
            // Bolt connection notifications encode device kind in the next byte.
            // Known non-pointer kinds can share the receiver without restarting mouse capture.
            let kind = frame.payload.first.map { $0 & 0x0F }
            let nonPointerKind = kind.map { [1, 3, 4, 7, 9, 10, 11, 12, 13].contains($0) } ?? false
            if nonPointerKind && !connection.mice.contains(where: { $0.slot == frame.device }) {
                connections[id]?.nonMouseSlots.insert(frame.device)
                connections[id]?.knownMouseSlots.remove(frame.device)
                return
            }
            connections[id]?.nonMouseSlots.remove(frame.device)
            connections[id]?.unknownSlotProbe[frame.device] = nil
            scan(id)
            return
        }
        guard let mouse = connection.mice.first(where: {
            $0.slot == frame.device || (!connection.endpoint.isBolt && frame.device == 0)
        }) else {
            guard isBoltSlot, !connection.nonMouseSlots.contains(frame.device),
                  frame.address & 0x0F == 0, frame.feature < 0x80 else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            if let previous = connection.unknownSlotProbe[frame.device], now - previous < 2_000_000_000 { return }
            connections[id]?.unknownSlotProbe[frame.device] = now
            scan(id)
            return
        }
        guard !connection.scanning else { return }
        if frame.feature == mouse.reconnectFeature {
            scan(id)
            return
        }
        guard frame.feature == mouse.buttonFeature, frame.address == 0, !mouse.captured.isEmpty else { return }

        let device = mouse.descriptor.id
        var next = Set<UInt16>()
        // A diverted-buttons notification lists every currently held CID.
        for offset in stride(from: 0, to: min(frame.payload.count, 8), by: 2) {
            if let cid = HIDPPFrame.word(frame.payload, at: offset), mouse.captured.contains(cid) {
                next.insert(cid)
            }
        }
        let previous = held[device] ?? []
        guard next != previous else { return }
        held[device] = next.isEmpty ? nil : next
        for cid in previous.subtracting(next) { onButton?(.init(deviceID: device, button: .logitech(cid), pressed: false)) }
        for cid in next.subtracting(previous) { onButton?(.init(deviceID: device, button: .logitech(cid), pressed: true)) }
    }

    private func cancel(_ devices: [LogitechMouse]) {
        for mouse in devices {
            let id = mouse.descriptor.id
            held[id] = nil
            onCancel?(id)
        }
    }

    func shutdown(_ completion: @escaping () -> Void) {
        guard !closing else { completion(); return }
        closing = true
        cancel(mice)
        let pending = DispatchGroup()
        for connection in connections.values {
            pending.enter()
            connection.endpoint.queue.async {
                connection.session.shutdown()
                pending.leave()
            }
        }
        pending.notify(queue: .main) { [self] in
            for connection in connections.values { connection.endpoint.invalidate() }
            connections.removeAll()
            if let manager {
                IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
                self.manager = nil
            }
            completion()
        }
    }
}

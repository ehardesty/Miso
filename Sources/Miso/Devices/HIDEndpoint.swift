import Foundation
import IOKit
import IOKit.hid
import MisoCore

protocol LogitechTransport: AnyObject {
    var product: Int { get }
    var location: Int? { get }
    var name: String { get }
    var serial: String? { get }
    var transport: String { get }
    var isBolt: Bool { get }

    func command(slot: UInt8, feature: UInt8, function: UInt8, payload: [UInt8], timeout: TimeInterval) -> [UInt8]?
    func receiverRegister(write: [UInt8]?) -> [UInt8]?
}

/// One serial command lane for a Logitech vendor HID collection. The IOKit
/// callback never waits for the command lane, and unrelated reports are ignored.
// Transport state is protected by lock or confined to queue. IOKit callback
// registration and the notification handler are confined to the main run loop.
final class HIDEndpoint: LogitechTransport, @unchecked Sendable {
    private final class Pending {
        let request: HIDPPFrame
        let direct: Bool
        let done = DispatchSemaphore(value: 0)
        var result: HIDPPFrame.Response?

        init(_ request: HIDPPFrame, direct: Bool) {
            self.request = request
            self.direct = direct
        }
    }

    let registryID: UInt64
    let device: IOHIDDevice
    let product: Int
    let location: Int?
    let name: String
    let serial: String?
    let transport: String
    let isBolt: Bool
    let hasMouseUsage: Bool
    let queue: DispatchQueue

    private let reportID: UInt8
    private let supportsShortReport: Bool
    private let reportBuffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int
    private let lock = NSLock()
    private var pending: Pending?
    private var valid = true
    private var softwareID: UInt8 = 0x09
    private var nextUse = [UInt64](repeating: 0, count: 16)

    // Invoked on the HID run loop for hardware notifications only.
    var onNotification: ((HIDPPFrame) -> Void)?

    init?(_ device: IOHIDDevice) {
        func property<T>(_ key: String) -> T? {
            IOHIDDeviceGetProperty(device, key as CFString) as? T
        }
        guard property("VendorID") as Int? == 0x046D,
              let product: Int = property("ProductID"),
              let page: Int = property(kIOHIDPrimaryUsagePageKey),
              let maxInput: Int = property("MaxInputReportSize"),
              let maxOutput: Int = property("MaxOutputReportSize"),
              (7...1024).contains(maxInput), maxOutput >= 7 else { return nil }
        let usagePairs: [[String: Int]] = property(kIOHIDDeviceUsagePairsKey) ?? []
        // Bluetooth mice can expose HID++ as a secondary collection on the pointer device.
        let hasVendorCollection = page == 0xFF00 || page == 0xFF43 || usagePairs.contains {
            $0[kIOHIDDeviceUsagePageKey] == 0xFF43 && $0[kIOHIDDeviceUsageKey] == 0x0202
        }
        guard hasVendorCollection else { return nil }
        let service = IOHIDDeviceGetService(device)
        var registryID: UInt64 = 0
        guard service != 0, IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else { return nil }

        let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(0)) as? [IOHIDElement] ?? []
        let outputIDs = Set(elements.lazy.filter { IOHIDElementGetType($0) == kIOHIDElementTypeOutput }
            .map(IOHIDElementGetReportID))
        if outputIDs.contains(0x11) && maxOutput >= 20 {
            reportID = 0x11
        } else if outputIDs.contains(0x10) {
            reportID = 0x10
        } else if outputIDs.isEmpty {
            reportID = maxOutput >= 20 ? 0x11 : 0x10
        } else {
            return nil
        }

        supportsShortReport = outputIDs.contains(0x10) || (outputIDs.isEmpty && (page == 0xFF00 || reportID == 0x10))

        guard IOHIDDeviceOpen(device, IOOptionBits(0)) == kIOReturnSuccess else { return nil }
        self.registryID = registryID
        self.device = device
        self.product = product
        location = property("LocationID")
        name = property("Product") ?? "Logitech Mouse"
        serial = property("SerialNumber")
        transport = property("Transport") ?? "USB"
        isBolt = product == 0xC548
        hasMouseUsage = IOHIDDeviceConformsTo(device, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse))
        self.queue = DispatchQueue(label: "Miso HID++ \(registryID)", qos: .utility)
        bufferSize = maxInput
        reportBuffer = .allocate(capacity: maxInput)
        registerCallback()
    }

    private func registerCallback() {
        IOHIDDeviceRegisterInputReportCallback(
            device, reportBuffer, bufferSize, { ctx, result, _, _, reportID, report, length in
                guard result == kIOReturnSuccess, let ctx, reportID == 0x10 || reportID == 0x11 else { return }
                let endpoint = Unmanaged<HIDEndpoint>.fromOpaque(ctx).takeUnretainedValue()
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                let expected = reportID == 0x10 ? 7 : 20
                let framed = bytes.count == expected - 1 ? [UInt8(reportID)] + bytes : bytes
                if let frame = HIDPPFrame(report: framed) { endpoint.receive(frame) }
            }, Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func invalidate() {
        lock.withLock {
            valid = false
            pending?.done.signal()
        }
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, bufferSize, nil, nil)
        queue.async { [self] in IOHIDDeviceClose(device, IOOptionBits(0)) }
    }

    deinit { reportBuffer.deallocate() }

    func command(
        slot: UInt8, feature: UInt8, function: UInt8, payload: [UInt8], timeout: TimeInterval
    ) -> [UInt8]? {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let softwareID = nextSoftwareID() else { return nil }
        let request = HIDPPFrame(device: slot, feature: feature, address: (function << 4) | softwareID, payload: payload)
        return exchange(request, reportID: reportID, direct: slot == 0xFF, timeout: timeout) {
            nextUse[Int(softwareID)] = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        }
    }

    /// Bolt receiver notifications use HID++ 1.0 instead of the paired
    /// device's HID++ 2.0 feature table. The register byte has no software ID.
    func receiverRegister(write: [UInt8]?) -> [UInt8]? {
        dispatchPrecondition(condition: .onQueue(queue))
        guard isBolt, supportsShortReport else { return nil }
        let data = write ?? [0, 0, 0]
        guard data.count == 3 else { return nil }
        let request = HIDPPFrame(device: 0xFF, feature: write == nil ? 0x81 : 0x80, address: 0, payload: data)
        return exchange(request, reportID: 0x10, direct: false, timeout: 0.45)
    }

    private func exchange(
        _ request: HIDPPFrame, reportID: UInt8, direct: Bool, timeout: TimeInterval, onTimeout: () -> Void = {}
    ) -> [UInt8]? {
        guard let bytes = request.report(id: reportID) else { return nil }
        let transaction = Pending(request, direct: direct)
        let admitted = lock.withLock {
            guard valid else { return false }
            pending = transaction
            return true
        }
        guard admitted else { return nil }
        defer { lock.withLock { pending = nil } }

        let result = bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else { return nil }
        guard transaction.done.wait(timeout: .now() + timeout) == .success else {
            onTimeout()
            return nil
        }
        return lock.withLock {
            guard valid, case let .success(payload)? = transaction.result else { return nil }
            return payload
        }
    }

    private func nextSoftwareID() -> UInt8? {
        let now = DispatchTime.now().uptimeNanoseconds
        for _ in 1...15 {
            softwareID = (softwareID % 15) + 1
            if nextUse[Int(softwareID)] <= now { return softwareID }
        }
        return nil
    }

    private func receive(_ frame: HIDPPFrame) {
        let matched = lock.withLock {
            guard valid else { return true }
            guard let pending, pending.result == nil,
                  let response = frame.response(to: pending.request, direct: pending.direct) else { return false }
            pending.result = response
            pending.done.signal()
            return true
        }
        if !matched, frame.address & 0x0F == 0 || frame.feature == 0x41 { onNotification?(frame) }
    }
}

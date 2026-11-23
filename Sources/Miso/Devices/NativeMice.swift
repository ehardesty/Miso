import Foundation
import MisoCore
import MisoPlatform

struct NativeMouse {
    let service: AnyObject
    let sender: UInt64
    let vendor: Int
    let product: Int
    let location: Int?
    let serial: String?
    let model: MouseDevice

    init?(service: AnyObject) {
        func property<T>(_ key: String) -> T? {
            MTCopyServiceProperty(service, key as CFString) as? T
        }

        let sender = MTServiceRegistryID(service)
        guard sender != 0,
              let name: String = property("Product"),
              !name.localizedCaseInsensitiveContains("trackpad"),
              property("Built-In") as Bool? != true else { return nil }

        let vendor: Int = property("VendorID") ?? 0
        let product: Int = property("ProductID") ?? 0
        let serial: String? = property("SerialNumber")
        let location: Int? = property("LocationID")
        let transport: String = property("Transport") ?? "Mouse"
        let reportedCount: Int = property("ButtonCount") ?? 3
        let count = max(3, min(32, reportedCount))
        self.service = service
        self.sender = sender
        self.vendor = vendor
        self.product = product
        self.location = location
        self.serial = serial
        model = MouseDevice(
            id: Self.identifier(vendor: vendor, product: product, serial: serial, location: location),
            name: name, transport: transport,
            buttons: (0..<count).map { .standard(UInt8($0)) }
        )
    }

    static func identifier(vendor: Int, product: Int, serial: String?, location: Int?) -> String {
        let identity = serial.flatMap { $0.isEmpty ? nil : $0 } ?? location.flatMap { $0 == 0 ? nil : String($0) } ?? ""
        return "\(vendor):\(product):\(identity)"
    }

    static func connected() -> [NativeMouse] {
        (MTCopyMouseServices() as? [AnyObject] ?? []).compactMap(NativeMouse.init)
    }
}

/// Native IOHID service settings keep pointer shaping out of the event tap.
/// This object is used on the main actor in response to configuration and device changes.
final class PointerSettings {
    private static let resolution = "HIDPointerResolution"
    private static let linear = "HIDUseLinearScalingMouseAcceleration"

    private struct Ownership {
        let service: AnyObject
        let accelerationKey: String
        let resolution: Int?
        let acceleration: Int?
        let linear: Int?
        var applied: AxisSettings?
        var writes: [String: Int] = [:]

        init(_ mouse: NativeMouse) {
            service = mouse.service
            accelerationKey = MTCopyServiceProperty(service, "HIDPointerAccelerationType" as CFString) as? String
                ?? "HIDMouseAcceleration"
            resolution = Self.read(service, PointerSettings.resolution)
            acceleration = Self.read(service, accelerationKey)
            linear = Self.read(service, PointerSettings.linear)
        }

        static func read(_ service: AnyObject, _ key: String) -> Int? {
            MTCopyServiceProperty(service, key as CFString) as? Int
        }

        mutating func write(_ value: Int, _ key: String, previous: Int?) -> Bool {
            guard previous != value || writes[key] != nil else { return true }
            guard MTSetServiceProperty(service, key as CFString, NSNumber(value: value)) else { return false }
            writes[key] = value
            return true
        }

        mutating func apply(_ settings: AxisSettings) -> Bool {
            let speed = settings.speedMultiplier
            let accelerationAmount = settings.accelerationAmount
            var succeeded = true
            if speed != 1 || writes[PointerSettings.resolution] != nil {
                if let resolution {
                    let value = speed == 1 ? resolution : Int(
                        min(1995 * 65_536, max(10 * 65_536, Double(resolution) / speed))
                    )
                    succeeded = write(value, PointerSettings.resolution, previous: resolution) && succeeded
                } else {
                    succeeded = false
                }
            }

            if let linear, accelerationAmount != 0 || writes[PointerSettings.linear] != nil {
                let value = accelerationAmount < 0 ? 1 : accelerationAmount > 0 ? 0 : linear
                succeeded = write(value, PointerSettings.linear, previous: linear) && succeeded
            }

            if let acceleration {
                let baseline = acceleration >= 0 ? acceleration : 45_056
                let adjusted = Int(Double(baseline) * (1 + max(0, accelerationAmount)) * (1 + min(0, accelerationAmount)))
                let value: Int
                if accelerationAmount <= -1 && linear == nil {
                    value = -65_536
                } else if accelerationAmount == 0 || accelerationAmount <= -1 {
                    value = acceleration
                } else {
                    value = adjusted
                }
                // Reapplying the current acceleration makes a resolution change take effect.
                if speed != 1 || writes[PointerSettings.resolution] != nil {
                    let accepted = MTSetServiceProperty(service, accelerationKey as CFString, NSNumber(value: value))
                    succeeded = accepted && succeeded
                    if accepted, value != acceleration { writes[accelerationKey] = value }
                } else {
                    succeeded = write(value, accelerationKey, previous: acceleration) && succeeded
                }
            } else if accelerationAmount != 0 && !(accelerationAmount <= -1 && linear != nil) {
                succeeded = false
            }
            applied = succeeded ? settings : nil
            return succeeded
        }

        mutating func restore() -> Bool {
            var succeeded = true
            let currentAcceleration = Self.read(service, accelerationKey)
            let ownsAcceleration = writes[accelerationKey] != nil && writes[accelerationKey] == currentAcceleration
            var didRestoreResolution = false
            for (key, baseline) in [(PointerSettings.linear, linear), (PointerSettings.resolution, resolution)] {
                guard let baseline, let last = writes[key] else { continue }
                guard Self.read(service, key) == last else { writes[key] = nil; continue }
                if MTSetServiceProperty(service, key as CFString, NSNumber(value: baseline)) {
                    writes[key] = nil
                    didRestoreResolution = didRestoreResolution || key == PointerSettings.resolution
                } else {
                    succeeded = false
                }
            }
            if (ownsAcceleration || didRestoreResolution),
               let desired = ownsAcceleration ? acceleration : currentAcceleration {
                if MTSetServiceProperty(service, accelerationKey as CFString, NSNumber(value: desired)) {
                    writes[accelerationKey] = nil
                } else {
                    succeeded = false
                }
            } else if !ownsAcceleration {
                writes[accelerationKey] = nil
            }
            applied = nil
            return succeeded
        }
    }

    private var owners: [UInt64: Ownership] = [:]

    func apply(to devices: [NativeMouse], deviceIDs: [UInt64: String], settings: Settings, app: String?) -> [String] {
        let connected = Set(devices.map(\.sender))
        owners = owners.filter { connected.contains($0.key) }
        var unavailable: [String] = []
        for device in devices {
            let value = settings.enabled
                ? settings.profile(device: deviceIDs[device.sender] ?? device.model.id, app: app).pointer
                : AxisSettings()
            if value == AxisSettings() {
                if var owner = owners[device.sender] {
                    if owner.restore() {
                        owners[device.sender] = nil
                    } else {
                        owners[device.sender] = owner
                        unavailable.append(device.model.name)
                    }
                }
            } else {
                var owner = owners[device.sender] ?? Ownership(device)
                if owner.applied != value, !owner.apply(value) { unavailable.append(device.model.name) }
                owners[device.sender] = owner
            }
        }
        return unavailable
    }

    func recheck() {
        for id in Array(owners.keys) { owners[id]?.applied = nil }
    }

    func restoreAll() {
        for id in Array(owners.keys) {
            if owners[id]?.restore() == true { owners[id] = nil }
        }
    }
}

import MisoCore

struct LogitechDPI {
    private enum Feature {
        case adjustable(index: UInt8)
        case extended(index: UInt8, hasY: Bool, hasLiftOff: Bool)
    }

    private let feature: Feature
    let capability: MouseDPI

    static func discover(on device: LogitechFeatures) -> Self? {
        if let index = device.feature(0x2201),
           (device.call(index, 0)?.first ?? 0) > 0,
           let data = device.call(index, 1, [0]), let values = DPICapability.parseList(data),
           let current = currentDPI(device.call(index, 2, [0])),
           let capability = capability(values, current: current) {
            return Self(feature: .adjustable(index: index), capability: capability)
        }
        guard let index = device.feature(0x2202),
              (device.call(index, 0)?.first ?? 0) > 0,
              let sensor = device.call(index, 1, [0]), sensor.count >= 3, sensor[0] == 0,
              let parameters = extendedParameters(on: device, index: index),
              let current = currentDPI(parameters),
              let x = extendedValues(on: device, index: index, axis: 0) else { return nil }

        let hasY = sensor[2] & 1 != 0
        let values: [Int]
        if hasY {
            guard let y = extendedValues(on: device, index: index, axis: 1) else { return nil }
            values = Set(x).intersection(y).sorted()
        } else {
            values = x
        }
        guard let capability = capability(values, current: current) else { return nil }
        return Self(
            feature: .extended(index: index, hasY: hasY, hasLiftOff: sensor[2] & 2 != 0),
            capability: capability
        )
    }

    func write(_ requested: Int, on device: LogitechFeatures) -> Int? {
        guard capability.supports(requested), let value = UInt16(exactly: requested) else { return nil }

        switch feature {
        case let .adjustable(index):
            guard device.feature(0x2201) == index else { return nil }
            _ = device.call(index, 3, [0] + HIDPPFrame.bytes(value))
            let observed = Self.currentDPI(device.call(index, 2, [0]))
            if observed == requested { return observed }
            return Self.currentDPI(device.call(index, 2, [0])) ?? observed

        case let .extended(index, hasY, hasLiftOff):
            guard device.feature(0x2202) == index,
                  let current = Self.extendedParameters(on: device, index: index) else { return nil }
            let liftOff = hasLiftOff ? current[9] : 0
            guard liftOff <= 3 else { return nil }
            let y: UInt16 = hasY ? value : 0
            _ = device.call(index, 6, [0] + HIDPPFrame.bytes(value) + HIDPPFrame.bytes(y) + [liftOff])
            guard let actual = Self.extendedParameters(on: device, index: index),
                  !hasY || HIDPPFrame.word(actual, at: 5) == value,
                  !hasLiftOff || actual[9] == liftOff else { return nil }
            return Self.currentDPI(actual)
        }
    }

    private static func capability(_ values: [Int], current: Int) -> MouseDPI? {
        guard let minimum = values.first, let maximum = values.last else { return nil }
        let step = values.count > 1 ? values[1] - minimum : 1
        let regular = zip(values, values.dropFirst()).allSatisfy { $1 - $0 == step }
        return MouseDPI(
            current: current, minimum: minimum, maximum: maximum,
            step: step, values: regular && values.count > 1 ? [] : values
        )
    }

    private static func currentDPI(_ data: [UInt8]?) -> Int? {
        guard let data, let value = HIDPPFrame.word(data, at: 1) else { return nil }
        let effective = value == 0 ? HIDPPFrame.word(data, at: 3) ?? 0 : value
        return effective > 0 ? Int(effective) : nil
    }

    private static func extendedParameters(on device: LogitechFeatures, index: UInt8) -> [UInt8]? {
        guard let payload = device.call(index, 5, [0]), payload.count >= 10, payload[0] == 0 else { return nil }
        return payload
    }

    private static func extendedValues(on device: LogitechFeatures, index: UInt8, axis: UInt8) -> [Int]? {
        var bytes: [UInt8] = []
        for page: UInt8 in 0..<8 {
            guard let payload = device.call(index, 2, [0, axis, page]), payload.count == 16,
                  payload[0] == 0, payload[1] == axis, payload[2] == page else { return nil }
            bytes.append(contentsOf: payload.dropFirst(3))
            if let values = DPICapability.parseRanges(bytes) { return values }
        }
        return nil
    }
}

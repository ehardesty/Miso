import Foundation

/// HID++ 2.0 short and long packets. The low nibble of the address is a
/// software ID. Zero is reserved for unsolicited device notifications.
public struct HIDPPFrame: Equatable, Sendable {
    public var device: UInt8
    public var feature: UInt8
    public var address: UInt8
    public var payload: [UInt8]

    public init(device: UInt8, feature: UInt8, address: UInt8, payload: [UInt8]) {
        self.device = device
        self.feature = feature
        self.address = address
        self.payload = payload
    }

    public init?(report: [UInt8]) {
        guard let id = report.first, report.count == (id == 0x10 ? 7 : id == 0x11 ? 20 : 0) else { return nil }
        self.init(device: report[1], feature: report[2], address: report[3], payload: Array(report.dropFirst(4)))
    }

    public func report(id: UInt8) -> [UInt8]? {
        let count = id == 0x10 ? 7 : id == 0x11 ? 20 : 0
        guard count >= payload.count + 4 else { return nil }
        return [id, device, feature, address] + payload + Array(repeating: 0, count: count - payload.count - 4)
    }

    public enum Response: Equatable, Sendable {
        case success([UInt8]), rejected(UInt8)
    }

    public func response(to request: HIDPPFrame, direct: Bool) -> Response? {
        guard device == request.device || (direct && device == 0) else { return nil }
        if feature == request.feature && address == request.address {
            return .success(payload)
        }
        if feature == 0xFF || feature == 0x8F,
           address == request.feature, payload.count >= 2, payload[0] == request.address {
            return .rejected(payload[1])
        }
        return nil
    }

    public static func word(_ bytes: [UInt8], at index: Int) -> UInt16? {
        guard index >= 0, index + 1 < bytes.count else { return nil }
        return UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
    }

    public static func bytes(_ word: UInt16) -> [UInt8] {
        [UInt8(word >> 8), UInt8(truncatingIfNeeded: word)]
    }
}

public enum DPICapability {
    /// The adjustable DPI feature lists individual values and can encode a
    /// stepped interval as [minimum, 0xE000 | step, maximum].
    public static func parseList(_ payload: [UInt8]) -> [Int]? {
        guard payload.first == 0 else { return nil }
        return parseRanges(Array(payload.dropFirst()), requiresTerminator: false)
    }

    /// Extended DPI range pages concatenate into the same word stream, but
    /// adjacent ranges may share endpoints and require an end word.
    public static func parseRanges(_ bytes: [UInt8], requiresTerminator: Bool = true) -> [Int]? {
        var values = Set<Int>()
        var previous: Int?
        var terminated = false
        var index = 0
        while let word = HIDPPFrame.word(bytes, at: index) {
            if word == 0 { terminated = true; break }
            index += 2
            if word < 0xE000 {
                previous = Int(word)
                values.insert(Int(word))
                continue
            }
            let step = Int(word & 0x1FFF)
            guard let start = previous, step > 0, let end = HIDPPFrame.word(bytes, at: index),
                  end < 0xE000, Int(end) >= start else { return nil }
            values.formUnion(stride(from: start, through: Int(end), by: step))
            values.insert(Int(end))
            previous = Int(end)
            index += 2
        }
        guard !requiresTerminator || terminated, !values.isEmpty else { return nil }
        return values.sorted()
    }
}

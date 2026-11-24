import Foundation
import MisoCore

struct LogitechFeatures {
    let endpoint: any LogitechTransport
    let slot: UInt8

    func feature(_ id: UInt16, timeout: TimeInterval = 0.45) -> UInt8? {
        guard let index = endpoint.command(
            slot: slot, feature: 0, function: 0, payload: HIDPPFrame.bytes(id), timeout: timeout
        )?.first, index != 0 else { return nil }
        return index
    }

    func call(_ index: UInt8, _ function: UInt8, _ payload: [UInt8] = []) -> [UInt8]? {
        endpoint.command(slot: slot, feature: index, function: function, payload: payload, timeout: 0.45)
    }

    func identity(index: UInt8) -> String? {
        guard let bytes = call(index, 0), bytes.count >= 13,
              bytes[1..<5].contains(where: { $0 != 0 }) else { return nil }
        // Physical unit ID plus six-byte model identifier. Neither is the
        // receiver serial or slot number, so leases follow the same mouse.
        return (Array(bytes[1..<5]) + Array(bytes[7..<13])).map { String(format: "%02X", $0) }.joined()
    }

    func name(index: UInt8) -> String? {
        guard let count = call(index, 0)?.first, count > 0, count <= 64 else { return nil }
        var bytes: [UInt8] = []
        while bytes.count < Int(count) {
            guard let chunk = call(index, 1, [UInt8(bytes.count)]), !chunk.isEmpty else { return nil }
            bytes += chunk
        }
        return String(decoding: bytes.prefix(Int(count)), as: UTF8.self)
    }

    func controls(index: UInt8) -> [UInt16] {
        guard let count = call(index, 0)?.first else { return [] }
        return (0 ..< min(count, 32)).compactMap { offset in
            guard let data = call(index, 1, [offset]), data.count >= 5,
                  let cid = HIDPPFrame.word(data, at: 0), [0x00C3, 0x00D0, 0x01A0].contains(cid),
                  data[4] & 0xA1 == 0x21 else { return nil }
            return cid
        }
    }

    struct Reporting: Codable, Equatable {
        let flags: UInt16
        let target: UInt16

        var isDiverted: Bool { flags & 1 != 0 }
        var hasConflictingMode: Bool { flags & 0x55 != 0 }
    }

    func reporting(_ cid: UInt16, index: UInt8) -> Reporting? {
        guard let data = call(index, 2, HIDPPFrame.bytes(cid)), data.count >= 5,
              HIDPPFrame.word(data, at: 0) == cid,
              let target = HIDPPFrame.word(data, at: 3) else { return nil }
        let extended = data.count > 5 ? UInt16(data[5]) << 8 : 0
        return Reporting(flags: extended | UInt16(data[2]), target: target == 0 ? cid : target)
    }

    func setDiverted(_ diverted: Bool, cid: UInt16, index: UInt8) -> Reporting? {
        // The next bit is the validity mask. Leave raw XY, persistent
        // diversion and the existing mapping target untouched.
        _ = call(index, 3, HIDPPFrame.bytes(cid) + [diverted ? 0x03 : 0x02, 0, 0])
        return reporting(cid, index: index)
    }
}

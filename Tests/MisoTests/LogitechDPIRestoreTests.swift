import Foundation
@testable import Miso
import MisoCore
import Testing

@Test func savedDPIFollowsTheMouseAcrossSessionsAndReceiverSlots() throws {
    let fixture = try DPIFixture()
    defer { fixture.cleanUp() }
    let first = fixture.session()
    let original = try #require(first.discover { true }.mice.first)
    #expect(fixture.transport.writes.isEmpty)
    #expect(first.writeDPI(1300, deviceID: original.descriptor.id).success)

    fixture.transport.x = 1000
    fixture.transport.unit = 2
    let next = fixture.session()
    let replacement = try #require(next.discover { true }.mice.first)
    #expect(replacement.descriptor.dpi?.current == 1000)
    #expect(fixture.transport.writes == [1300])

    fixture.transport.unit = 1
    fixture.transport.slot = 3
    let restored = try #require(next.discover { true }.mice.first)
    #expect(restored.descriptor.id == original.descriptor.id)
    #expect(restored.descriptor.dpi?.current == 1300)
    #expect(fixture.transport.writes == [1300, 1300])
    _ = next.discover { true }
    #expect(fixture.transport.writes == [1300, 1300])
}

@Test func disablingAutomaticDPILeavesTheHardwareAloneUntilReenabled() throws {
    let fixture = try DPIFixture()
    defer { fixture.cleanUp() }
    let session = fixture.session()
    let mouse = try #require(session.discover { false }.mice.first)
    #expect(session.writeDPI(1300, deviceID: mouse.descriptor.id).success)

    fixture.transport.x = 1000
    let disabled = try #require(session.discover { false }.mice.first)
    #expect(disabled.descriptor.dpi?.current == 1000)
    #expect(fixture.transport.writes == [1300])

    let enabled = try #require(session.discover { true }.mice.first)
    #expect(enabled.descriptor.dpi?.current == 1300)
}

@Test func unverifiedDPIEditKeepsTheLastVerifiedSetting() throws {
    let fixture = try DPIFixture()
    defer { fixture.cleanUp() }
    let session = fixture.session()
    let mouse = try #require(session.discover { true }.mice.first)
    #expect(session.writeDPI(1600, deviceID: mouse.descriptor.id).success)

    fixture.transport.writeOverride = 1250
    let failed = session.writeDPI(1300, deviceID: mouse.descriptor.id)
    #expect(!failed.success)
    #expect(failed.actual == 1250)
    let disagreement = try #require(session.discover { true }.mice.first)
    #expect(disagreement.descriptor.dpi?.current == 1250)
    #expect(disagreement.needsDPIRestore)

    fixture.transport.writeOverride = nil
    let restored = try #require(fixture.session().discover { true }.mice.first)
    #expect(restored.descriptor.dpi?.current == 1600)
    #expect(fixture.transport.writes.last == 1600)
}

@Test func automaticDPIRestoreChecksBothAxesOfAnExtendedSensor() throws {
    let fixture = try DPIFixture()
    defer { fixture.cleanUp() }
    fixture.transport.extended = true
    let session = fixture.session()
    let mouse = try #require(session.discover { true }.mice.first)
    #expect(session.writeDPI(1300, deviceID: mouse.descriptor.id).success)

    fixture.transport.y = 1000
    let restored = try #require(session.discover { true }.mice.first)
    #expect(restored.descriptor.dpi?.current == 1300)
    #expect(fixture.transport.y == 1300)
    #expect(fixture.transport.writes == [1300, 1300])
}

private struct DPIFixture {
    let transport = FakeLogitechTransport()
    private let domain = "dev.mousetweaks.MisoTests." + UUID().uuidString
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: domain))
    }

    func session() -> LogitechSession {
        let journal = ControlJournal(url: FileManager.default.temporaryDirectory.appendingPathComponent(domain))
        return LogitechSession(endpoint: transport, journal: journal, defaults: defaults)
    }

    func cleanUp() { defaults.removePersistentDomain(forName: domain) }
}

private final class FakeLogitechTransport: LogitechTransport {
    let product = 0xC548
    let location: Int? = nil
    let name = "USB Receiver"
    let serial: String? = nil
    let transport = "USB"
    let isBolt = true
    var slot: UInt8 = 2
    var unit: UInt8 = 1
    var extended = false
    var x: UInt16 = 1000
    var y: UInt16 = 1000
    var writeOverride: UInt16?
    private(set) var writes: [UInt16] = []

    func receiverRegister(write: [UInt8]?) -> [UInt8]? { [0, 1, 0] }

    func command(
        slot: UInt8, feature: UInt8, function: UInt8, payload: [UInt8], timeout: TimeInterval
    ) -> [UInt8]? {
        guard slot == self.slot else { return nil }
        switch (feature, function) {
        case (0, 0):
            switch HIDPPFrame.word(payload, at: 0) {
            case 0x0003: return [1]
            case 0x0005: return [2]
            case 0x2201 where !extended, 0x2202 where extended: return [3]
            default: return [0]
            }
        case (1, 0): return [0, 0, 0, 0, unit, 0, 0, 0, 0, 0, 0, 0, 4]
        case (2, 0): return [5]
        case (2, 1): return Array("Mouse".utf8)
        case (2, 2): return [3]
        case (3, 0): return [1]
        case (3, 1) where extended: return [0, 0, 1]
        case (3, 1): return [0, 0, 200, 0xE0, 50, 0x1F, 0x40, 0, 0]
        case (3, 2) where extended:
            return [0] + payload.dropFirst() + [0, 200, 0xE0, 50, 0x1F, 0x40, 0, 0, 0, 0, 0, 0, 0]
        case (3, 2): return [0] + HIDPPFrame.bytes(x)
        case (3, 3) where !extended, (3, 6) where extended:
            guard let requested = HIDPPFrame.word(payload, at: 1) else { return nil }
            writes.append(requested)
            x = writeOverride ?? requested
            if let requestedY = HIDPPFrame.word(payload, at: 3) { y = requestedY }
            return [0]
        case (3, 5):
            return [0] + HIDPPFrame.bytes(x) + HIDPPFrame.bytes(1000) + HIDPPFrame.bytes(y) + HIDPPFrame.bytes(1000) + [0]
        default: return nil
        }
    }
}

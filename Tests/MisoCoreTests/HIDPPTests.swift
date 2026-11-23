import MisoCore
import Testing

@Test func parserReadsMXMaster4BoltDPICapabilities() throws {
    // getSensorDpiList response from OpenLogi's MX Master 4 Bolt cassette,
    // fixture dpi-info.json at da245558a4cafef5271480cc10e633c901f62a82.
    let reply: [UInt8] = [
        0x11, 0x02, 0x14, 0x10, 0x00, 0x00, 0xC8, 0xE0, 0x32, 0x1F, 0x40,
        0, 0, 0, 0, 0, 0, 0, 0, 0
    ]
    let frame = try #require(HIDPPFrame(report: reply))
    let values = try #require(DPICapability.parseList(frame.payload))

    #expect(values == Array(stride(from: 200, through: 8000, by: 50)))
    #expect(DPICapability.parseList([0, 0, 200, 0xE0, 0x32, 0]) == nil)
}

@Test func repliesCannotCrossSlotsOrTransactions() throws {
    let request = HIDPPFrame(device: 2, feature: 0x14, address: 0x29, payload: [0])
    let sent = try #require(request.report(id: 0x11))
    #expect(sent.prefix(5).elementsEqual([0x11, 2, 0x14, 0x29, 0]))

    var reply = HIDPPFrame(device: 3, feature: 0x14, address: 0x29, payload: [0, 0x07, 0xD0])
    #expect(reply.response(to: request, direct: false) == nil)
    reply.device = 2
    reply.address = 0x28
    #expect(reply.response(to: request, direct: false) == nil)
    reply.address = 0x29
    #expect(reply.response(to: request, direct: false) == .success([0, 0x07, 0xD0]))
}

@Test func receiverErrorDoesNotWaitForAnImpossibleReply() {
    let request = HIDPPFrame(device: 2, feature: 0, address: 0x0B, payload: [0x22, 1])
    let error = HIDPPFrame(device: 2, feature: 0x8F, address: 0, payload: [0x0B, 0x09, 0])
    #expect(error.response(to: request, direct: false) == .rejected(9))
    #expect(HIDPPFrame(report: [0x11, 2, 0x14, 0x29]) == nil)
}

@Test func extendedDPIRangesAcceptSharedEndpointsAndRequireTerminator() {
    let ranges: [UInt8] = [0, 100, 0xE0, 50, 0, 200, 0xE0, 100, 1, 144, 0, 0]
    #expect(DPICapability.parseRanges(ranges) == [100, 150, 200, 300, 400])
    #expect(DPICapability.parseRanges(Array(ranges.dropLast(2))) == nil)
}

public struct WheelRamp: Codable, Equatable, Sendable {
    public enum Curve: String, Codable, CaseIterable, Sendable {
        case gradual, linear, quick
    }

    public static let rateRange: ClosedRange<Int> = 0...120

    public let startRate: Int
    public let fullRate: Int
    public let curve: Curve

    public init(startRate: Int = 25, fullRate: Int = 50, curve: Curve = .linear) {
        let maximum = Self.rateRange.upperBound
        self.startRate = min(maximum - 1, max(Self.rateRange.lowerBound, startRate))
        self.fullRate = min(maximum, max(self.startRate + 1, fullRate))
        self.curve = curve
    }

    private enum CodingKeys: String, CodingKey {
        case startRate, fullRate, curve
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            startRate: try values.decode(Int.self, forKey: .startRate),
            fullRate: try values.decode(Int.self, forKey: .fullRate),
            curve: try values.decode(Curve.self, forKey: .curve)
        )
    }

    func boostFraction(at rate: Double) -> Double {
        let progress = min(1, max(0, (rate - Double(startRate)) / Double(fullRate - startRate)))
        switch curve {
        case .gradual: return progress * progress
        case .linear: return progress
        case .quick: return progress * (2 - progress)
        }
    }
}

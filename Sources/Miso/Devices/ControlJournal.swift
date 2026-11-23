import Foundation

/// Recorded before a vendor control is first diverted. Successfully settled
/// claims are cleared; the next process can recover after a hard kill.
final class ControlJournal {
    private let url: URL
    private let lock = NSLock()
    private var records: [String: [UInt16: LogitechFeatures.Reporting]]

    init(url: URL) {
        self.url = url
        records = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String: [UInt16: LogitechFeatures.Reporting]].self, from: $0) } ?? [:]
    }

    func claims(for deviceID: String) -> [UInt16: LogitechFeatures.Reporting] {
        lock.withLock { records[deviceID] ?? [:] }
    }

    @discardableResult
    func update(_ value: LogitechFeatures.Reporting?, deviceID: String, cid: UInt16) -> Bool {
        lock.withLock {
            var draft = records
            draft[deviceID, default: [:]][cid] = value
            if draft[deviceID]?.isEmpty == true { draft[deviceID] = nil }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(draft).write(to: url, options: .atomic)
                records = draft
                return true
            } catch {
                return false
            }
        }
    }
}

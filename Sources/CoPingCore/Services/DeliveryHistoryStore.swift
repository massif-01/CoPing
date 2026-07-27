import Foundation

public struct DeliveryHistoryStore {
    public let fileURL: URL
    public let limit: Int
    private let fileManager: FileManager

    public init(
        fileURL: URL = CoPingPaths.historyFile(),
        limit: Int = 100,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.limit = limit
        self.fileManager = fileManager
    }

    public func load() -> [DeliveryRecord] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let records = try? JSONDecoder().decode([DeliveryRecord].self, from: data)
        else {
            return []
        }
        return Array(records.prefix(limit))
    }

    public func save(_ records: [DeliveryRecord]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let trimmed = Array(records.prefix(limit))
        let data = try JSONEncoder().encode(trimmed)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func clear() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
}

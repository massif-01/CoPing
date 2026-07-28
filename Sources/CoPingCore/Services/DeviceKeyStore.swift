import Foundation

public struct DeviceKeyStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL = CoPingPaths.configurationFile(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func read() throws -> String? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(StoredConfiguration.self, from: data).deviceKey
    }

    public func save(_ value: String) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directory.path
        )

        let data = try JSONEncoder().encode(StoredConfiguration(deviceKey: value))
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
    }

}

private struct StoredConfiguration: Codable {
    let deviceKey: String
}

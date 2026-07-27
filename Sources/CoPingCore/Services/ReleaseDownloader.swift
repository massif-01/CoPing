import CryptoKit
import Foundation

public enum ReleaseDownloadError: LocalizedError, Equatable {
    case invalidResponse
    case rejected(Int)
    case invalidChecksumFile
    case checksumMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            AppText.downloadInvalidResponse
        case .rejected(let status):
            AppText.downloadHTTPFailure(status)
        case .invalidChecksumFile:
            AppText.invalidReleaseChecksum
        case .checksumMismatch:
            AppText.releaseChecksumMismatch
        }
    }
}

public struct ReleaseArchiveVerifier {
    public static func expectedSHA256(
        from checksumData: Data,
        archiveName: String
    ) throws -> String {
        guard let contents = String(data: checksumData, encoding: .utf8) else {
            throw ReleaseDownloadError.invalidChecksumFile
        }

        for line in contents.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let first = fields.first else { continue }
            let hash = String(first).lowercased()
            let fileName = fields.dropFirst().first.map {
                String($0).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            }
            if
                hash.count == 64,
                hash.allSatisfy(\.isHexDigit),
                fileName == archiveName
            {
                return hash
            }
        }

        throw ReleaseDownloadError.invalidChecksumFile
    }

    public static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct ReleaseDownloader: Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 600
            self.session = URLSession(configuration: configuration)
        }
    }

    public func download(_ release: AppRelease, to destinationURL: URL) async throws {
        let checksumData = try await data(from: release.checksum.downloadURL)
        let expectedHash = try ReleaseArchiveVerifier.expectedSHA256(
            from: checksumData,
            archiveName: release.archive.name
        )

        var request = URLRequest(url: release.archive.downloadURL)
        request.setValue("CoPing", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await session.download(for: request)
        try validate(response)
        try Task.checkCancellation()

        let actualHash = try ReleaseArchiveVerifier.sha256(of: temporaryURL)
        guard actualHash == expectedHash else {
            throw ReleaseDownloadError.checksumMismatch
        }

        let fileManager = FileManager.default
        let stagingURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).download-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: stagingURL) }
        try fileManager.moveItem(at: temporaryURL, to: stagingURL)

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        }
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("CoPing", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ReleaseDownloadError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ReleaseDownloadError.rejected(http.statusCode)
        }
    }
}

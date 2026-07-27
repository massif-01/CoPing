import Foundation

public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(rawValue: String) {
        let normalized = rawValue.hasPrefix("v")
            ? String(rawValue.dropFirst())
            : rawValue
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard
            components.count == 3,
            components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
            let major = Int(components[0]),
            let minor = Int(components[1]),
            let patch = Int(components[2])
        else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct ReleaseAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    public let size: Int64

    public init(name: String, downloadURL: URL, size: Int64) {
        self.name = name
        self.downloadURL = downloadURL
        self.size = size
    }
}

public struct AppRelease: Equatable, Sendable {
    public static let archiveName = "CoPing-macOS-arm64.zip"
    public static let checksumName = "\(archiveName).sha256"

    public let version: SemanticVersion
    public let tagName: String
    public let publishedAt: Date
    public let pageURL: URL
    public let archive: ReleaseAsset
    public let checksum: ReleaseAsset

    public init(
        version: SemanticVersion,
        tagName: String,
        publishedAt: Date,
        pageURL: URL,
        archive: ReleaseAsset,
        checksum: ReleaseAsset
    ) {
        self.version = version
        self.tagName = tagName
        self.publishedAt = publishedAt
        self.pageURL = pageURL
        self.archive = archive
        self.checksum = checksum
    }
}

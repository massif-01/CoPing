import Foundation

public enum GitHubReleaseError: LocalizedError, Equatable {
    case invalidResponse
    case noPublishedRelease
    case rejected(Int)
    case invalidRelease
    case missingAsset(String)
    case insecureAssetURL

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            AppText.updateInvalidResponse
        case .noPublishedRelease:
            AppText.noPublishedRelease
        case .rejected(let status):
            AppText.updateHTTPFailure(status)
        case .invalidRelease:
            AppText.invalidReleaseMetadata
        case .missingAsset(let name):
            AppText.missingReleaseAsset(name)
        case .insecureAssetURL:
            AppText.insecureReleaseAsset
        }
    }
}

public struct GitHubReleaseClient: Sendable {
    private static let endpoint = URL(
        string: "https://api.github.com/repos/massif-01/CoPing/releases/latest"
    )!

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration)
        }
    }

    public func latestRelease() async throws -> AppRelease {
        var request = URLRequest(
            url: Self.endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CoPing", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubReleaseError.invalidResponse
        }
        if http.statusCode == 404 {
            throw GitHubReleaseError.noPublishedRelease
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubReleaseError.rejected(http.statusCode)
        }

        let payload: ReleasePayload
        do {
            payload = try JSONDecoder.releaseDecoder.decode(ReleasePayload.self, from: data)
        } catch {
            throw GitHubReleaseError.invalidRelease
        }
        guard
            !payload.draft,
            !payload.prerelease,
            let version = SemanticVersion(rawValue: payload.tagName)
        else {
            throw GitHubReleaseError.invalidRelease
        }

        let archive = try payload.asset(named: AppRelease.archiveName)
        let checksum = try payload.asset(named: AppRelease.checksumName)
        guard
            archive.downloadURL.scheme?.lowercased() == "https",
            checksum.downloadURL.scheme?.lowercased() == "https"
        else {
            throw GitHubReleaseError.insecureAssetURL
        }

        return AppRelease(
            version: version,
            tagName: payload.tagName,
            publishedAt: payload.publishedAt,
            pageURL: payload.htmlURL,
            archive: archive,
            checksum: checksum
        )
    }
}

private struct ReleasePayload: Decodable {
    let tagName: String
    let publishedAt: Date
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [AssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    func asset(named name: String) throws -> ReleaseAsset {
        guard let asset = assets.first(where: { $0.name == name }) else {
            throw GitHubReleaseError.missingAsset(name)
        }
        return ReleaseAsset(
            name: asset.name,
            downloadURL: asset.downloadURL,
            size: asset.size
        )
    }
}

private struct AssetPayload: Decodable {
    let name: String
    let downloadURL: URL
    let size: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case size
    }
}

private extension JSONDecoder {
    static var releaseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

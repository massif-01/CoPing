import Foundation

public enum BarkError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidPublicBaseURL
    case invalidDeviceKey
    case deviceKeyNotRegistered
    case invalidResponse
    case rejected(Int)
    case serverRejected(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return AppText.invalidBarkBaseURL
        case .invalidPublicBaseURL:
            return AppText.invalidPublicBarkBaseURL
        case .invalidDeviceKey:
            return AppText.invalidBarkDeviceKey
        case .deviceKeyNotRegistered:
            return AppText.barkDeviceKeyNotRegistered
        case .invalidResponse:
            return AppText.invalidBarkResponse
        case .rejected(let status):
            return AppText.barkHTTPFailure(status)
        case .serverRejected(let code):
            return AppText.barkServerRejected(code)
        }
    }
}

public struct BarkDestination: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let baseURL: URL
    public let deviceKey: String

    public init(
        id: UUID = UUID(),
        baseURL: URL,
        deviceKey: String
    ) throws {
        try Self.validateDeviceKey(deviceKey)
        try BarkClient.validateBaseURL(baseURL)
        self.id = id
        self.baseURL = baseURL
        self.deviceKey = deviceKey
    }

    public init(
        id: UUID = UUID(),
        defaultBaseURLString: String,
        addressInput: String
    ) throws {
        let rawBaseURL = defaultBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configuredBaseURL = URL(string: rawBaseURL) else {
            throw BarkError.invalidBaseURL
        }
        try BarkClient.validateBaseURL(configuredBaseURL)

        let input = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.contains("://") {
            let parsed = try Self.parsePushURL(input, defaultBaseURL: configuredBaseURL)
            try self.init(id: id, baseURL: parsed.baseURL, deviceKey: parsed.deviceKey)
            return
        }

        try self.init(id: id, baseURL: configuredBaseURL, deviceKey: input)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            baseURL: container.decode(URL.self, forKey: .baseURL),
            deviceKey: container.decode(String.self, forKey: .deviceKey)
        )
    }

    public func addressInput(defaultBaseURLString: String) -> String {
        guard
            let defaultBaseURL = URL(
                string: defaultBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            Self.normalizedBaseURL(defaultBaseURL) == Self.normalizedBaseURL(baseURL)
        else {
            return baseURL.appendingPathComponent(deviceKey, isDirectory: false).absoluteString
        }
        return deviceKey
    }

    package var deduplicationKey: String {
        "\(Self.normalizedBaseURL(baseURL))\u{0}\(deviceKey)"
    }

    private static func parsePushURL(
        _ input: String,
        defaultBaseURL: URL
    ) throws -> (baseURL: URL, deviceKey: String) {
        guard
            let pushURL = URL(string: input),
            pushURL.scheme?.lowercased() == "https",
            pushURL.host != nil,
            pushURL.user == nil,
            pushURL.password == nil,
            pushURL.query == nil,
            pushURL.fragment == nil
        else {
            throw BarkError.invalidDeviceKey
        }

        let pushPath = pathComponents(of: pushURL)
        guard !pushPath.isEmpty else {
            throw BarkError.invalidDeviceKey
        }

        let defaultPath = pathComponents(of: defaultBaseURL)
        if
            sameOrigin(pushURL, defaultBaseURL),
            pushPath.starts(with: defaultPath),
            pushPath.count > defaultPath.count
        {
            return (defaultBaseURL, pushPath[defaultPath.count])
        }

        var origin = URLComponents()
        origin.scheme = pushURL.scheme
        origin.host = pushURL.host
        origin.port = pushURL.port
        guard let baseURL = origin.url else {
            throw BarkError.invalidBaseURL
        }
        return (baseURL, pushPath[0])
    }

    private static func validateDeviceKey(_ deviceKey: String) throws {
        guard
            !deviceKey.isEmpty,
            !deviceKey.contains("/"),
            deviceKey.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            throw BarkError.invalidDeviceKey
        }
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && normalizedPort(of: lhs) == normalizedPort(of: rhs)
    }

    private static func pathComponents(of url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" }
    }

    private static func normalizedBaseURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if normalizedPort(of: url) == nil {
            components.port = nil
        }
        var path = components.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" {
            path = ""
        }
        components.percentEncodedPath = path
        return components.string ?? url.absoluteString
    }

    private static func normalizedPort(of url: URL) -> Int? {
        switch (url.scheme?.lowercased(), url.port) {
        case ("https", 443), ("http", 80): nil
        case (_, let port): port
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case baseURL
        case deviceKey
    }
}

public struct BarkConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let deviceKey: String

    public init(baseURLString: String, deviceKeyInput: String) throws {
        let destination = try BarkDestination(
            defaultBaseURLString: baseURLString,
            addressInput: deviceKeyInput
        )
        baseURL = destination.baseURL
        deviceKey = destination.deviceKey
    }
}

public struct BarkClient: PushProvider {
    public let baseURL: URL
    private let deviceKey: String
    private let session: URLSession

    public init(baseURL: URL, deviceKey: String, session: URLSession? = nil) throws {
        try Self.validateBaseURL(baseURL)
        self.baseURL = baseURL
        self.deviceKey = deviceKey
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 10
            self.session = URLSession(configuration: configuration)
        }
    }

    static func validateBaseURL(_ baseURL: URL) throws {
        guard
            baseURL.scheme?.lowercased() == "https",
            baseURL.host != nil,
            baseURL.user == nil,
            baseURL.password == nil,
            baseURL.query == nil,
            baseURL.fragment == nil
        else {
            throw BarkError.invalidBaseURL
        }
        if baseURL.host?.lowercased() == "api.day.app", !["", "/"].contains(baseURL.path) {
            throw BarkError.invalidPublicBaseURL
        }
    }

    public func send(_ notification: PushNotification) async throws {
        let endpoint = baseURL.appendingPathComponent("push", isDirectory: false)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            BarkPayload(
                deviceKey: deviceKey,
                title: notification.title,
                body: notification.body,
                group: notification.group,
                level: notification.level,
                icon: notification.icon?.absoluteString
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BarkError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if
                let result = try? JSONDecoder().decode(BarkResponse.self, from: data),
                result.message?.lowercased().contains("device token") == true
            {
                throw BarkError.deviceKeyNotRegistered
            }
            throw BarkError.rejected(http.statusCode)
        }
        if
            !data.isEmpty,
            let result = try? JSONDecoder().decode(BarkResponse.self, from: data),
            let code = result.code,
            code != 200
        {
            throw BarkError.serverRejected(code)
        }
    }
}

private struct BarkPayload: Encodable {
    let deviceKey: String
    let title: String
    let body: String
    let group: String
    let level: String
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case deviceKey = "device_key"
        case title
        case body
        case group
        case level
        case icon
    }
}

private struct BarkResponse: Decodable {
    let code: Int?
    let message: String?
}

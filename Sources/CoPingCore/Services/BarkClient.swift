import Foundation

public enum BarkError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidDeviceKey
    case invalidResponse
    case rejected(Int)
    case serverRejected(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Bark 服务地址必须是有效的 HTTPS 地址。"
        case .invalidDeviceKey:
            return "请输入 Device Key，或粘贴 Bark 提供的完整推送地址。"
        case .invalidResponse:
            return "Bark 返回了无法识别的响应。"
        case .rejected(let status):
            return "Bark 请求失败（HTTP \(status)）。"
        case .serverRejected(let code):
            return "Bark 服务拒绝了请求（代码 \(code)）。"
        }
    }
}

public struct BarkConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let deviceKey: String

    public init(baseURLString: String, deviceKeyInput: String) throws {
        let rawBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configuredBaseURL = URL(string: rawBaseURL) else {
            throw BarkError.invalidBaseURL
        }
        _ = try BarkClient(baseURL: configuredBaseURL, deviceKey: "validation")

        let input = deviceKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if
            let pastedURL = URL(string: input),
            pastedURL.scheme?.lowercased() == "https",
            pastedURL.host?.lowercased() == "api.day.app"
        {
            let components = pastedURL.pathComponents.filter { $0 != "/" }
            guard let key = components.first, !key.isEmpty else {
                throw BarkError.invalidDeviceKey
            }
            baseURL = URL(string: "https://api.day.app")!
            deviceKey = key
            return
        }

        guard
            !input.isEmpty,
            !input.contains("/"),
            input.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            throw BarkError.invalidDeviceKey
        }
        baseURL = configuredBaseURL
        deviceKey = input
    }
}

public struct BarkClient: PushProvider {
    public let baseURL: URL
    private let deviceKey: String
    private let session: URLSession

    public init(baseURL: URL, deviceKey: String, session: URLSession? = nil) throws {
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
}

import Foundation

public enum NtfyError: LocalizedError, Equatable {
    case invalidResponse
    case redirected
    case rateLimited(Int?)
    case rejected(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            AppText.invalidNtfyResponse
        case .redirected:
            AppText.ntfyRedirectRejected
        case .rateLimited:
            AppText.ntfyRateLimited
        case .rejected(let status):
            AppText.ntfyHTTPFailure(status)
        }
    }
}

extension NtfyError: PushRetryClassifyingError {
    public var isRetryable: Bool {
        switch self {
        case .rateLimited(let retryAfter):
            guard let retryAfter else { return true }
            return (0...10).contains(retryAfter)
        case .rejected(let status):
            return status == 408 || (500..<600).contains(status)
        default:
            return false
        }
    }

    public var suggestedRetryDelay: Duration? {
        guard case .rateLimited(let seconds) = self, let seconds else {
            return nil
        }
        return .seconds(seconds)
    }
}

public struct NtfyClient: PushProvider {
    private let configuration: NtfyConfiguration
    private let session: URLSession

    public init(
        configuration: NtfyConfiguration,
        session: URLSession
    ) {
        self.configuration = configuration
        self.session = session
    }

    public func send(_ notification: PushNotification) async throws {
        var request = URLRequest(url: NtfyConfiguration.serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("CoPing", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            NtfyPayload(
                topic: configuration.topic,
                title: notification.title,
                message: notification.body,
                priority: notification.urgency == .high ? 4 : 3,
                sequenceID: notification.sequenceID
            )
        )

        let (data, response) = try await session.data(
            for: request,
            delegate: NtfyRedirectRejectingDelegate()
        )
        guard let http = response as? HTTPURLResponse else {
            throw NtfyError.invalidResponse
        }
        if (300..<400).contains(http.statusCode) {
            throw NtfyError.redirected
        }
        if http.statusCode == 429 {
            throw NtfyError.rateLimited(
                http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NtfyError.rejected(http.statusCode)
        }
        guard
            let result = try? JSONDecoder().decode(NtfyResponse.self, from: data),
            !result.id.isEmpty,
            result.topic == configuration.topic
        else {
            throw NtfyError.invalidResponse
        }
    }
}

package final class NtfyRedirectRejectingDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    package func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct NtfyPayload: Encodable {
    let topic: String
    let title: String
    let message: String
    let priority: Int
    let sequenceID: String

    enum CodingKeys: String, CodingKey {
        case topic
        case title
        case message
        case priority
        case sequenceID = "sequence_id"
    }
}

private struct NtfyResponse: Decodable {
    let id: String
    let topic: String
}

import Foundation

public enum PushDeliveryRouting {
    public static func eventChannels(
        notificationsEnabled: Bool,
        barkEnabled: Bool,
        ntfyEnabled: Bool
    ) -> [PushChannel] {
        guard notificationsEnabled else { return [] }
        return PushChannel.allCases.filter { channel in
            switch channel {
            case .bark: barkEnabled
            case .ntfy: ntfyEnabled
            }
        }
    }
}

public protocol PushRetryClassifyingError: Error {
    var isRetryable: Bool { get }
    var suggestedRetryDelay: Duration? { get }
}

public struct PushDeliveryTarget: Sendable {
    public let channel: PushChannel
    public let provider: any PushProvider

    public init(channel: PushChannel, provider: any PushProvider) {
        self.channel = channel
        self.provider = provider
    }
}

public struct PushDeliveryDispatcher: Sendable {
    public let retryDelays: [Duration]

    public init(retryDelays: [Duration] = [.seconds(2), .seconds(10)]) {
        self.retryDelays = retryDelays
    }

    public func deliver(
        _ notification: PushNotification,
        to targets: [PushDeliveryTarget]
    ) async throws -> [DeliveryRecord.Attempt] {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(
            of: (Int, DeliveryRecord.Attempt).self,
            returning: [DeliveryRecord.Attempt].self
        ) { group in
            for (index, target) in targets.enumerated() {
                group.addTask {
                    (
                        index,
                        try await deliver(notification, to: target)
                    )
                }
            }

            var indexedAttempts: [(Int, DeliveryRecord.Attempt)] = []
            for try await attempt in group {
                indexedAttempts.append(attempt)
            }
            return indexedAttempts
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }

    private func deliver(
        _ notification: PushNotification,
        to target: PushDeliveryTarget
    ) async throws -> DeliveryRecord.Attempt {
        var retryIndex = 0

        while true {
            try Task.checkCancellation()
            do {
                try await target.provider.send(notification)
                try Task.checkCancellation()
                return DeliveryRecord.Attempt(
                    channel: target.channel,
                    outcome: .sent
                )
            } catch {
                if error is CancellationError || Task.isCancelled {
                    throw CancellationError()
                }
                guard
                    retryIndex < retryDelays.count,
                    let delay = retryDelay(for: error, fallback: retryDelays[retryIndex])
                else {
                    return DeliveryRecord.Attempt(
                        channel: target.channel,
                        outcome: .failed,
                        detail: safeError(error)
                    )
                }

                retryIndex += 1
                try await Task.sleep(for: delay)
            }
        }
    }

    private func retryDelay(for error: Error, fallback: Duration) -> Duration? {
        if let classified = error as? any PushRetryClassifyingError {
            guard classified.isRetryable else { return nil }
            return classified.suggestedRetryDelay ?? fallback
        }

        guard let urlError = error as? URLError else { return nil }
        switch urlError.code {
        case
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
            .timedOut:
            return fallback
        default:
            return nil
        }
    }

    private func safeError(_ error: Error) -> String {
        if error is BarkError || error is NtfyError || error is NtfyConfigurationError {
            return error.localizedDescription
        }
        return AppText.networkRequestFailed
    }
}

extension BarkError: PushRetryClassifyingError {
    public var isRetryable: Bool {
        switch self {
        case .rejected(let status):
            status == 408 || status == 429 || (500..<600).contains(status)
        case .serverRejected(let code):
            code == 408 || code == 429 || (500..<600).contains(code)
        default:
            false
        }
    }

    public var suggestedRetryDelay: Duration? {
        nil
    }
}

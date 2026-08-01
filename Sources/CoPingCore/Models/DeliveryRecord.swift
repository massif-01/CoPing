import CoPingIPC
import Foundation

public enum PushChannel: String, Codable, CaseIterable, Equatable, Sendable {
    case bark
    case ntfy

    public var displayName: String {
        switch self {
        case .bark: "Bark"
        case .ntfy: "NTFY"
        }
    }
}

public struct DeliveryRecord: Codable, Identifiable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case sent
        case failed
        case skipped
    }

    public enum AggregateStatus: Equatable, Sendable {
        case sent
        case partial
        case failed
        case skipped
    }

    public struct Attempt: Codable, Equatable, Sendable {
        public let channel: PushChannel
        public let destinationID: UUID?
        public let destinationLabel: String?
        public let outcome: Outcome
        public let detail: String?

        public init(
            channel: PushChannel,
            destinationID: UUID? = nil,
            destinationLabel: String? = nil,
            outcome: Outcome,
            detail: String? = nil
        ) {
            self.channel = channel
            self.destinationID = destinationID
            self.destinationLabel = destinationLabel
            self.outcome = outcome
            self.detail = detail
        }

        public var displayName: String {
            destinationLabel ?? channel.displayName
        }
    }

    public let id: UUID
    public let timestamp: Date
    public let eventType: CodexEvent.EventType
    public let projectName: String
    public let outcome: Outcome
    public let detail: String?
    public let attempts: [Attempt]?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        eventType: CodexEvent.EventType,
        projectName: String,
        outcome: Outcome,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.projectName = projectName
        self.outcome = outcome
        self.detail = detail
        attempts = nil
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        eventType: CodexEvent.EventType,
        projectName: String,
        attempts: [Attempt],
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.projectName = projectName
        self.attempts = attempts

        if attempts.contains(where: { $0.outcome == .failed }) {
            outcome = .failed
        } else if attempts.contains(where: { $0.outcome == .sent }) {
            outcome = .sent
        } else {
            outcome = .skipped
        }
        self.detail =
            detail
            ?? attempts.first(where: { $0.outcome == .failed })?.detail
            ?? attempts.first(where: { $0.outcome == .skipped })?.detail
    }

    public var effectiveAttempts: [Attempt] {
        if let attempts {
            return attempts
        }
        return [
            Attempt(
                channel: .bark,
                outcome: outcome,
                detail: detail
            )
        ]
    }

    /// A non-persisted view of the per-destination results. Keeping `outcome` in
    /// its original three-value format preserves history compatibility while
    /// allowing mixed destination results to be represented accurately.
    public var aggregateStatus: AggregateStatus {
        Self.aggregateStatus(for: effectiveAttempts, fallback: outcome)
    }

    public static func aggregateStatus(
        for attempts: [Attempt],
        fallback: Outcome = .skipped
    ) -> AggregateStatus {
        guard !attempts.isEmpty else {
            switch fallback {
            case .sent: return .sent
            case .failed: return .failed
            case .skipped: return .skipped
            }
        }

        let hasSent = attempts.contains { $0.outcome == .sent }
        let hasFailed = attempts.contains { $0.outcome == .failed }
        let hasSkipped = attempts.contains { $0.outcome == .skipped }

        if hasSent && (hasFailed || hasSkipped) {
            return .partial
        }
        if hasSent {
            return .sent
        }
        if hasFailed {
            return .failed
        }
        return .skipped
    }
}

import Foundation

public struct DeliveryRecord: Codable, Identifiable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case sent
        case failed
        case skipped
    }

    public let id: UUID
    public let timestamp: Date
    public let eventType: CodexEvent.EventType
    public let projectName: String
    public let outcome: Outcome
    public let detail: String?

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
    }
}

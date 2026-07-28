import Foundation

public struct CodexEvent: Codable, Equatable, Sendable {
    public enum EventType: String, Codable, CaseIterable, Sendable {
        case sessionStarted
        case completed
        case permissionRequested
        case questionRequested
    }

    public let version: Int
    public let type: EventType
    public let sessionID: String
    public let turnID: String?
    public let eventID: String?
    public let projectName: String
    public let timestamp: Date

    public init(
        version: Int = 1,
        type: EventType,
        sessionID: String,
        turnID: String?,
        eventID: String? = nil,
        projectName: String,
        timestamp: Date = Date()
    ) {
        self.version = version
        self.type = type
        self.sessionID = sessionID
        self.turnID = turnID
        self.eventID = eventID
        self.projectName = projectName
        self.timestamp = timestamp
    }

    public var uniqueKey: String {
        [type.rawValue, sessionID, turnID ?? "-", eventID ?? "-"]
            .joined(separator: ":")
    }

    public var verifiesConnection: Bool {
        version == 1
    }

    public var turnKey: String {
        [sessionID, turnID ?? "-"].joined(separator: ":")
    }

    public func addingEventIDIfMissing(_ generatedEventID: @autoclosure () -> String)
        -> CodexEvent
    {
        guard type == .permissionRequested, eventID == nil else { return self }
        return CodexEvent(
            version: version,
            type: type,
            sessionID: sessionID,
            turnID: turnID,
            eventID: generatedEventID(),
            projectName: projectName,
            timestamp: timestamp
        )
    }
}

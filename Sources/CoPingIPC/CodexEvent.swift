import Foundation

public struct CodexEvent: Codable, Equatable, Sendable {
    public enum EventType: String, Codable, CaseIterable, Sendable {
        case sessionStarted
        case completed
        case permissionRequested
        case questionRequested
    }

    public enum Phase: String, Codable, Sendable {
        case requested, accepted, resolved, stopCandidate
    }
    public enum QuestionMode: String, Codable, Sendable { case blocking, async, unknown }
    public enum IdentityQuality: String, Codable, Sendable { case strong, weak }
    public let callID: String?
    public let phase: Phase?
    public let questionMode: QuestionMode?
    /// Opaque installation/source token; never a filesystem path.
    public let sourceID: String?
    public var identityQuality: IdentityQuality {
        callID != nil ? .strong : .weak
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
        callID: String? = nil,
        phase: Phase? = nil,
        questionMode: QuestionMode? = nil,
        sourceID: String? = nil,
        projectName: String,
        timestamp: Date = Date()
    ) {
        self.callID = callID
        self.phase = phase
        self.questionMode = questionMode
        self.sourceID = sourceID
        self.version = version
        self.type = type
        self.sessionID = sessionID
        self.turnID = turnID
        self.eventID = eventID
        self.projectName = projectName
        self.timestamp = timestamp
    }

    public var uniqueKey: String {
        // JSON array encoding preserves boundaries and distinguishes nil from literal markers.
        Self.key([type.rawValue, sessionID, turnID, callID ?? eventID, phase?.rawValue, sourceID])
    }

    public static func key(_ fields: [String?]) -> String {
        String(decoding: try! JSONEncoder().encode(fields), as: UTF8.self)
    }

    public var verifiesConnection: Bool {
        version == 1
    }

    public var turnKey: String {
        Self.key([sessionID, turnID, sourceID])
    }

    public func addingEventIDIfMissing()
        -> CodexEvent
    {
        guard type != .sessionStarted, eventID == nil, callID == nil else { return self }
        return CodexEvent(
            version: version,
            type: type,
            sessionID: sessionID,
            turnID: turnID,
            // Old wire payloads already carry their creation timestamp. Normalize
            // deterministically at ingress; a receive attempt is not a new event.
            eventID: "legacy-wire:" + Self.key([String(version), type.rawValue, sessionID,
                turnID, sourceID, phase?.rawValue, questionMode?.rawValue, projectName,
                String(timestamp.timeIntervalSinceReferenceDate.bitPattern, radix: 16)]),
            callID: callID,
            phase: phase,
            questionMode: questionMode,
            sourceID: sourceID,
            projectName: projectName,
            timestamp: timestamp
        )
    }
}

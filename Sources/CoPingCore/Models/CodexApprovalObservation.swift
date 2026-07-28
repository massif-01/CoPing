import Foundation

public enum CodexApprovalMonitorHealth: Equatable, Sendable {
    case stopped
    case connecting
    case ready
    case unavailable
    case unsupportedProtocol(Int?)
}

public enum CodexAutomaticApprovalStatus: Equatable, Sendable {
    case inProgress
    case approved
    case denied
    case timedOut
    case aborted
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "inProgress":
            self = .inProgress
        case "approved":
            self = .approved
        case "denied":
            self = .denied
        case "timedOut":
            self = .timedOut
        case "aborted":
            self = .aborted
        default:
            self = .unknown
        }
    }
}

public struct CodexApprovalObservation: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case snapshot
        case live
    }

    public enum Kind: Equatable, Sendable {
        case permissionRequested(targetItemID: String, startedAt: Date)
        case automaticReview(
            targetItemID: String?,
            status: CodexAutomaticApprovalStatus,
            startedAt: Date
        )
        case waitingOnApproval(Bool)
    }

    public let sessionID: String
    public let turnID: String?
    public let source: Source
    public let kind: Kind

    public init(
        sessionID: String,
        turnID: String?,
        source: Source,
        kind: Kind
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.source = source
        self.kind = kind
    }
}

public struct CodexPendingApprovalReference: Equatable, Sendable {
    public let key: String
    public let sessionID: String
    public let turnID: String?
    public let targetItemID: String?
    public let requestedAt: Date

    public init(
        key: String,
        sessionID: String,
        turnID: String?,
        targetItemID: String?,
        requestedAt: Date
    ) {
        self.key = key
        self.sessionID = sessionID
        self.turnID = turnID
        self.targetItemID = targetItemID
        self.requestedAt = requestedAt
    }
}

public enum CodexApprovalCorrelation {
    public static func matchingPendingKey(
        sessionID: String,
        turnID: String?,
        targetItemID: String?,
        startedAt: Date,
        candidates: [CodexPendingApprovalReference],
        maximumUnlinkedInterval: TimeInterval = 30
    ) -> String? {
        let matches = candidates.compactMap {
            candidate -> (reference: CodexPendingApprovalReference, exact: Bool)? in
            guard candidate.sessionID == sessionID else { return nil }
            if
                let turnID,
                let candidateTurnID = candidate.turnID,
                candidateTurnID != turnID
            {
                return nil
            }

            if let targetItemID, let candidateTargetItemID = candidate.targetItemID {
                guard candidateTargetItemID == targetItemID else { return nil }
                return (candidate, true)
            }

            let interval = abs(candidate.requestedAt.timeIntervalSince(startedAt))
            guard interval <= maximumUnlinkedInterval else { return nil }
            return (candidate, false)
        }

        return matches.min {
            if $0.exact != $1.exact {
                return $0.exact
            }
            return abs($0.reference.requestedAt.timeIntervalSince(startedAt))
                < abs($1.reference.requestedAt.timeIntervalSince(startedAt))
        }?.reference.key
    }
}

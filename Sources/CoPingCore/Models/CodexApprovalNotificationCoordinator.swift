import Foundation

public enum CodexApprovalNotificationCause: Equatable, Sendable {
    case requiresUserAction
    case unknownState
}

public enum CodexApprovalCoordinatorEffect: Equatable, Sendable {
    case scheduleUnknownFallback(key: String)
    case cancelUnknownFallback(key: String)
    case notify(event: CodexEvent, cause: CodexApprovalNotificationCause)
    case followSession(String)
    case unfollowSession(String)
}

public struct CodexApprovalNotificationCoordinator: Sendable {
    private struct Pending: Sendable {
        let event: CodexEvent
        var targetItemID: String?
        var fallbackScheduled: Bool
        var automaticReviewInProgress: Bool
    }

    private struct PermissionFact: Equatable, Sendable {
        let sessionID: String
        let turnID: String?
        let targetItemID: String
        let startedAt: Date
    }

    private struct ReviewFact: Equatable, Sendable {
        let sessionID: String
        let turnID: String?
        let targetItemID: String?
        let status: CodexAutomaticApprovalStatus
        let startedAt: Date
    }

    private var pending: [String: Pending] = [:]
    private var permissionFacts: [PermissionFact] = []
    private var reviewFacts: [ReviewFact] = []
    private var followedSessions: Set<String> = []
    private var waitingSessions: Set<String> = []
    private var waitingTurnBySession: [String: String] = [:]
    private var waitingEpisodeCountBySession: [String: Int] = [:]
    private var monitorHealth: CodexApprovalMonitorHealth = .stopped

    public init() {}

    public var pendingEvents: [CodexEvent] {
        pending.values.map(\.event).sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            return $0.uniqueKey < $1.uniqueKey
        }
    }

    public mutating func receive(
        _ event: CodexEvent
    ) -> [CodexApprovalCoordinatorEffect] {
        guard event.type == .permissionRequested else { return [] }

        if isWaiting(sessionID: event.sessionID, turnID: event.turnID) {
            return []
        }

        let key = event.uniqueKey
        guard pending[key] == nil else { return [] }
        pending[key] = Pending(
            event: event,
            targetItemID: nil,
            fallbackScheduled: false,
            automaticReviewInProgress: false
        )

        var effects: [CodexApprovalCoordinatorEffect] = []
        associateCachedPermissionFact(withPendingKey: key)
        applyCachedReview(toPendingKey: key, effects: &effects)
        if
            let candidate = pending[key],
            !candidate.automaticReviewInProgress
        {
            ensureFallback(for: key, effects: &effects)
        }
        reconcileFollowers(effects: &effects)
        return effects
    }

    public mutating func receive(
        _ observation: CodexApprovalObservation,
        now: Date = Date()
    ) -> [CodexApprovalCoordinatorEffect] {
        var effects: [CodexApprovalCoordinatorEffect] = []

        switch observation.kind {
        case let .permissionRequested(targetItemID, startedAt):
            let fact = PermissionFact(
                sessionID: observation.sessionID,
                turnID: observation.turnID,
                targetItemID: targetItemID,
                startedAt: startedAt
            )
            if !permissionFacts.contains(fact) {
                permissionFacts.append(fact)
            }
            associatePendingPermission(with: fact, effects: &effects)

        case let .automaticReview(targetItemID, status, startedAt):
            let fact = ReviewFact(
                sessionID: observation.sessionID,
                turnID: observation.turnID,
                targetItemID: targetItemID,
                status: status,
                startedAt: startedAt
            )
            if !reviewFacts.contains(fact) {
                reviewFacts.append(fact)
            }
            applyReviewFact(fact, effects: &effects)

        case let .waitingOnApproval(waiting):
            handleWaiting(
                waiting,
                sessionID: observation.sessionID,
                turnID: observation.turnID,
                now: now,
                effects: &effects
            )
        }

        trimFacts()
        reconcileFollowers(effects: &effects)
        return effects
    }

    public mutating func monitorHealthChanged(
        _ health: CodexApprovalMonitorHealth
    ) -> [CodexApprovalCoordinatorEffect] {
        guard monitorHealth != health else { return [] }
        monitorHealth = health

        var effects: [CodexApprovalCoordinatorEffect] = []
        switch health {
        case .unavailable, .unsupportedProtocol:
            for key in pending.keys.sorted() {
                ensureFallback(for: key, effects: &effects)
            }
        case .stopped, .connecting, .ready:
            break
        }
        return effects
    }

    public mutating func unknownFallbackFired(
        key: String
    ) -> [CodexApprovalCoordinatorEffect] {
        guard let candidate = pending[key], candidate.fallbackScheduled else {
            return []
        }

        pending.removeValue(forKey: key)
        var effects: [CodexApprovalCoordinatorEffect] = [
            .notify(event: candidate.event, cause: .unknownState)
        ]
        reconcileFollowers(effects: &effects)
        return effects
    }

    public mutating func complete(
        sessionID: String,
        turnID: String?
    ) -> [CodexApprovalCoordinatorEffect] {
        var effects: [CodexApprovalCoordinatorEffect] = []
        let keys = pending.compactMap { key, candidate in
            matchesTurn(
                sessionID: candidate.event.sessionID,
                turnID: candidate.event.turnID,
                expectedSessionID: sessionID,
                expectedTurnID: turnID
            ) ? key : nil
        }
        removePending(keys: keys, effects: &effects)
        removeFacts(sessionID: sessionID, turnID: turnID)
        waitingSessions.remove(sessionID)
        waitingTurnBySession.removeValue(forKey: sessionID)
        reconcileFollowers(effects: &effects)
        return effects
    }

    public mutating func reset() -> [CodexApprovalCoordinatorEffect] {
        var effects: [CodexApprovalCoordinatorEffect] = []
        removePending(keys: Array(pending.keys), effects: &effects)
        permissionFacts.removeAll()
        reviewFacts.removeAll()
        waitingSessions.removeAll()
        waitingTurnBySession.removeAll()
        waitingEpisodeCountBySession.removeAll()
        monitorHealth = .stopped
        reconcileFollowers(effects: &effects)
        return effects
    }

    private mutating func associateCachedPermissionFact(
        withPendingKey key: String
    ) {
        guard let candidate = pending[key], candidate.targetItemID == nil else {
            return
        }
        let usedTargetIDs = Set(pending.values.compactMap(\.targetItemID))
        let matchingFacts = permissionFacts.filter {
            !usedTargetIDs.contains($0.targetItemID)
                && matches(
                    event: candidate.event,
                    sessionID: $0.sessionID,
                    turnID: $0.turnID,
                    startedAt: $0.startedAt
                )
        }
        guard let fact = matchingFacts.min(by: {
            abs($0.startedAt.timeIntervalSince(candidate.event.timestamp))
                < abs($1.startedAt.timeIntervalSince(candidate.event.timestamp))
        }) else {
            return
        }
        pending[key]?.targetItemID = fact.targetItemID
        permissionFacts.removeAll { $0 == fact }
    }

    private mutating func associatePendingPermission(
        with fact: PermissionFact,
        effects: inout [CodexApprovalCoordinatorEffect]
    ) {
        let usedTargetIDs = Set(pending.values.compactMap(\.targetItemID))
        guard !usedTargetIDs.contains(fact.targetItemID) else { return }

        let candidates = pending.compactMap {
            key, candidate -> CodexPendingApprovalReference? in
            guard candidate.targetItemID == nil else { return nil }
            return CodexPendingApprovalReference(
                key: key,
                sessionID: candidate.event.sessionID,
                turnID: candidate.event.turnID,
                targetItemID: nil,
                requestedAt: candidate.event.timestamp
            )
        }
        guard let key = CodexApprovalCorrelation.matchingPendingKey(
            sessionID: fact.sessionID,
            turnID: fact.turnID,
            targetItemID: fact.targetItemID,
            startedAt: fact.startedAt,
            candidates: candidates
        ) else {
            return
        }

        pending[key]?.targetItemID = fact.targetItemID
        permissionFacts.removeAll { $0 == fact }
        applyCachedReview(toPendingKey: key, effects: &effects)
    }

    private mutating func applyCachedReview(
        toPendingKey key: String,
        effects: inout [CodexApprovalCoordinatorEffect]
    ) {
        guard let candidate = pending[key] else { return }
        let reference = CodexPendingApprovalReference(
            key: key,
            sessionID: candidate.event.sessionID,
            turnID: candidate.event.turnID,
            targetItemID: candidate.targetItemID,
            requestedAt: candidate.event.timestamp
        )
        let matches = reviewFacts.enumerated().filter {
            CodexApprovalCorrelation.matchingPendingKey(
                sessionID: $0.element.sessionID,
                turnID: $0.element.turnID,
                targetItemID: $0.element.targetItemID,
                startedAt: $0.element.startedAt,
                candidates: [reference]
            ) == key
        }
        guard let indexedFact = matches.min(by: {
            let leftInterval = abs(
                $0.element.startedAt.timeIntervalSince(candidate.event.timestamp)
            )
            let rightInterval = abs(
                $1.element.startedAt.timeIntervalSince(candidate.event.timestamp)
            )
            if leftInterval != rightInterval {
                return leftInterval < rightInterval
            }
            return $0.offset > $1.offset
        }) else {
            return
        }
        let fact = indexedFact.element
        apply(fact, toPendingKey: key, effects: &effects)
    }

    private mutating func applyReviewFact(
        _ fact: ReviewFact,
        effects: inout [CodexApprovalCoordinatorEffect]
    ) {
        let candidates = pending.map {
            key, candidate in
            CodexPendingApprovalReference(
                key: key,
                sessionID: candidate.event.sessionID,
                turnID: candidate.event.turnID,
                targetItemID: candidate.targetItemID,
                requestedAt: candidate.event.timestamp
            )
        }
        guard let key = CodexApprovalCorrelation.matchingPendingKey(
            sessionID: fact.sessionID,
            turnID: fact.turnID,
            targetItemID: fact.targetItemID,
            startedAt: fact.startedAt,
            candidates: candidates
        ) else {
            return
        }
        apply(fact, toPendingKey: key, effects: &effects)
    }

    private mutating func apply(
        _ fact: ReviewFact,
        toPendingKey key: String,
        effects: inout [CodexApprovalCoordinatorEffect]
    ) {
        guard pending[key] != nil else { return }
        if pending[key]?.targetItemID == nil, let targetItemID = fact.targetItemID {
            pending[key]?.targetItemID = targetItemID
        }

        switch fact.status {
        case .inProgress:
            reviewFacts.removeAll { $0 == fact }
            pending[key]?.automaticReviewInProgress = true
            cancelFallback(for: key, effects: &effects)
        case .approved, .denied, .timedOut, .aborted:
            reviewFacts.removeAll {
                $0.sessionID == fact.sessionID
                    && $0.turnID == fact.turnID
                    && (
                        $0.targetItemID == fact.targetItemID
                            || $0.targetItemID == nil
                            || fact.targetItemID == nil
                    )
                    && $0.startedAt == fact.startedAt
            }
            removePending(keys: [key], effects: &effects)
        case .unknown:
            reviewFacts.removeAll { $0 == fact }
            pending[key]?.automaticReviewInProgress = false
            ensureFallback(for: key, effects: &effects)
        }
    }

    private mutating func handleWaiting(
        _ waiting: Bool,
        sessionID: String,
        turnID: String?,
        now: Date,
        effects: inout [CodexApprovalCoordinatorEffect]
    ) {
        if !waiting {
            waitingSessions.remove(sessionID)
            waitingTurnBySession.removeValue(forKey: sessionID)
            return
        }
        guard !waitingSessions.contains(sessionID) else { return }
        waitingSessions.insert(sessionID)
        if let turnID {
            waitingTurnBySession[sessionID] = turnID
        } else {
            waitingTurnBySession.removeValue(forKey: sessionID)
        }

        let keys = pending.compactMap { key, candidate in
            matchesTurn(
                sessionID: candidate.event.sessionID,
                turnID: candidate.event.turnID,
                expectedSessionID: sessionID,
                expectedTurnID: turnID
            ) ? key : nil
        }
        if let notificationKey = keys.max(by: {
            guard let left = pending[$0]?.event, let right = pending[$1]?.event else {
                return $0 < $1
            }
            if left.timestamp != right.timestamp {
                return left.timestamp < right.timestamp
            }
            return left.uniqueKey < right.uniqueKey
        }), let event = pending[notificationKey]?.event {
            removePending(keys: keys, effects: &effects)
            effects.append(.notify(event: event, cause: .requiresUserAction))
            removeFacts(sessionID: sessionID, turnID: turnID)
            return
        }

        let episode = (waitingEpisodeCountBySession[sessionID] ?? 0) + 1
        waitingEpisodeCountBySession[sessionID] = episode
        let event = CodexEvent(
            type: .permissionRequested,
            sessionID: sessionID,
            turnID: turnID,
            eventID: "approval-state-\(episode)",
            projectName: "Codex",
            timestamp: now
        )
        effects.append(.notify(event: event, cause: .requiresUserAction))
        removeFacts(sessionID: sessionID, turnID: turnID)
    }

    private mutating func ensureFallback(
        for key: String,
        effects: inout [CodexApprovalCoordinatorEffect]
    ) {
        guard var candidate = pending[key], !candidate.fallbackScheduled else {
            return
        }
        candidate.fallbackScheduled = true
        pending[key] = candidate
        effects.append(.scheduleUnknownFallback(key: key))
    }

    private mutating func cancelFallback(
        for key: String,
        effects: inout [CodexApprovalCoordinatorEffect]
    ) {
        guard var candidate = pending[key], candidate.fallbackScheduled else {
            return
        }
        candidate.fallbackScheduled = false
        pending[key] = candidate
        effects.append(.cancelUnknownFallback(key: key))
    }

    private mutating func removePending(
        keys: [String],
        effects: inout [CodexApprovalCoordinatorEffect]
    ) {
        for key in Set(keys).sorted() {
            guard let candidate = pending.removeValue(forKey: key) else { continue }
            if candidate.fallbackScheduled {
                effects.append(.cancelUnknownFallback(key: key))
            }
        }
    }

    private mutating func reconcileFollowers(
        effects: inout [CodexApprovalCoordinatorEffect]
    ) {
        let desired = Set(pending.values.map(\.event.sessionID))
        for sessionID in desired.subtracting(followedSessions).sorted() {
            effects.append(.followSession(sessionID))
        }
        for sessionID in followedSessions.subtracting(desired).sorted() {
            effects.append(.unfollowSession(sessionID))
        }
        followedSessions = desired
    }

    private func isWaiting(sessionID: String, turnID: String?) -> Bool {
        guard waitingSessions.contains(sessionID) else { return false }
        guard let storedTurnID = waitingTurnBySession[sessionID], let turnID else {
            return true
        }
        return storedTurnID == turnID
    }

    private func matches(
        event: CodexEvent,
        sessionID: String,
        turnID: String?,
        startedAt: Date
    ) -> Bool {
        guard event.sessionID == sessionID else { return false }
        if let eventTurnID = event.turnID, let turnID, eventTurnID != turnID {
            return false
        }
        return abs(event.timestamp.timeIntervalSince(startedAt)) <= 30
    }

    private func matchesTurn(
        sessionID: String,
        turnID: String?,
        expectedSessionID: String,
        expectedTurnID: String?
    ) -> Bool {
        guard sessionID == expectedSessionID else { return false }
        guard let turnID, let expectedTurnID else { return true }
        return turnID == expectedTurnID
    }

    private mutating func removeFacts(sessionID: String, turnID: String?) {
        permissionFacts.removeAll {
            guard $0.sessionID == sessionID else { return false }
            guard let factTurnID = $0.turnID, let turnID else { return true }
            return factTurnID == turnID
        }
        reviewFacts.removeAll {
            guard $0.sessionID == sessionID else { return false }
            guard let factTurnID = $0.turnID, let turnID else { return true }
            return factTurnID == turnID
        }
    }

    private mutating func trimFacts() {
        if permissionFacts.count > 100 {
            permissionFacts.removeFirst(permissionFacts.count - 100)
        }
        if reviewFacts.count > 100 {
            reviewFacts.removeFirst(reviewFacts.count - 100)
        }
    }
}

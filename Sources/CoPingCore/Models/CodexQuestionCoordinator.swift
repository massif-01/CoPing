import CoPingIPC
import Foundation

/// Pure state machine. The caller owns timers; take() is the final eligibility check.
/// No transcript text, answer text, or arbitrary tool output crosses this boundary.
public struct CodexQuestionCoordinator {
    public enum Effect: Equatable {
        case schedule(String), cancel(String)
    }
    private var pending: [String: CodexEvent] = [:]
    private var terminal: [String] = []
    private var candidates: [String: Date] = [:]
    private let limit = 200
    public init() {}
    public var pendingCount: Int { pending.count }
    public var candidateCount: Int { candidates.count }

    private func key(_ event: CodexEvent) -> String {
        CodexEvent.key([event.sourceID, event.sessionID, event.turnID,
                        event.callID ?? event.eventID])
    }

    public mutating func receive(_ event: CodexEvent, now: Date = Date()) -> [Effect] {
        guard event.type == .questionRequested else { return [] }
        candidates = candidates.filter { now.timeIntervalSince($0.value) < 60 }
        let key = key(event)
        if event.phase == .resolved {
            // A native call within the exact source/session/optional-turn scope is
            // sufficient. Missing turn is a value, never a session wildcard.
            guard event.callID != nil else { return [] }
            rememberTerminal(key)
            candidates.removeValue(forKey: key)
            pending.removeValue(forKey: key)
            return [.cancel(key)]
        }
        guard !terminal.contains(key), pending[key] == nil else { return [] }
        if event.questionMode == .async && event.phase != .accepted {
            candidates[key] = now
            if candidates.count > limit, let oldest = candidates.min(by: { $0.value < $1.value })?.key {
                candidates.removeValue(forKey: oldest)
            }
            return []
        }
        candidates.removeValue(forKey: key)
        var effects: [Effect] = []
        if pending.count >= limit, let oldest = pending.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
            pending.removeValue(forKey: oldest)
            rememberTerminal(oldest)
            effects.append(.cancel(oldest))
        }
        pending[key] = event
        effects.append(.schedule(key))
        return effects
    }

    public mutating func take(_ key: String) -> CodexEvent? {
        guard let event = pending.removeValue(forKey: key) else { return nil }
        rememberTerminal(key)
        return event
    }

    public mutating func reset() -> [Effect] {
        let effects = pending.keys.map(Effect.cancel)
        for key in pending.keys { rememberTerminal(key) }
        for key in candidates.keys { rememberTerminal(key) }
        pending.removeAll()
        candidates.removeAll()
        return effects
    }

    private mutating func rememberTerminal(_ key: String) {
        if !terminal.contains(key) { terminal.append(key) }
        if terminal.count > limit { terminal.removeFirst(terminal.count - limit) }
    }
}

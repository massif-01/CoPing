import Foundation

public enum CodexApprovalStateDecodeError: Error, Equatable {
    case invalidMessage
    case unsupportedVersion(Int?)
}

public final class CodexApprovalStateDecoder {
    private var turnIDsBySessionAndEntity: [String: [String: String]] = [:]
    private var waitingOnApprovalBySession: [String: Bool] = [:]
    private var activeTurnIDBySession: [String: String] = [:]

    public init() {}

    public func decode(_ data: Data) throws -> [CodexApprovalObservation] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CodexApprovalStateDecodeError.invalidMessage
        }
        return try decodeJSONObject(root)
    }

    public func decodeJSONObject(
        _ root: [String: Any]
    ) throws -> [CodexApprovalObservation] {
        guard
            root["type"] as? String == "broadcast",
            root["method"] as? String == "thread-stream-state-changed"
        else {
            throw CodexApprovalStateDecodeError.invalidMessage
        }
        let version = (root["version"] as? NSNumber)?.intValue
        guard version == 11 else {
            throw CodexApprovalStateDecodeError.unsupportedVersion(version)
        }
        guard
            let params = root["params"] as? [String: Any],
            let sessionID = params["conversationId"] as? String,
            !sessionID.isEmpty,
            let change = params["change"] as? [String: Any],
            let changeType = change["type"] as? String
        else {
            throw CodexApprovalStateDecodeError.invalidMessage
        }

        switch changeType {
        case "snapshot":
            guard let state = change["conversationState"] as? [String: Any] else {
                throw CodexApprovalStateDecodeError.invalidMessage
            }
            return decodeSnapshot(state, sessionID: sessionID)
        case "patches":
            guard let patches = change["patches"] as? [[String: Any]] else {
                throw CodexApprovalStateDecodeError.invalidMessage
            }
            return decodePatches(patches, sessionID: sessionID)
        default:
            throw CodexApprovalStateDecodeError.invalidMessage
        }
    }

    public func removeSession(_ sessionID: String) {
        turnIDsBySessionAndEntity.removeValue(forKey: sessionID)
        waitingOnApprovalBySession.removeValue(forKey: sessionID)
        activeTurnIDBySession.removeValue(forKey: sessionID)
    }

    public func reset() {
        turnIDsBySessionAndEntity.removeAll()
        waitingOnApprovalBySession.removeAll()
        activeTurnIDBySession.removeAll()
    }

    private func decodeSnapshot(
        _ state: [String: Any],
        sessionID: String
    ) -> [CodexApprovalObservation] {
        var observations: [CodexApprovalObservation] = []
        var turnIDsByEntity: [String: String] = [:]
        var latestActiveTurn: (id: String, startedAt: Double)?

        if
            let turnHistory = state["turnHistory"] as? [String: Any],
            let history = turnHistory["history"] as? [String: Any],
            let entities = history["entitiesByKey"] as? [String: Any]
        {
            for (entityKey, value) in entities {
                guard
                    let turn = value as? [String: Any],
                    let turnID = turn["turnId"] as? String
                else {
                    continue
                }
                turnIDsByEntity[entityKey] = turnID

                if turn["status"] as? String == "inProgress" {
                    let startedAt = number(turn["turnStartedAtMs"]) ?? 0
                    if latestActiveTurn == nil || startedAt > latestActiveTurn!.startedAt {
                        latestActiveTurn = (turnID, startedAt)
                    }
                }

                observations.append(
                    contentsOf: decodeTurnContent(
                        turn,
                        sessionID: sessionID,
                        turnID: turnID,
                        source: .snapshot
                    )
                )
            }
        }

        turnIDsBySessionAndEntity[sessionID] = turnIDsByEntity
        if let latestActiveTurn {
            activeTurnIDBySession[sessionID] = latestActiveTurn.id
        } else {
            activeTurnIDBySession.removeValue(forKey: sessionID)
        }

        let waiting = waitingOnApproval(in: state["threadRuntimeStatus"])
        waitingOnApprovalBySession[sessionID] = waiting
        observations.append(
            CodexApprovalObservation(
                sessionID: sessionID,
                turnID: activeTurnIDBySession[sessionID],
                source: .snapshot,
                kind: .waitingOnApproval(waiting)
            )
        )
        return observations
    }

    private func decodePatches(
        _ patches: [[String: Any]],
        sessionID: String
    ) -> [CodexApprovalObservation] {
        var observations: [CodexApprovalObservation] = []

        for patch in patches {
            let operation = patch["op"] as? String ?? ""
            let path = pathComponents(patch["path"])
            let value = patch["value"]
            let entityKey = entityKey(in: path)
            var turnID = entityKey.flatMap {
                turnIDsBySessionAndEntity[sessionID]?[$0]
            }

            if let dictionary = value as? [String: Any] {
                if let patchedTurnID = dictionary["turnId"] as? String {
                    turnID = patchedTurnID
                    if let entityKey {
                        turnIDsBySessionAndEntity[sessionID, default: [:]][entityKey] =
                            patchedTurnID
                    }
                    if dictionary["status"] as? String == "inProgress" {
                        activeTurnIDBySession[sessionID] = patchedTurnID
                    }
                }

                observations.append(
                    contentsOf: decodeTurnContent(
                        dictionary,
                        sessionID: sessionID,
                        turnID: turnID,
                        source: .live
                    )
                )
            }

            if path.contains("threadRuntimeStatus") {
                let previous = waitingOnApprovalBySession[sessionID] ?? false
                let waiting: Bool
                if let dictionary = value as? [String: Any] {
                    waiting = waitingOnApproval(in: dictionary)
                } else if let flags = value as? [String] {
                    waiting = flags.contains("waitingOnApproval")
                } else if value as? String == "waitingOnApproval" {
                    waiting = operation != "remove"
                } else if operation == "remove" && path.contains("activeFlags") {
                    waiting = false
                } else {
                    waiting = previous
                }

                waitingOnApprovalBySession[sessionID] = waiting
                if waiting != previous {
                    observations.append(
                        CodexApprovalObservation(
                            sessionID: sessionID,
                            turnID: activeTurnIDBySession[sessionID] ?? turnID,
                            source: .live,
                            kind: .waitingOnApproval(waiting)
                        )
                    )
                }
            }
        }

        return observations
    }

    private func decodeTurnContent(
        _ value: [String: Any],
        sessionID: String,
        turnID: String?,
        source: CodexApprovalObservation.Source
    ) -> [CodexApprovalObservation] {
        var observations: [CodexApprovalObservation] = []

        if let observation = decodePermissionRequest(
            value,
            sessionID: sessionID,
            turnID: turnID,
            source: source
        ) {
            observations.append(observation)
        }
        if let observation = decodeAutomaticReview(
            value,
            sessionID: sessionID,
            turnID: turnID,
            source: source
        ) {
            observations.append(observation)
        }

        if let run = value["run"] as? [String: Any],
            let observation = decodePermissionRequest(
                run,
                sessionID: sessionID,
                turnID: turnID,
                source: source
            )
        {
            observations.append(observation)
        }
        if let hookRuns = value["hookRuns"] as? [[String: Any]] {
            for hookRun in hookRuns {
                let run = hookRun["run"] as? [String: Any] ?? hookRun
                if let observation = decodePermissionRequest(
                    run,
                    sessionID: sessionID,
                    turnID: turnID,
                    source: source
                ) {
                    observations.append(observation)
                }
            }
        }
        if let items = value["items"] as? [[String: Any]] {
            for item in items {
                if let observation = decodeAutomaticReview(
                    item,
                    sessionID: sessionID,
                    turnID: turnID,
                    source: source
                ) {
                    observations.append(observation)
                }
            }
        }
        return observations
    }

    private func decodePermissionRequest(
        _ value: [String: Any],
        sessionID: String,
        turnID: String?,
        source: CodexApprovalObservation.Source
    ) -> CodexApprovalObservation? {
        let normalizedEventName = (value["eventName"] as? String ?? "")
            .lowercased()
            .filter(\.isLetter)
        guard normalizedEventName == "permissionrequest" else { return nil }
        guard
            let runID = value["id"] as? String,
            let targetItemID = targetItemID(fromHookRunID: runID),
            let rawStartedAt = number(value["startedAt"])
        else {
            return nil
        }

        return CodexApprovalObservation(
            sessionID: sessionID,
            turnID: turnID,
            source: source,
            kind: .permissionRequested(
                targetItemID: targetItemID,
                startedAt: date(fromFlexibleTimestamp: rawStartedAt)
            )
        )
    }

    private func decodeAutomaticReview(
        _ value: [String: Any],
        sessionID: String,
        turnID: String?,
        source: CodexApprovalObservation.Source
    ) -> CodexApprovalObservation? {
        guard
            value["type"] as? String == "automaticApprovalReview",
            let rawStatus = value["status"] as? String,
            let rawStartedAt = number(value["startedAtMs"])
        else {
            return nil
        }

        return CodexApprovalObservation(
            sessionID: sessionID,
            turnID: turnID,
            source: source,
            kind: .automaticReview(
                targetItemID: value["targetItemId"] as? String,
                status: CodexAutomaticApprovalStatus(rawValue: rawStatus),
                startedAt: Date(timeIntervalSince1970: rawStartedAt / 1_000)
            )
        )
    }

    private func waitingOnApproval(in value: Any?) -> Bool {
        guard let status = value as? [String: Any] else { return false }
        return (status["activeFlags"] as? [String] ?? []).contains("waitingOnApproval")
    }

    private func targetItemID(fromHookRunID runID: String) -> String? {
        guard let candidate = runID.split(separator: ":").last else { return nil }
        let targetItemID = String(candidate)
        return targetItemID.hasPrefix("call_") || targetItemID.hasPrefix("exec-")
            ? targetItemID
            : nil
    }

    private func entityKey(in path: [String]) -> String? {
        guard
            let index = path.firstIndex(of: "entitiesByKey"),
            path.indices.contains(index + 1)
        else {
            return nil
        }
        return path[index + 1]
    }

    private func pathComponents(_ value: Any?) -> [String] {
        if let components = value as? [Any] {
            return components.map { String(describing: $0) }
        }
        if let path = value as? String {
            return path.split(separator: "/").map(String.init)
        }
        return []
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private func date(fromFlexibleTimestamp value: Double) -> Date {
        Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1_000 : value)
    }
}

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
        let turns = turnIDsBySessionAndEntity
        let waiting = waitingOnApprovalBySession
        let active = activeTurnIDBySession
        do { return try decodeValidated(root) } catch {
            turnIDsBySessionAndEntity = turns
            waitingOnApprovalBySession = waiting
            activeTurnIDBySession = active
            throw error
        }
    }

    private func decodeValidated(_ root: [String: Any]) throws -> [CodexApprovalObservation] {
        guard
            root["type"] as? String == "broadcast",
            root["method"] as? String == "thread-stream-state-changed"
        else {
            throw CodexApprovalStateDecodeError.invalidMessage
        }
        let rawVersion = root["version"] as? NSNumber
        let version = rawVersion?.intValue
        guard version == 11, rawVersion?.doubleValue == 11 else {
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
            _ = try waitingOnApproval(in: state["threadRuntimeStatus"])
            try validateContent(state)
            return try decodeSnapshot(state, sessionID: sessionID)
        case "patches":
            guard let patches = change["patches"] as? [[String: Any]] else {
                throw CodexApprovalStateDecodeError.invalidMessage
            }
            for patch in patches {
                guard let op = patch["op"] as? String, ["add", "replace", "remove"].contains(op),
                    !pathComponents(patch["path"]).isEmpty else {
                    throw CodexApprovalStateDecodeError.invalidMessage
                }
                if let value = patch["value"] { try validateContent(value) }
            }
            return try decodePatches(patches, sessionID: sessionID)
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
    ) throws -> [CodexApprovalObservation] {
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

                if turn["status"] as? String == "inProgress" {
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
        }

        turnIDsBySessionAndEntity[sessionID] = turnIDsByEntity
        if let latestActiveTurn {
            activeTurnIDBySession[sessionID] = latestActiveTurn.id
        } else {
            activeTurnIDBySession.removeValue(forKey: sessionID)
        }

        let waiting = try waitingOnApproval(in: state["threadRuntimeStatus"])
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
    ) throws -> [CodexApprovalObservation] {
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
                    waiting = try waitingOnApproval(in: dictionary)
                } else if let flags = value as? [String] {
                    waiting = flags.contains("waitingOnApproval")
                } else if value as? String == "waitingOnApproval" {
                    waiting = operation != "remove"
                } else {
                    // Removing an indexed flag without its previous value is ambiguous.
                    throw CodexApprovalStateDecodeError.invalidMessage
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

    private func waitingOnApproval(in value: Any?) throws -> Bool {
        guard let status = value as? [String: Any],
            let flags = status["activeFlags"] as? [String] else {
            throw CodexApprovalStateDecodeError.invalidMessage
        }
        return flags.contains("waitingOnApproval")
    }

    private func validateContent(_ value: Any) throws {
        if let dictionary = value as? [String: Any] {
            if (dictionary["eventName"] as? String)?.lowercased().filter(\.isLetter) == "permissionrequest" {
                guard let id = dictionary["id"] as? String, targetItemID(fromHookRunID: id) != nil,
                    number(dictionary["startedAt"]) != nil else {
                    throw CodexApprovalStateDecodeError.invalidMessage
                }
            }
            if dictionary["type"] as? String == "automaticApprovalReview" {
                guard dictionary["status"] is String,
                    number(dictionary["startedAtMs"]) != nil else {
                    throw CodexApprovalStateDecodeError.invalidMessage
                }
            }
            if let flags = dictionary["activeFlags"], !(flags is [String]) {
                throw CodexApprovalStateDecodeError.invalidMessage
            }
            // Only traverse known structural fields; never inspect free text or tool arguments.
            for key in ["turnHistory", "history", "entitiesByKey", "items", "hookRuns", "run"] {
                if let child = dictionary[key] {
                    if key == "entitiesByKey", let entities = child as? [String: Any] {
                        for entity in entities.values { try validateContent(entity) }
                    } else { try validateContent(child) }
                }
            }
        } else if let array = value as? [Any] {
            for child in array { try validateContent(child) }
        }
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

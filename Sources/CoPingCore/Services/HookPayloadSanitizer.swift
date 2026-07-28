import Foundation

public enum HookPayloadError: Error, Equatable {
    case inputTooLarge
    case invalidJSON
    case unsupportedEvent
    case missingSessionID
}

public enum HookPayloadSanitizer {
    public static let maximumInputBytes = 1_048_576

    public static func sanitize(_ data: Data, now: Date = Date()) throws -> CodexEvent {
        guard data.count <= maximumInputBytes else {
            throw HookPayloadError.inputTooLarge
        }
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw HookPayloadError.invalidJSON
        }
        guard let sessionID = object["session_id"] as? String, !sessionID.isEmpty else {
            throw HookPayloadError.missingSessionID
        }
        guard
            let rawName = object["hook_event_name"] as? String,
            let type = eventType(rawName: rawName, object: object)
        else {
            throw HookPayloadError.unsupportedEvent
        }

        let turnID = object["turn_id"] as? String
        let cwd = object["cwd"] as? String ?? ""
        let projectName = URL(fileURLWithPath: cwd).lastPathComponent.nonEmpty ?? "Codex"

        return CodexEvent(
            type: type,
            sessionID: sessionID,
            turnID: turnID,
            eventID: type == .permissionRequested ? UUID().uuidString : nil,
            projectName: projectName,
            timestamp: now
        )
    }

    private static func eventType(
        rawName: String,
        object: [String: Any]
    ) -> CodexEvent.EventType? {
        switch rawName {
        case "SessionStart":
            return .sessionStarted
        case "Stop":
            return .completed
        case "PermissionRequest":
            return .permissionRequested
        case "PreToolUse":
            guard object["tool_name"] as? String == "request_user_input" else {
                return nil
            }
            return .questionRequested
        default:
            return nil
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

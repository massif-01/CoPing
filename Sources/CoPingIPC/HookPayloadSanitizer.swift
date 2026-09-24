import Foundation
import CoreFoundation

public enum HookPayloadError: Error, Equatable {
    case inputTooLarge
    case invalidJSON
    case unsupportedEvent
    case missingSessionID
}

public enum HookPayloadSanitizer {
    public static let maximumInputBytes = 1_048_576

    public static func sanitize(_ data: Data, now: Date = Date(), sourceID: String? = nil) throws -> CodexEvent {
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

        let turnID = (object["turn_id"] as? String)?.nonEmpty
        let cwd = object["cwd"] as? String ?? ""
        let projectName = URL(fileURLWithPath: cwd).lastPathComponent.nonEmpty ?? "Codex"

        let tool = object["tool_name"] as? String
        let callID = (object["tool_use_id"] as? String)?.nonEmpty
        var phase: CodexEvent.Phase = .requested
        let mode: CodexEvent.QuestionMode? = type == .questionRequested
            ? (tool == "request_user_input_async" ? .async : .unknown) : nil
        if rawName == "Stop" { phase = .stopCandidate }
        if rawName == "PostToolUse" {
            let response = responseObject(object["tool_response"])
            if mode == .async {
                guard let accepted = response?["accepted"] as? NSNumber,
                    CFGetTypeID(accepted) == CFBooleanGetTypeID(), accepted.boolValue else {
                    throw HookPayloadError.unsupportedEvent
                }
                phase = .accepted
            } else {
                // rust-v0.156.1 returns a structured response after the wait ends.
                // Empty answers can mean cancellation/automatic resolution, not a human answer.
                guard response?["answers"] is [String: Any] else {
                    throw HookPayloadError.unsupportedEvent
                }
                phase = .resolved
            }
        }
        return CodexEvent(
            type: type,
            sessionID: sessionID,
            turnID: turnID,
            eventID: callID == nil ? UUID().uuidString : nil,
            callID: callID,
            phase: phase,
            questionMode: mode,
            sourceID: sourceID,
            projectName: projectName,
            timestamp: now
        )
    }

    private static func responseObject(_ value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] { return object }
        guard let text = value as? String, let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
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
        case "PreToolUse", "PostToolUse":
            guard let tool = object["tool_name"] as? String,
                ["request_user_input", "request_user_input_async"].contains(tool) else {
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

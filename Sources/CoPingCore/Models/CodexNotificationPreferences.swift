public enum ApprovalNotificationMode: String, CaseIterable, Codable, Sendable {
    case all
    case actionNeeded
    case none

    public static func migrated(
        storedRawValue: String?,
        legacyIgnorePermissionNotifications: Bool?
    ) -> Self {
        if let storedRawValue, let stored = Self(rawValue: storedRawValue) {
            return stored
        }
        return legacyIgnorePermissionNotifications == true ? .none : .all
    }
}

public enum ApprovalNotificationRequirement: Equatable, Sendable {
    case handledAutomatically
    case requiresUserAction
    case unknown
}

public struct CodexNotificationPreferences: Equatable, Sendable {
    public let approvalNotificationMode: ApprovalNotificationMode

    public init(approvalNotificationMode: ApprovalNotificationMode = .all) {
        self.approvalNotificationMode = approvalNotificationMode
    }

    public func allows(
        _ eventType: CodexEvent.EventType,
        approvalRequirement: ApprovalNotificationRequirement = .unknown
    ) -> Bool {
        guard eventType == .permissionRequested else { return true }

        switch approvalNotificationMode {
        case .all:
            return true
        case .actionNeeded:
            return approvalRequirement != .handledAutomatically
        case .none:
            return false
        }
    }
}

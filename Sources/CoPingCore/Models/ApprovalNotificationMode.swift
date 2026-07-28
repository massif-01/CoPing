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

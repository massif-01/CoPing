public struct CodexNotificationPreferences: Equatable, Sendable {
    public let ignorePermissionNotifications: Bool

    public init(ignorePermissionNotifications: Bool = false) {
        self.ignorePermissionNotifications = ignorePermissionNotifications
    }

    public func allows(_ eventType: CodexEvent.EventType) -> Bool {
        eventType != .permissionRequested || !ignorePermissionNotifications
    }
}

import Foundation

public enum CoPingBrand {
    public static let barkIconURL = URL(
        string: "https://raw.githubusercontent.com/massif-01/CoPing/main/assets/icon/CoPing-bark-avatar-v2.png"
    )!
}

public struct PushNotification: Codable, Equatable, Sendable {
    public let title: String
    public let body: String
    public let group: String
    public let level: String
    public let icon: URL?

    public init(
        title: String,
        body: String,
        group: String = "CoPing",
        level: String = "active",
        icon: URL? = CoPingBrand.barkIconURL
    ) {
        self.title = title
        self.body = body
        self.group = group
        self.level = level
        self.icon = icon
    }
}

public protocol PushProvider: Sendable {
    func send(_ notification: PushNotification) async throws
}

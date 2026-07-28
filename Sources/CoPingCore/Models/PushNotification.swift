import Foundation

public enum CoPingBrand {
    public static let barkIconURL = URL(
        string: "https://raw.githubusercontent.com/massif-01/CoPing/main/assets/icon/CoPing-bark-avatar-v2.png"
    )!
}

public enum PushUrgency: String, Codable, Equatable, Sendable {
    case normal
    case high
}

public struct PushNotification: Codable, Equatable, Sendable {
    public let title: String
    public let body: String
    public let group: String
    public let level: String
    public let icon: URL?
    public let urgency: PushUrgency
    public let sequenceID: String

    public init(
        title: String,
        body: String,
        group: String = "CoPing",
        level: String = "active",
        icon: URL? = CoPingBrand.barkIconURL,
        urgency: PushUrgency = .normal,
        sequenceID: String = UUID().uuidString.lowercased()
    ) {
        self.title = title
        self.body = body
        self.group = group
        self.level = level
        self.icon = icon
        self.urgency = urgency
        self.sequenceID = sequenceID
    }
}

public protocol PushProvider: Sendable {
    func send(_ notification: PushNotification) async throws
}

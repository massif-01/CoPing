import Foundation

public enum NtfyConfigurationError: LocalizedError, Equatable {
    case invalidTopic

    public var errorDescription: String? {
        switch self {
        case .invalidTopic:
            AppText.invalidNtfyTopic
        }
    }
}

public struct NtfyConfiguration: Codable, Equatable, Sendable {
    public static let serverURL = URL(string: "https://ntfy.sh")!

    public let topic: String

    public init(topicInput: String) throws {
        guard
            topicInput.count == 33,
            topicInput.range(
                of: #"^coping-[a-z2-7]{26}$"#,
                options: .regularExpression
            ) != nil
        else {
            throw NtfyConfigurationError.invalidTopic
        }
        topic = topicInput
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(topicInput: container.decode(String.self, forKey: .topic))
    }

    private enum CodingKeys: String, CodingKey {
        case topic
    }
}

public enum NtfyTopicGenerator {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")

    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        let randomPart = String(
            (0..<26).map { _ in
                alphabet.randomElement(using: &generator)!
            }
        )
        return "coping-\(randomPart)"
    }
}

public enum NtfySettingsError: LocalizedError, Equatable {
    case topicNotSaved

    public var errorDescription: String? {
        switch self {
        case .topicNotSaved:
            AppText.ntfyTopicNotSaved
        }
    }
}

/// Owns the NTFY configuration state that must stay consistent across the UI,
/// UserDefaults, and the protected on-disk topic.
public struct NtfySettingsCoordinator {
    public static let enabledDefaultsKey = "ntfyEnabled"

    public private(set) var topic: String
    public private(set) var isEnabled: Bool
    public private(set) var configurationReadFailed: Bool

    private let configurationStore: NtfyConfigurationStore
    private let defaults: UserDefaults
    private var savedConfiguration: NtfyConfiguration?

    public init(
        configurationStore: NtfyConfigurationStore = NtfyConfigurationStore(),
        defaults: UserDefaults = .standard
    ) {
        self.configurationStore = configurationStore
        self.defaults = defaults

        let configuration: NtfyConfiguration?
        do {
            configuration = try configurationStore.read()
            configurationReadFailed = false
        } catch {
            configuration = nil
            configurationReadFailed = true
        }

        savedConfiguration = configuration
        topic = configuration?.topic ?? NtfyTopicGenerator.generate()

        let requestedEnabled =
            defaults.object(forKey: Self.enabledDefaultsKey) as? Bool
            ?? false
        isEnabled = requestedEnabled && configuration != nil

        if requestedEnabled && !isEnabled {
            defaults.set(false, forKey: Self.enabledDefaultsKey)
        }
    }

    public var hasCurrentConfiguration: Bool {
        savedConfiguration?.topic == topic
    }

    public var deliveryConfiguration: NtfyConfiguration? {
        hasCurrentConfiguration ? savedConfiguration : nil
    }

    @discardableResult
    public mutating func save() throws -> NtfyConfiguration {
        let configuration = try NtfyConfiguration(topicInput: topic)
        try configurationStore.save(configuration)
        savedConfiguration = configuration
        topic = configuration.topic
        return configuration
    }

    public mutating func setEnabled(_ enabled: Bool) throws {
        guard !enabled || hasCurrentConfiguration else {
            throw NtfySettingsError.topicNotSaved
        }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
    }

    public mutating func regenerateTopic() {
        var nextTopic = NtfyTopicGenerator.generate()
        while nextTopic == topic {
            nextTopic = NtfyTopicGenerator.generate()
        }
        topic = nextTopic
        isEnabled = false
        defaults.set(false, forKey: Self.enabledDefaultsKey)
    }
}

public struct NtfyConfigurationStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL = CoPingPaths.ntfyConfigurationFile(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func read() throws -> NtfyConfiguration? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(NtfyConfiguration.self, from: data)
    }

    public func save(_ configuration: NtfyConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directory.path
        )

        let data = try JSONEncoder().encode(configuration)
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
    }
}

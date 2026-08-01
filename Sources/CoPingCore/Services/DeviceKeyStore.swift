import Foundation

public enum StoredBarkConfiguration: Equatable, Sendable {
    case legacyDeviceKey(String)
    case destinations([BarkDestination])
}

public struct DeviceKeyStore {
    public static let currentVersion = 2

    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL = CoPingPaths.configurationFile(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func read() throws -> StoredBarkConfiguration? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let probe = try decoder.decode(StoredConfigurationProbe.self, from: data)

        if let version = probe.version {
            guard version == Self.currentVersion else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: [],
                        debugDescription: "Unsupported Bark configuration version \(version)"
                    )
                )
            }
            let stored = try decoder.decode(StoredConfiguration.self, from: data)
            guard
                !stored.destinations.isEmpty,
                Set(stored.destinations.map(\.id)).count == stored.destinations.count
            else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Invalid Bark destinations")
                )
            }
            return .destinations(stored.destinations)
        }

        guard let deviceKey = probe.deviceKey else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unrecognized Bark configuration")
            )
        }
        return .legacyDeviceKey(deviceKey)
    }

    public func save(_ destinations: [BarkDestination]) throws {
        guard
            !destinations.isEmpty,
            Set(destinations.map(\.id)).count == destinations.count
        else {
            throw BarkSettingsError.invalidFields
        }

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

        let data = try JSONEncoder().encode(
            StoredConfiguration(
                version: Self.currentVersion,
                deviceKey: destinations[0].deviceKey,
                destinations: destinations
            )
        )
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
    }
}

public struct BarkDestinationDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var addressInput: String

    public init(id: UUID = UUID(), addressInput: String = "") {
        self.id = id
        self.addressInput = addressInput
    }
}

public enum BarkSettingsError: LocalizedError, Equatable {
    case invalidFields
    case configurationNotSaved

    public var errorDescription: String? {
        switch self {
        case .invalidFields:
            AppText.invalidBarkSettings
        case .configurationNotSaved:
            AppText.barkSettingsNotSaved
        }
    }
}

/// Owns Bark drafts, protected persistence, legacy migration, and the last
/// configuration that formal notifications are allowed to use.
public struct BarkSettingsCoordinator {
    /// Canonical server used when a destination row contains only a Device Key.
    public static let baseURLDefaultsKey = "barkDefaultBaseURL"
    /// First destination server projected for released single-destination builds.
    public static let legacyBaseURLDefaultsKey = "barkBaseURL"
    public static let enabledDefaultsKey = "barkEnabled"
    public static let defaultBaseURLString = "https://api.day.app"

    public private(set) var baseURLString: String
    public private(set) var destinationDrafts: [BarkDestinationDraft]
    public private(set) var validationErrors: [UUID: String]
    public private(set) var baseURLValidationError: String?
    public private(set) var isEnabled: Bool
    public private(set) var configurationReadFailed: Bool
    public private(set) var configurationMigrationFailed: Bool

    private let configurationStore: DeviceKeyStore
    private let defaults: UserDefaults
    private var savedDestinations: [BarkDestination]

    public init(
        configurationStore: DeviceKeyStore = DeviceKeyStore(),
        defaults: UserDefaults = .standard
    ) {
        let baseURLString =
            defaults.string(forKey: Self.baseURLDefaultsKey)
            ?? defaults.string(forKey: Self.legacyBaseURLDefaultsKey)
            ?? Self.defaultBaseURLString
        var loadedDestinations: [BarkDestination] = []
        var loadedDrafts: [BarkDestinationDraft] = []
        var loadedValidationErrors: [UUID: String] = [:]
        var readFailed = false
        var migrationFailed = false

        do {
            switch try configurationStore.read() {
            case .destinations(let destinations):
                loadedDestinations = destinations
            case .legacyDeviceKey(let deviceKey):
                if !deviceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let id = UUID()
                    do {
                        let destination = try BarkDestination(
                            id: id,
                            defaultBaseURLString: baseURLString,
                            addressInput: deviceKey
                        )
                        loadedDestinations = [destination]
                        do {
                            try configurationStore.save([destination])
                        } catch {
                            migrationFailed = true
                        }
                    } catch {
                        loadedDrafts = [BarkDestinationDraft(id: id, addressInput: deviceKey)]
                        loadedValidationErrors[id] = error.localizedDescription
                    }
                }
            case nil:
                break
            }
        } catch {
            readFailed = true
        }

        if loadedDrafts.isEmpty {
            loadedDrafts = loadedDestinations.map {
                BarkDestinationDraft(
                    id: $0.id,
                    addressInput: $0.addressInput(defaultBaseURLString: baseURLString)
                )
            }
        }
        if loadedDrafts.isEmpty {
            loadedDrafts = [BarkDestinationDraft()]
        }

        let requestedEnabled =
            defaults.object(forKey: Self.enabledDefaultsKey) as? Bool
            ?? !loadedDestinations.isEmpty
        let enabled = requestedEnabled && !loadedDestinations.isEmpty

        self.configurationStore = configurationStore
        self.defaults = defaults
        self.baseURLString = baseURLString
        destinationDrafts = loadedDrafts
        validationErrors = loadedValidationErrors
        baseURLValidationError = nil
        isEnabled = enabled
        configurationReadFailed = readFailed
        configurationMigrationFailed = migrationFailed
        savedDestinations = loadedDestinations

        if requestedEnabled && !enabled {
            defaults.set(false, forKey: Self.enabledDefaultsKey)
        }
        if
            !loadedDestinations.isEmpty,
            defaults.object(forKey: Self.baseURLDefaultsKey) == nil
        {
            defaults.set(baseURLString, forKey: Self.baseURLDefaultsKey)
        }
    }

    public var hasCurrentConfiguration: Bool {
        let validation = Self.validate(
            baseURLString: baseURLString,
            drafts: destinationDrafts
        )
        return validation.destinations == savedDestinations
            && validation.baseURLFailure == nil
            && validation.rowFailures.isEmpty
    }

    public var deliveryDestinations: [BarkDestination] {
        savedDestinations
    }

    public mutating func setBaseURLString(_ value: String) {
        baseURLString = value
        baseURLValidationError = nil
        validationErrors.removeAll()
    }

    public mutating func setAddressInput(_ value: String, for id: UUID) {
        guard let index = destinationDrafts.firstIndex(where: { $0.id == id }) else { return }
        destinationDrafts[index].addressInput = value
        validationErrors.removeAll()
    }

    @discardableResult
    public mutating func addDestination() -> UUID {
        let draft = BarkDestinationDraft()
        destinationDrafts.append(draft)
        return draft.id
    }

    public mutating func removeDestination(id: UUID) {
        guard destinationDrafts.count > 1 else { return }
        destinationDrafts.removeAll { $0.id == id }
        validationErrors.removeAll()
    }

    @discardableResult
    public mutating func save() throws -> [BarkDestination] {
        let validation = Self.validate(
            baseURLString: baseURLString,
            drafts: destinationDrafts
        )
        baseURLValidationError = validation.baseURLFailure
        validationErrors = validation.rowFailures
        guard
            let destinations = validation.destinations,
            let normalizedBaseURLString = validation.normalizedBaseURLString
        else {
            throw BarkSettingsError.invalidFields
        }

        try configurationStore.save(destinations)
        savedDestinations = destinations
        baseURLString = normalizedBaseURLString
        defaults.set(normalizedBaseURLString, forKey: Self.baseURLDefaultsKey)
        defaults.set(
            destinations[0].baseURL.absoluteString,
            forKey: Self.legacyBaseURLDefaultsKey
        )
        destinationDrafts = destinations.map {
            BarkDestinationDraft(
                id: $0.id,
                addressInput: $0.addressInput(defaultBaseURLString: normalizedBaseURLString)
            )
        }
        return destinations
    }

    public mutating func setEnabled(_ enabled: Bool) throws {
        guard !enabled || hasCurrentConfiguration else {
            throw BarkSettingsError.configurationNotSaved
        }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
    }

    private static func validate(
        baseURLString: String,
        drafts: [BarkDestinationDraft]
    ) -> ValidationResult {
        let rawBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: rawBaseURL) else {
            return ValidationResult(
                destinations: nil,
                normalizedBaseURLString: nil,
                baseURLFailure: AppText.invalidBarkBaseURL,
                rowFailures: [:]
            )
        }
        do {
            try BarkClient.validateBaseURL(baseURL)
        } catch {
            return ValidationResult(
                destinations: nil,
                normalizedBaseURLString: nil,
                baseURLFailure: error.localizedDescription,
                rowFailures: [:]
            )
        }

        var destinations: [BarkDestination] = []
        var rowFailures: [UUID: String] = [:]
        var firstIDByDeduplicationKey: [String: UUID] = [:]

        for draft in drafts {
            do {
                let destination = try BarkDestination(
                    id: draft.id,
                    defaultBaseURLString: rawBaseURL,
                    addressInput: draft.addressInput
                )
                if let firstID = firstIDByDeduplicationKey[destination.deduplicationKey] {
                    rowFailures[firstID] = AppText.duplicateBarkPushAddress
                    rowFailures[draft.id] = AppText.duplicateBarkPushAddress
                } else {
                    firstIDByDeduplicationKey[destination.deduplicationKey] = draft.id
                }
                destinations.append(destination)
            } catch {
                rowFailures[draft.id] = error.localizedDescription
            }
        }

        return ValidationResult(
            destinations: rowFailures.isEmpty ? destinations : nil,
            normalizedBaseURLString: baseURL.absoluteString,
            baseURLFailure: nil,
            rowFailures: rowFailures
        )
    }

    private struct ValidationResult {
        let destinations: [BarkDestination]?
        let normalizedBaseURLString: String?
        let baseURLFailure: String?
        let rowFailures: [UUID: String]
    }
}

private struct StoredConfigurationProbe: Decodable {
    let version: Int?
    let deviceKey: String?
}

private struct StoredConfiguration: Codable {
    let version: Int
    /// Projects the first destination for released single-destination builds
    /// that share this configuration file.
    let deviceKey: String
    let destinations: [BarkDestination]
}

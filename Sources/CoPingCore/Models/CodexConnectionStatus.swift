import CoPingIPC
import Foundation

public enum CodexConnectionStatus: Equatable, Sendable {
    case disconnected
    case awaitingVerification
    case connected
    case error

    public var label: String {
        switch self {
        case .disconnected: AppText.disconnected
        case .awaitingVerification: AppText.awaitingVerification
        case .connected: AppText.connected
        case .error: AppText.configurationError
        }
    }

    @discardableResult
    public mutating func verify(with event: CodexEvent) -> Bool {
        guard self == .awaitingVerification, event.verifiesConnection else {
            return false
        }
        self = .connected
        return true
    }
}

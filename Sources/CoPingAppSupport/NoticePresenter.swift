import Foundation

@MainActor
public final class NoticePresenter {
    public struct Notice: Equatable, Identifiable {
        public enum Kind {
            case success
            case information
            case error
        }

        public let id: UUID
        public let message: String
        public let kind: Kind

        public init(
            id: UUID = UUID(),
            message: String,
            kind: Kind
        ) {
            self.id = id
            self.message = message
            self.kind = kind
        }
    }

    public private(set) var current: Notice?

    private let autoDismissDelay: Duration
    private let onChange: @MainActor (Notice?) -> Void
    private var dismissTask: Task<Void, Never>?

    public init(
        autoDismissDelay: Duration = .seconds(3),
        onChange: @escaping @MainActor (Notice?) -> Void = { _ in }
    ) {
        self.autoDismissDelay = autoDismissDelay
        self.onChange = onChange
    }

    @discardableResult
    public func show(_ message: String, kind: Notice.Kind) -> Notice {
        dismissTask?.cancel()

        let next = Notice(message: message, kind: kind)
        current = next
        onChange(next)

        guard kind != .error else {
            dismissTask = nil
            return next
        }

        dismissTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: autoDismissDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            dismiss(id: next.id)
        }
        return next
    }

    public func dismiss(id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        onChange(nil)
    }
}

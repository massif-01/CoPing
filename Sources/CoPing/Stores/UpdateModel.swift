import CoPingCore
import Foundation

@MainActor
final class UpdateModel: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case noPublishedRelease
        case upToDate(AppRelease)
        case updateAvailable(AppRelease)
        case downloading(AppRelease)
        case downloaded(AppRelease, URL)
        case failed(String, AppRelease?)
    }

    @Published private(set) var state: State = .idle

    private let releaseClient: GitHubReleaseClient
    private let downloader: ReleaseDownloader
    private var task: Task<Void, Never>?

    init(
        releaseClient: GitHubReleaseClient = GitHubReleaseClient(),
        downloader: ReleaseDownloader = ReleaseDownloader()
    ) {
        self.releaseClient = releaseClient
        self.downloader = downloader
    }

    func checkForUpdates() {
        task?.cancel()
        state = .checking
        task = Task {
            do {
                guard let currentVersion = SemanticVersion(rawValue: AppVersion.current) else {
                    state = .failed(AppText.invalidCurrentVersion, nil)
                    return
                }
                let release = try await releaseClient.latestRelease()
                try Task.checkCancellation()
                state = release.version > currentVersion
                    ? .updateAvailable(release)
                    : .upToDate(release)
            } catch GitHubReleaseError.noPublishedRelease {
                state = .noPublishedRelease
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription, nil)
            }
        }
    }

    func download(_ release: AppRelease, to destinationURL: URL) {
        task?.cancel()
        state = .downloading(release)
        task = Task {
            do {
                try await downloader.download(release, to: destinationURL)
                try Task.checkCancellation()
                state = .downloaded(release, destinationURL)
            } catch is CancellationError {
                state = .updateAvailable(release)
            } catch {
                state = .failed(error.localizedDescription, release)
            }
        }
    }

    func cancelDownload() {
        guard case .downloading(let release) = state else { return }
        task?.cancel()
        state = .updateAvailable(release)
    }
}

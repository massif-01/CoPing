import AppKit
import CoPingCore
import SwiftUI

struct VersionSettingsView: View {
    @ObservedObject var updateModel: UpdateModel

    var body: some View {
        SettingsPage(
            AppText.versionTab,
            subtitle: AppText.versionSettingsDescription,
            systemImage: "arrow.triangle.2.circlepath",
            tint: .blue
        ) {
            SettingsCard {
                SettingsRow(
                    systemImage: "info.circle.fill",
                    tint: .blue,
                    title: AppText.currentVersionLabel
                ) {
                    Text(AppVersion.current)
                        .foregroundStyle(.secondary)
                }

                SettingsCardDivider()

                SettingsRow(
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    title: AppText.supportedEventsLabel
                ) {
                    Text(AppText.supportedEventsValue)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                SettingsCardDivider()

                SettingsRow(
                    systemImage: "xmark.circle.fill",
                    tint: .orange,
                    title: AppText.executionFailureLabel
                ) {
                    Text(AppText.notSupportedInVersion(AppVersion.current))
                        .foregroundStyle(.secondary)
                }
            }

            updateCard
        }
    }

    @ViewBuilder
    private var updateCard: some View {
        SettingsCard {
            switch updateModel.state {
            case .idle:
                updateRow(
                    icon: "arrow.clockwise",
                    tint: .blue,
                    title: AppText.softwareUpdate,
                    subtitle: AppText.checkForUpdatesHelp
                ) {
                    checkButton
                }
            case .checking:
                updateRow(
                    icon: "arrow.clockwise",
                    tint: .blue,
                    title: AppText.checkingForUpdates,
                    subtitle: nil
                ) {
                    ProgressView()
                        .controlSize(.small)
                }
            case .noPublishedRelease:
                updateRow(
                    icon: "shippingbox",
                    tint: .secondary,
                    title: AppText.noPublishedReleaseTitle,
                    subtitle: AppText.noPublishedRelease
                ) {
                    checkButton
                }
            case .upToDate(let release):
                updateRow(
                    icon: "checkmark.seal.fill",
                    tint: .green,
                    title: AppText.upToDate,
                    subtitle: AppText.latestVersionValue(release.version.description)
                ) {
                    checkButton
                }
            case .updateAvailable(let release):
                updateAvailableRows(release)
            case .downloading(let release):
                updateRow(
                    icon: "arrow.down.circle.fill",
                    tint: .blue,
                    title: AppText.downloadingVersion(release.version.description),
                    subtitle: release.archive.name
                ) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Button(AppText.cancelDownload) {
                            updateModel.cancelDownload()
                        }
                        .copingSecondaryButtonStyle()
                    }
                }
            case .downloaded(let release, let fileURL):
                updateRow(
                    icon: "checkmark.circle.fill",
                    tint: .green,
                    title: AppText.downloadComplete,
                    subtitle: AppText.downloadedVersion(release.version.description)
                ) {
                    Button(AppText.showInFinder) {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                    .copingSecondaryButtonStyle()
                }
            case .failed(let message, let release):
                updateRow(
                    icon: "exclamationmark.triangle.fill",
                    tint: .red,
                    title: AppText.updateFailed,
                    subtitle: message
                ) {
                    if let release {
                        Button(AppText.retryDownload) {
                            chooseDestinationAndDownload(release)
                        }
                        .copingPrimaryButtonStyle()
                    } else {
                        checkButton
                    }
                }
            }
        }
    }

    private var checkButton: some View {
        Button(AppText.checkForUpdates) {
            updateModel.checkForUpdates()
        }
        .copingPrimaryButtonStyle()
    }

    @ViewBuilder
    private func updateAvailableRows(_ release: AppRelease) -> some View {
        updateRow(
            icon: "sparkles",
            tint: .orange,
            title: AppText.updateAvailable,
            subtitle: AppText.latestVersionValue(release.version.description)
        ) {
            Text(release.archive.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        SettingsCardDivider()

        updateRow(
            icon: "arrow.down.circle.fill",
            tint: .blue,
            title: AppText.downloadUpdate,
            subtitle: release.archive.name
        ) {
            Button(AppText.download) {
                chooseDestinationAndDownload(release)
            }
            .copingPrimaryButtonStyle()
        }
    }

    private func updateRow<Control: View>(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String?,
        @ViewBuilder control: () -> Control
    ) -> some View {
        SettingsRow(
            systemImage: icon,
            tint: tint,
            title: title,
            subtitle: subtitle,
            control: control
        )
    }

    private func chooseDestinationAndDownload(_ release: AppRelease) {
        guard
            let destination = ReleaseSavePanel.chooseDestination(
                suggestedName: release.archive.name
            )
        else {
            return
        }
        updateModel.download(release, to: destination)
    }
}

private extension ReleaseAsset {
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

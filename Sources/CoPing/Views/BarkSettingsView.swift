import CoPingCore
import SwiftUI

struct BarkSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            AppText.serviceSection,
                            systemImage: "network"
                        )
                        .font(.headline)

                        TextField(
                            AppText.httpsServerAddress,
                            text: $model.baseURLString
                        )
                        .textFieldStyle(.roundedBorder)

                        Text(AppText.barkServerHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            AppText.deviceSection,
                            systemImage: "iphone"
                        )
                        .font(.headline)

                        SecureField(
                            AppText.deviceKeyOrURL,
                            text: $model.deviceKey
                        )
                        .textFieldStyle(.roundedBorder)

                        Text(AppText.deviceKeyHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()

                    Button(AppText.save) {
                        model.saveBarkSettings()
                    }
                    .copingSecondaryButtonStyle()

                    Button(AppText.saveAndSendTest) {
                        model.sendTestNotification()
                    }
                    .copingPrimaryButtonStyle()
                    .disabled(model.isBusy)
                }
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }
}

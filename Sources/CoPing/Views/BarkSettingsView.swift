import CoPingCore
import SwiftUI

struct BarkSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage("Bark") {
            Form {
                Section(AppText.serviceSection) {
                    TextField(
                        AppText.httpsServerAddress,
                        text: $model.baseURLString
                    )

                    Text(AppText.barkServerHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(AppText.deviceSection) {
                    SecureField(
                        AppText.deviceKeyOrURL,
                        text: $model.deviceKey
                    )

                    Text(AppText.deviceKeyHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
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
                    .controlSize(.regular)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}

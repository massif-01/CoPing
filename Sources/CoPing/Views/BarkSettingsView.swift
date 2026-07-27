import CoPingCore
import SwiftUI

struct BarkSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage(
            "Bark",
            subtitle: AppText.barkSettingsDescription,
            systemImage: "iphone.radiowaves.left.and.right",
            imageResourceName: "BarkIcon",
            tint: .blue
        ) {
            SettingsCard {
                SettingsRow(
                    systemImage: "server.rack",
                    tint: .blue,
                    title: AppText.httpsServerAddress,
                    subtitle: AppText.barkServerHelp
                ) {
                    TextField(
                        "",
                        text: $model.baseURLString
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                }

                SettingsCardDivider()

                SettingsRow(
                    systemImage: "key.fill",
                    tint: .orange,
                    title: AppText.deviceKeyOrURL,
                    subtitle: AppText.deviceKeyHelp
                ) {
                    SecureField(
                        "",
                        text: $model.deviceKey
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                }
            }

            HStack {
                Spacer()

                Button(AppText.save) {
                    model.saveBarkSettings()
                }
                .copingSecondaryButtonStyle()

                Button {
                    model.sendTestNotification()
                } label: {
                    Text(AppText.saveAndSendTest)
                        .foregroundStyle(.white)
                }
                .copingPrimaryButtonStyle()
                .disabled(model.isBusy)
            }
            .controlSize(.regular)
            .padding(.horizontal, 4)
        }
    }
}

import CoPingCore
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage(
            AppText.generalTab,
            subtitle: AppText.generalSettingsDescription,
            systemImage: "gearshape.fill",
            tint: .secondary
        ) {
            SettingsCard {
                SettingsRow(
                    systemImage: "globe",
                    tint: .blue,
                    title: AppText.languagePickerLabel,
                    subtitle: AppText.languagePreferenceHelp
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.languagePreference },
                            set: { model.setLanguagePreference($0) }
                        )
                    ) {
                        Text(AppText.followSystemLanguage)
                            .tag(AppLanguagePreference.system)
                        Text(AppText.simplifiedChineseLanguage)
                            .tag(AppLanguagePreference.simplifiedChinese)
                        Text(AppText.englishLanguage)
                            .tag(AppLanguagePreference.english)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 245)
                }

                SettingsCardDivider()

                SettingsRow(
                    systemImage: "bell.fill",
                    tint: .red,
                    title: AppText.enableNotifications,
                    subtitle: AppText.notificationsDisabledHelp
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.notificationsEnabled },
                            set: { model.setNotificationsEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(AppText.enableNotifications)
                }

                SettingsCardDivider()

                SettingsRow(
                    systemImage: "power",
                    tint: .green,
                    title: AppText.launchAtLogin
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(AppText.launchAtLogin)
                }
            }

        }
    }
}

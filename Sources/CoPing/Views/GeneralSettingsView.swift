import CoPingCore
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage(AppText.generalTab) {
            Form {
                Section(AppText.languageSection) {
                    Picker(
                        AppText.languagePickerLabel,
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

                    Text(AppText.languagePreferenceHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(AppText.notificationsSection) {
                    Toggle(
                        AppText.enableNotifications,
                        isOn: Binding(
                            get: { model.notificationsEnabled },
                            set: { model.setNotificationsEnabled($0) }
                        )
                    )

                    Text(AppText.notificationsDisabledHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(AppText.startupSection) {
                    Toggle(
                        AppText.launchAtLogin,
                        isOn: Binding(
                            get: { model.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                }

                Section(AppText.appVersionLabel) {
                    LabeledContent(
                        AppText.currentVersionLabel,
                        value: AppVersion.current
                    )
                    LabeledContent(
                        AppText.supportedEventsLabel,
                        value: AppText.supportedEventsValue
                    )
                    LabeledContent(
                        AppText.executionFailureLabel,
                        value: AppText.notSupportedInVersion(AppVersion.current)
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}

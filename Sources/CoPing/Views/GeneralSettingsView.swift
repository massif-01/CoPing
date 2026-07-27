import CoPingCore
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        settingsHeader(AppText.languageSection, icon: "globe")

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
                }

                GlassCard {
                    VStack(spacing: 0) {
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)

                        Divider()
                            .padding(.vertical, 14)

                        Toggle(
                            AppText.launchAtLogin,
                            isOn: Binding(
                                get: { model.launchAtLogin },
                                set: { model.setLaunchAtLogin($0) }
                            )
                        )
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        settingsHeader(AppText.appVersionLabel, icon: "info.circle")

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
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private func settingsHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }
}

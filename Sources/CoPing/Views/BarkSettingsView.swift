import CoPingCore
import SwiftUI

struct BarkSettingsView: View {
    @ObservedObject var model: AppModel
    @FocusState private var focusedDestinationID: UUID?

    var body: some View {
        SettingsPage(
            "Bark",
            subtitle: AppText.barkSettingsDescription,
            systemImage: "iphone.radiowaves.left.and.right",
            tint: .blue
        ) {
            SettingsCard {
                SettingsRow(
                    systemImage: "bell.fill",
                    tint: .blue,
                    title: AppText.enableBark,
                    subtitle: AppText.enableBarkHelp
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.barkEnabled },
                            set: { model.setBarkEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(AppText.enableBark)
                }

                SettingsCardDivider()

                SettingsRow(
                    systemImage: "server.rack",
                    tint: .blue,
                    title: AppText.httpsServerAddress,
                    subtitle: AppText.barkServerHelp
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(
                            "",
                            text: Binding(
                                get: { model.baseURLString },
                                set: { model.setBarkBaseURLString($0) }
                            )
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)

                        if let error = model.barkBaseURLValidationError {
                            validationMessage(error)
                        }
                    }
                    .frame(width: 280, alignment: .leading)
                }

                SettingsCardDivider()

                ForEach(
                    Array(model.barkDestinationDrafts.enumerated()),
                    id: \.element.id
                ) { index, destination in
                    destinationRow(destination, index: index)

                    SettingsCardDivider()
                }

                addDestinationRow
            }

            HStack {
                Spacer()

                Button(AppText.save) {
                    model.saveBarkSettings()
                }
                .copingSecondaryButtonStyle()

                Button {
                    model.sendBarkTestNotification()
                } label: {
                    Text(AppText.saveAndTestAllBarkAddresses)
                        .foregroundStyle(.white)
                }
                .copingPrimaryButtonStyle()
                .disabled(model.isBusy)
            }
            .controlSize(.regular)
            .padding(.horizontal, 4)
        }
    }

    private func destinationRow(
        _ destination: BarkDestinationDraft,
        index: Int
    ) -> some View {
        SettingsRow(
            systemImage: "key.fill",
            tint: .orange,
            title: model.barkDestinationDrafts.count == 1
                ? AppText.deviceKeyOrURL
                : AppText.barkPushAddress(index + 1),
            subtitle: index == 0 ? AppText.deviceKeyHelp : nil
        ) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField(
                        "",
                        text: addressBinding(for: destination.id)
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedDestinationID, equals: destination.id)

                    if let error = model.barkValidationErrors[destination.id] {
                        validationMessage(error)
                    }
                }
                .frame(width: 244, alignment: .leading)

                if model.barkDestinationDrafts.count > 1 {
                    Button(role: .destructive) {
                        if focusedDestinationID == destination.id {
                            focusedDestinationID = nil
                        }
                        model.removeBarkDestination(id: destination.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 22)
                    .help(AppText.removeBarkPushAddress(index + 1))
                    .accessibilityLabel(AppText.removeBarkPushAddress(index + 1))
                } else {
                    Color.clear
                        .frame(width: 26, height: 22)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var addDestinationRow: some View {
        Button {
            let id = model.addBarkDestination()
            Task { @MainActor in
                await Task.yield()
                focusedDestinationID = id
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppText.addMoreBarkPushAddresses)
                        .foregroundStyle(.primary)

                    Text(AppText.addMoreBarkPushAddressesHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .foregroundStyle(.blue)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppText.addMoreBarkPushAddresses)
    }

    private func addressBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                model.barkDestinationDrafts.first(where: { $0.id == id })?.addressInput ?? ""
            },
            set: { model.setBarkAddressInput($0, for: id) }
        )
    }

    private func validationMessage(_ message: String) -> some View {
        Text(message)
            .font(.caption2)
            .foregroundStyle(Color(nsColor: .systemRed))
            .fixedSize(horizontal: false, vertical: true)
    }
}

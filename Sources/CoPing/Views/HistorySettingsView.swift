import AppKit
import CoPingCore
import SwiftUI

struct HistorySettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(AppText.historyTab)
                    .font(.title2.weight(.semibold))

                Spacer()

                Button(AppText.clearHistory, role: .destructive) {
                    model.clearHistory()
                }
                .copingSecondaryButtonStyle()
                .disabled(model.records.isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 12)

            if model.records.isEmpty {
                ContentUnavailableView(
                    AppText.noNotificationHistory,
                    systemImage: "bell.slash",
                    description: Text(AppText.historyPrivacyHelp)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.records) { record in
                    historyRow(record)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            Text(AppText.historyLimit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
        }
    }

    private func historyRow(_ record: DeliveryRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: record.outcome))
                .font(.body.weight(.semibold))
                .foregroundStyle(color(for: record.outcome))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(eventName(record.eventType)) · \(record.projectName)")

                if let detail = record.detail {
                    Text(AppText.localizedHistoryDetail(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(record.timestamp, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }

    private func eventName(_ type: CodexEvent.EventType) -> String {
        switch type {
        case .sessionStarted: AppText.connectionEvent
        case .completed: AppText.completionEvent
        case .permissionRequested: AppText.permissionEvent
        case .questionRequested: AppText.questionEvent
        }
    }

    private func icon(for outcome: DeliveryRecord.Outcome) -> String {
        switch outcome {
        case .sent: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .skipped: "minus.circle.fill"
        }
    }

    private func color(for outcome: DeliveryRecord.Outcome) -> Color {
        switch outcome {
        case .sent: Color(nsColor: .systemGreen)
        case .failed: Color(nsColor: .systemRed)
        case .skipped: .secondary
        }
    }
}

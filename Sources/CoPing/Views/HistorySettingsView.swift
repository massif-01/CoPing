import AppKit
import CoPingCore
import SwiftUI

struct HistorySettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage(
            AppText.historyTab,
            subtitle: AppText.historySettingsDescription,
            systemImage: "clock.arrow.circlepath",
            tint: .teal
        ) {
            HStack {
                Spacer()

                Button(AppText.clearHistory, role: .destructive) {
                    model.clearHistory()
                }
                .copingSecondaryButtonStyle()
                .disabled(model.records.isEmpty)
            }
            .padding(.horizontal, 4)

            if model.records.isEmpty {
                SettingsCard {
                    ContentUnavailableView(
                        AppText.noNotificationHistory,
                        systemImage: "bell.slash",
                        description: Text(AppText.historyPrivacyHelp)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                }
            } else {
                SettingsCard {
                    ForEach(Array(model.records.enumerated()), id: \.element.id) {
                        index,
                        record in
                        historyRow(record)

                        if index < model.records.count - 1 {
                            SettingsCardDivider()
                        }
                    }
                }
            }

            Text(AppText.historyLimit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private func historyRow(_ record: DeliveryRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: record.aggregateStatus))
                .font(.body.weight(.semibold))
                .foregroundStyle(color(for: record.aggregateStatus))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(eventName(record.eventType)) · \(record.projectName)")

                if let detail = deliveryDetail(record) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Text(record.timestamp, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func deliveryDetail(_ record: DeliveryRecord) -> String? {
        let attempts = record.effectiveAttempts
        guard !attempts.isEmpty else {
            return record.detail.map(AppText.localizedHistoryDetail)
        }
        return attempts.map { attempt in
            let status: String
            switch attempt.outcome {
            case .sent:
                status = AppText.deliverySent
            case .failed:
                status = AppText.deliveryFailed
            case .skipped:
                status = AppText.deliverySkipped
            }
            if let detail = attempt.detail {
                return "\(attempt.channel.displayName)：\(status) · \(AppText.localizedHistoryDetail(detail))"
            }
            return "\(attempt.channel.displayName)：\(status)"
        }
        .joined(separator: "   ")
    }

    private func eventName(_ type: CodexEvent.EventType) -> String {
        switch type {
        case .sessionStarted: AppText.connectionEvent
        case .completed: AppText.completionEvent
        case .permissionRequested: AppText.permissionEvent
        case .questionRequested: AppText.questionEvent
        }
    }

    private func icon(for status: DeliveryRecord.AggregateStatus) -> String {
        switch status {
        case .sent: "checkmark.circle.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .skipped: "minus.circle.fill"
        }
    }

    private func color(for status: DeliveryRecord.AggregateStatus) -> Color {
        switch status {
        case .sent: Color(nsColor: .systemGreen)
        case .partial: Color(nsColor: .systemOrange)
        case .failed: Color(nsColor: .systemRed)
        case .skipped: .secondary
        }
    }
}

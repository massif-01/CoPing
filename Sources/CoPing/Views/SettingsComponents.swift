import AppKit
import CoPingCore
import SwiftUI

struct SettingsPage<Content: View>: View {
    let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 12)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SettingsNoticeView: View {
    let notice: AppModel.Notice
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)

            Text(notice.message)
                .font(.callout)
                .lineLimit(2)

            if notice.kind == .error {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(AppText.dismiss)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(NoticeSurfaceModifier(tint: color))
    }

    private var icon: String {
        switch notice.kind {
        case .success: "checkmark.circle.fill"
        case .information: "info.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch notice.kind {
        case .success: Color(nsColor: .systemGreen)
        case .information: .accentColor
        case .error: Color(nsColor: .systemRed)
        }
    }
}

private struct NoticeSurfaceModifier: ViewModifier {
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(tint.opacity(0.14)),
                    in: .capsule
                )
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(tint.opacity(0.2))
                }
        }
    }
}

extension View {
    @ViewBuilder
    func copingSettingsToolbar() -> some View {
        if #available(macOS 15.0, *) {
            toolbar(removing: .sidebarToggle)
                .toolbar(removing: .title)
        } else {
            toolbar(removing: .sidebarToggle)
        }
    }

    @ViewBuilder
    func copingPrimaryButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func copingSecondaryButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

import AppKit
import CoPingCore
import SwiftUI

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    private let content: Content

    init(
        _ title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsHero(
                    title: title,
                    subtitle: subtitle,
                    systemImage: systemImage,
                    tint: tint
                )

                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }
}

struct SettingsHero: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

            Text(title)
                .font(.title2.weight(.bold))

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(SettingsCardBackground())
    }
}

struct SettingsCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(SettingsCardBackground())
    }
}

struct SettingsCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.035))
    }
}

struct SettingsRow<Control: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String?
    private let control: Control

    init(
        systemImage: String,
        tint: Color,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct SettingsCardDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 52)
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
    func copingPrimaryButtonStyle() -> some View {
        buttonStyle(.borderedProminent)
            .tint(Color(nsColor: .systemBlue))
            .foregroundStyle(.white)
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

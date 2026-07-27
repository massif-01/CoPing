import SwiftUI

struct GlassCard<Content: View>: View {
    private let clear: Bool
    private let content: Content

    init(clear: Bool = false, @ViewBuilder content: () -> Content) {
        self.clear = clear
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .modifier(AdaptiveGlassCardModifier(clear: clear))
    }
}

private struct AdaptiveGlassCardModifier: ViewModifier {
    let clear: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    clear ? .clear : .regular,
                    in: .rect(cornerRadius: 18)
                )
        } else if clear {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    cardBorder
                }
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    cardBorder
                }
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(.primary.opacity(0.08))
    }
}

extension View {
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

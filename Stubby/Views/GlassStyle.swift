import SwiftUI

struct StubbyPanelModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(padding)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .padding(padding)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

struct StubbyProminentButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

struct StubbyGlassButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func stubbyPanel(padding: CGFloat = 14, cornerRadius: CGFloat = 8) -> some View {
        modifier(StubbyPanelModifier(padding: padding, cornerRadius: cornerRadius))
    }

    func stubbyProminentButton() -> some View {
        modifier(StubbyProminentButtonModifier())
    }

    func stubbyGlassButton() -> some View {
        modifier(StubbyGlassButtonModifier())
    }
}

import SwiftUI

struct DotGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduced
    func body(content: Content) -> some View {
        if reduced {
            content.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 28))
        } else {
            // Marketplace CI also builds with SDKs predating Liquid Glass.
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            #else
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            #endif
        }
    }
}

struct DotIconButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var destructive = false
    @Environment(\.dotTheme) private var selectedTheme
    private var themeName: String { selectedTheme.rawValue }
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.callout.weight(.semibold))
                .frame(width: 36, height: 36).contentShape(Circle())
        }.buttonStyle(.plain)
            .foregroundStyle(.white)
            .background {
                Circle().fill(destructive ? Color.red.opacity(0.8) : prominent
                    ? (DotTheme(rawValue: themeName) ?? .arctic).messageColor : Color.black.opacity(0.22))
            }
            .overlay(Circle().strokeBorder(.white.opacity(prominent ? 0.38 : 0.22), lineWidth: 0.8))
            .help(title).accessibilityLabel(title)
    }
}

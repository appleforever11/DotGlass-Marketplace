import DockDoorWidgetSDK
import SwiftUI

@objc(DotGlassPlugin)
final class DotGlassPlugin: WidgetPlugin, DockDoorWidgetProvider {
    @MainActor private lazy var connection = DotConnection()
    var id: String { "dot-glass" }
    var name: String { "Dot Glass" }
    var iconSymbol: String { "circle.circle" }
    var widgetDescription: String { "Your Dot in a glass conversation panel, with real messages and a voice-reactive ring." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }
    func settingsSchema() -> [WidgetSetting] {
        [.picker(key: "theme", label: "Orb glow", options: DotTheme.allCases.map(\.rawValue), defaultValue: "Arctic")]
    }
    @MainActor func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(TimelineView(.periodic(from: .now, by: connection.voiceStarting || connection.voiceConnected ? 0.25 : 1)) { timeline in
            DotCompact(size: size, vertical: isVertical, connection: self.connection)
                .environment(\.dotTheme, DotTheme.current)
                .onChange(of: timeline.date) { _, _ in self.connection.tick() }
        })
    }
    @MainActor func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? { AnyView(DotPanel(connection: connection, dismiss: dismiss).frame(width: 440, height: 640)) }
}

@MainActor
struct DotCompact: View {
    let size: CGSize
    let vertical: Bool
    let connection: DotConnection
    private var themeName: String { DotTheme.current.rawValue }
    private var side: CGFloat { max(20, min(size.width, size.height)) }
    var body: some View {
        DotRing(phase: connection.phase, energy: connection.voiceLevel, diameter: side * WidgetMetrics.contentScale)
        .contentShape(Rectangle())
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dot Glass, \(themeName). \(connection.phase.rawValue). \(connection.microphoneMuted ? "Microphone muted." : "") Open conversation panel.")
    }
}

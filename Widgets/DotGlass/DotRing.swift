import SwiftUI

/// A hollow, softly refracting ring. Speech modulation is gated by real playback.
struct DotRing: View {
    @Environment(\.dotTheme) private var selectedTheme
    private var themeName: String { selectedTheme.rawValue }
    private var palette: [Color] { (DotTheme(rawValue: themeName) ?? .arctic).colors }
    let phase: DotPhase
    var energy: Double = 0
    var diameter: CGFloat = 104
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !visible || scenePhase == .background)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let breath = sin(t * 1.35)
            let voice = phase == .speaking && !reduceMotion ? (0.3 + energy * 0.7) : 0
            ZStack {
                Circle()
                    .fill(palette[0].opacity(0.14 + 0.06 * (breath + 1)))
                    .blur(radius: diameter * 0.24)
                    .scaleEffect(1.04 + breath * 0.05 + voice * 0.08)
                RingContour(time: t, energy: voice)
                    .stroke(AngularGradient(colors: [palette[2], palette[0], palette[1], palette[2]], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: diameter * 0.18, lineCap: .round, lineJoin: .round))
                    .padding(diameter * 0.17)
                    .shadow(color: palette[0].opacity(0.24), radius: diameter * 0.08)
                    .scaleEffect(reduceMotion ? 1 : 1 + breath * 0.027)
                Circle().trim(from: 0.05, to: 0.31)
                    .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .padding(diameter * 0.078)
                    .rotationEffect(.degrees(-115))
                if phase == .thinking || phase == .sending {
                    Circle().trim(from: 0, to: 0.21)
                        .stroke(palette[2].opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .padding(2)
                        .rotationEffect(.degrees(reduceMotion ? -90 : t.truncatingRemainder(dividingBy: 5) * 72))
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear { visible = true }.onDisappear { visible = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dot, \(phase.rawValue)")
    }
}

private struct RingContour: Shape {
    var time: Double
    var energy: Double
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0...120 {
            let angle = Double(index) / 120 * .pi * 2
            let ripple = energy * (sin(angle * 3 + time * 7) * 0.045 + sin(angle * 5 - time * 5) * 0.018)
            let r = radius * (1 + ripple)
            let point = CGPoint(x: rect.midX + cos(angle) * r, y: rect.midY + sin(angle) * r)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

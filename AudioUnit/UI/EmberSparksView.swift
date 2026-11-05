import SwiftUI

/// Rising sparks behind the Amount knob. Every particle is a pure function of time and its seed,
/// so nothing is stored or allocated per frame.
struct EmberSparksView: View {
    /// 0...1 - how many sparks and how bright (the Amount knob).
    let heat: Double
    /// 0...1 - output level, makes the glow breathe with the music.
    let energy: Double

    private static let maxSparks = 64

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawGlow(in: &context, size: size)
                drawSparks(in: &context, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawGlow(in context: inout GraphicsContext, size: CGSize) {
        let intensity = 0.15 + 0.45 * heat + 0.4 * energy * heat
        let radius = min(size.width, size.height) * 0.55
        let center = CGPoint(x: size.width / 2, y: size.height * 0.55)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [EmberPalette.flame.opacity(0.55 * intensity),
                                  EmberPalette.coal.opacity(0.25 * intensity),
                                  .clear]),
                center: center, startRadius: 0, endRadius: radius))
    }

    private func drawSparks(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let count = Int(Double(Self.maxSparks) * (0.15 + 0.85 * heat))
        let brightness = (0.35 + 0.65 * heat) * (0.6 + 0.4 * energy)
        context.blendMode = .plusLighter

        for index in 0..<count {
            let seed = Double(index)
            let period = 2.6 + 2.2 * Self.random(seed, 1)
            let phase = (time / period + Self.random(seed, 2)).truncatingRemainder(dividingBy: 1)
            let drift = sin(time * (0.7 + Self.random(seed, 3)) + seed) * 10 * phase
            let spread = (Self.random(seed, 4) - 0.5) * size.width * 0.55 * (0.4 + 0.6 * phase)

            let x = size.width / 2 + spread + drift
            let y = size.height * (0.92 - 0.9 * phase)
            let radius = (1.0 + 2.4 * Self.random(seed, 5)) * (1 - phase * 0.7)
            let alpha = brightness * sin(Double.pi * phase) // fade in, fade out

            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(EmberPalette.emberColor(phase).opacity(alpha)))
        }
    }

    /// Cheap deterministic hash in [0, 1).
    private static func random(_ seed: Double, _ salt: Double) -> Double {
        let value = sin(seed * 12.9898 + salt * 78.233) * 43758.5453
        return value - value.rounded(.down)
    }
}

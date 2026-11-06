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

    /// The halo the knob throws around itself: nothing when cold, a wide bright
    /// bloom when turned up, breathing with the music.
    private func drawGlow(in context: inout GraphicsContext, size: CGSize) {
        guard heat > 0.001 else { return }
        let intensity = pow(heat, 1.3) * (0.8 + 0.35 * energy)
        // Never past the canvas edge, or the halo would show a hard cut.
        let radius = min(size.width, size.height) * (0.36 + 0.14 * heat)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.blendMode = .plusLighter
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [EmberPalette.glowColor(heat).opacity(0.75 * intensity),
                                  EmberPalette.flame.opacity(0.35 * intensity),
                                  EmberPalette.coal.opacity(0.12 * intensity),
                                  .clear]),
                center: center, startRadius: 0, endRadius: radius))
        context.blendMode = .normal
    }

    private func drawSparks(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let count = Int(Double(Self.maxSparks) * heat)
        let brightness = (0.3 + 0.7 * heat) * (0.6 + 0.4 * energy)
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

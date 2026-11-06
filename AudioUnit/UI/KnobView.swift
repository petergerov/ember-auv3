import SwiftUI

/// Passive drawing of a black bakelite pointer knob in a chrome collar, inside
/// a cream scale printed on the panel. The thin accent arc tracks the value so
/// it reads at a glance. `normalized` is 0...1 over a 270° sweep.
///
/// With a `heat` (0...1) the knob glows like a coal being fanned: the swept arc
/// and scale ticks light up, the cap glows from inside and the pointer turns
/// into a hot filament - dull red when barely on, pale yellow when turned up.
struct KnobView: View {
    let normalized: Double
    let theme: GearPalette
    var heat: Double?

    private static let startAngle = -135.0 * .pi / 180.0
    private static let endAngle = 135.0 * .pi / 180.0

    /// Room a glowing knob draws outside its frame, so the bloom isn't cut off.
    private var bleed: CGFloat { heat == nil ? 0 : 28 }

    var body: some View {
        let bleed = self.bleed
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2 + bleed, dy: 2 + bleed)
            let diameter = min(rect.width, rect.height)
            let radius = diameter / 2
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let fraction = min(max(normalized, 0), 1)
            let angle = Self.startAngle + fraction * (Self.endAngle - Self.startAngle)
            let unit = diameter / 78.0 // the design's reference knob size
            let heat = min(max(self.heat ?? 0, 0), 1)
            let glows = self.heat != nil
            let glowColor = EmberPalette.glowColor(heat)

            func point(_ a: Double, _ r: CGFloat) -> CGPoint {
                CGPoint(x: centre.x + CGFloat(sin(a)) * r, y: centre.y - CGFloat(cos(a)) * r)
            }

            // Scale printed on the panel around the knob. On a glowing knob the
            // ticks the arc has passed light up, hotter towards the pointer.
            let tickCount = glows ? 21 : 11
            for i in 0..<tickCount {
                let t = Double(i) / Double(tickCount - 1)
                let tickAngle = Self.startAngle + t * (Self.endAngle - Self.startAngle)
                let major = i % ((tickCount - 1) / 2) == 0
                var tick = Path()
                tick.move(to: point(tickAngle, radius * (major ? 0.80 : 0.86)))
                tick.addLine(to: point(tickAngle, radius * 0.97))
                let width = (major ? 2.2 : 1.4) * unit
                if glows, t <= fraction + 0.001, heat > 0.001 {
                    let local = heat * (0.45 + 0.55 * t / max(fraction, 0.001))
                    var lit = context
                    lit.addFilter(.shadow(color: EmberPalette.glowColor(local).opacity(0.9), radius: 3 * unit * local))
                    lit.stroke(tick, with: .color(EmberPalette.glowColor(local)), lineWidth: width)
                } else {
                    context.stroke(tick,
                                   with: .color(theme.textLight.opacity(major ? 0.9 : 0.55)),
                                   lineWidth: width)
                }
            }

            // Value arc.
            var arc = Path()
            arc.addArc(center: centre, radius: radius * 0.885,
                       startAngle: .radians(Self.startAngle - .pi / 2),
                       endAngle: .radians(angle - .pi / 2), clockwise: false)
            if glows {
                var bloom = context
                bloom.blendMode = .plusLighter
                bloom.stroke(arc, with: .color(glowColor.opacity(0.12 + 0.30 * heat)),
                             style: StrokeStyle(lineWidth: (4.6 + 7 * heat) * unit, lineCap: .round))
                var core = context
                core.addFilter(.shadow(color: glowColor, radius: (1 + 5 * heat) * unit))
                core.stroke(arc, with: .color(glowColor.opacity(0.55 + 0.45 * heat)),
                            style: StrokeStyle(lineWidth: (2 + 1.2 * heat) * unit, lineCap: .round))
            } else {
                context.stroke(arc, with: .color(theme.accent.opacity(0.18)), lineWidth: 4.6 * unit)
                context.stroke(arc, with: .color(theme.accent.opacity(0.92)), lineWidth: 2.0 * unit)
            }

            // Chrome collar the knob is seated in.
            let collarR = radius * 0.74
            let collarBox = CGRect(x: centre.x - collarR, y: centre.y - collarR,
                                   width: collarR * 2, height: collarR * 2)
            context.fill(Path(ellipseIn: collarBox.offsetBy(dx: 0, dy: 2.6 * unit)),
                         with: .color(.black.opacity(0.45)))
            context.fill(Path(ellipseIn: collarBox), with: .linearGradient(
                Gradient(colors: [theme.metalLight, theme.metalMid, theme.metalDark, theme.metalMid]),
                startPoint: CGPoint(x: collarBox.minX, y: collarBox.minY),
                endPoint: CGPoint(x: collarBox.maxX, y: collarBox.maxY)))
            if glows, heat > 0.001 {
                // The glow catching the polished collar.
                context.stroke(Path(ellipseIn: collarBox.insetBy(dx: 0.6 * unit, dy: 0.6 * unit)),
                               with: .color(glowColor.opacity(0.55 * heat)), lineWidth: 1.4 * unit)
            }

            // Bakelite cap.
            let capR = collarR * 0.86
            let capBox = CGRect(x: centre.x - capR, y: centre.y - capR,
                                width: capR * 2, height: capR * 2)
            context.fill(Path(ellipseIn: capBox), with: .radialGradient(
                Gradient(colors: [theme.bakeliteLight, theme.bakeliteDark]),
                center: CGPoint(x: centre.x - capR * 0.4, y: centre.y - capR * 0.5),
                startRadius: 0, endRadius: capR * 1.5))
            if glows, heat > 0.001 {
                // Heated from inside, like a coal: hottest in the middle.
                var ember = context
                ember.blendMode = .plusLighter
                ember.fill(Path(ellipseIn: capBox), with: .radialGradient(
                    Gradient(colors: [glowColor.opacity(0.55 * heat),
                                      EmberPalette.coal.opacity(0.28 * heat), .clear]),
                    center: centre, startRadius: 0, endRadius: capR))
            }
            context.stroke(Path(ellipseIn: capBox), with: .color(.black.opacity(0.7)),
                           lineWidth: 1.2 * unit)

            // Gloss on the moulded top surface.
            let gloss = CGRect(x: centre.x - capR * 0.62, y: centre.y - capR * 0.78,
                               width: capR * 1.05, height: capR * 0.62)
            context.fill(Path(ellipseIn: gloss), with: .radialGradient(
                Gradient(colors: [.white.opacity(0.20), .clear]),
                center: CGPoint(x: gloss.midX, y: gloss.midY),
                startRadius: 0, endRadius: gloss.width * 0.6))

            // Pointer, rotating with the value.
            var rotated = context
            rotated.translateBy(x: centre.x, y: centre.y)
            rotated.rotate(by: .radians(angle))
            rotated.translateBy(x: -centre.x, y: -centre.y)

            let pointerWidth = 3.4 * unit
            let pointer = CGRect(x: centre.x - pointerWidth / 2, y: centre.y - capR * 0.94,
                                 width: pointerWidth, height: capR * 0.94)
            let pointerPath = Path(roundedRect: pointer, cornerRadius: pointerWidth / 2)
            rotated.fill(Path(roundedRect: pointer.offsetBy(dx: 0, dy: 1.2 * unit),
                              cornerRadius: pointerWidth / 2),
                         with: .color(.black.opacity(0.55)))
            rotated.fill(pointerPath, with: .color(theme.textLight))
            if glows, heat > 0.001 {
                // A hot filament: tinted by the heat, blooming as it rises.
                var filament = rotated
                filament.addFilter(.shadow(color: glowColor, radius: (1 + 4 * heat) * unit))
                filament.fill(pointerPath, with: .color(EmberPalette.glowColor(min(1, heat + 0.25)).opacity(heat)))
            }
        }
        // Negative padding: the canvas is larger than the knob, the layout size is not.
        .padding(-bleed)
    }
}

import SwiftUI

/// A latching illuminated push button — the solo key on a 60s console. A
/// chrome bezel holds a coloured glass cap that sits dark when off, lights
/// from behind when engaged, and sinks into the bezel while held or latched.
struct IlluminatedButtonStyle: ButtonStyle {
    let isOn: Bool
    let lampColor: Color
    let theme: GearPalette

    func makeBody(configuration: Configuration) -> some View {
        IlluminatedButtonFace(label: configuration.label, isOn: isOn,
                              isPressed: configuration.isPressed,
                              lampColor: lampColor, theme: theme)
    }
}

private struct IlluminatedButtonFace: View {
    let label: ButtonStyleConfiguration.Label
    let isOn: Bool
    let isPressed: Bool
    let lampColor: Color
    let theme: GearPalette

    /// How far the cap has sunk: further while the finger is on it, a little
    /// while latched, flush when released.
    private var depth: CGFloat { isPressed ? 1.6 : (isOn ? 0.8 : 0) }

    var body: some View {
        ZStack {
            bezel
            cap
                .padding(3)
                .offset(y: depth)
        }
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .animation(.easeOut(duration: 0.12), value: isOn)
    }

    /// Chrome frame with the dark hole the cap sits in.
    private var bezel: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(colors: [theme.metalLight, theme.metalMid, theme.metalDark],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.black.opacity(0.6), lineWidth: 0.8))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .fill(.black.opacity(0.8))
                    .padding(2.2)
            )
            .shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1.5)
    }

    private var cap: some View {
        let shape = RoundedRectangle(cornerRadius: 2.5)
        return shape
            .fill(isOn ? lampColor : theme.lampRedDim)
            // Lit: the bulb's hot spot behind the glass. Unlit: smoked glass.
            .overlay(
                shape.fill(isOn
                    ? RadialGradient(colors: [.white.opacity(0.55), .clear],
                                     center: .init(x: 0.5, y: 0.35), startRadius: 0, endRadius: 46)
                    : RadialGradient(colors: [.white.opacity(0.06), .clear],
                                     center: .init(x: 0.5, y: 0.2), startRadius: 0, endRadius: 46))
            )
            // Glass gloss on the top half, darker towards the bottom lip.
            .overlay(
                shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.3)],
                                          startPoint: .top, endPoint: .bottom))
            )
            .overlay(shape.stroke(.black.opacity(0.65), lineWidth: 0.8))
            .overlay(
                label
                    .font(.system(size: 8.5, weight: .heavy))
                    .tracking(1.3)
                    .foregroundStyle(isOn ? Color.white.opacity(0.95) : theme.textLight.opacity(0.55))
                    .shadow(color: isOn ? lampColor : .black.opacity(0.8),
                            radius: isOn ? 2.5 : 0, x: 0, y: isOn ? 0 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
            )
            // Light spilling out around the cap while engaged.
            .shadow(color: isOn ? lampColor.opacity(0.6) : .clear, radius: 7)
            .shadow(color: .black.opacity(isPressed || isOn ? 0.2 : 0.5), radius: 0.8,
                    x: 0, y: isPressed || isOn ? 0.4 : 1.2)
    }
}

/// The panel-finish selector: a small rotary switch whose cap is painted in
/// the fitted finish and whose pointer stands at that finish's detent.
/// Clicking turns it to the next finish.
struct FinishSelector: View {
    var theme: GearPalette
    @State private var taps = 0

    private var finishes: [GearPalette] { GearPalette.all }
    private var index: Int { finishes.firstIndex { $0.id == theme.id } ?? 0 }

    /// Detents spread over a 70° arc, centred.
    private func detentAngle(_ i: Int) -> Double {
        let steps = max(1, finishes.count - 1)
        return (-35 + Double(i) / Double(steps) * 70) * .pi / 180
    }

    var body: some View {
        Button {
            ThemeStore.shared.selectNext()
            taps += 1
        } label: {
            FinishSelectorDrawing(theme: theme, count: finishes.count, index: index,
                                  detentAngle: detentAngle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Panel finish: \(theme.name)")
        .accessibilityLabel("Panel finish")
        .accessibilityValue(theme.name)
        .accessibilityHint("Switches the panel colourway")
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: taps)
    }
}

private struct FinishSelectorDrawing: View {
    let theme: GearPalette
    let count: Int
    let index: Int
    let detentAngle: (Int) -> Double

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2

            func point(_ a: Double, _ r: CGFloat) -> CGPoint {
                CGPoint(x: centre.x + CGFloat(sin(a)) * r, y: centre.y - CGFloat(cos(a)) * r)
            }

            // Detent marks printed on the panel, one per finish.
            for i in 0..<count {
                let a = detentAngle(i)
                var tick = Path()
                tick.move(to: point(a, radius * 0.82))
                tick.addLine(to: point(a, radius * 0.99))
                context.stroke(tick, with: .color(theme.textLight.opacity(i == index ? 0.9 : 0.45)),
                               lineWidth: 1.4)
            }

            // Chrome bezel.
            let bezelR = radius * 0.74
            let bezel = CGRect(x: centre.x - bezelR, y: centre.y - bezelR,
                               width: bezelR * 2, height: bezelR * 2)
            context.fill(Path(ellipseIn: bezel.offsetBy(dx: 0, dy: 1.4)),
                         with: .color(.black.opacity(0.45)))
            context.fill(Path(ellipseIn: bezel), with: .linearGradient(
                Gradient(colors: [theme.metalLight, theme.metalMid, theme.metalDark]),
                startPoint: CGPoint(x: bezel.minX, y: bezel.minY),
                endPoint: CGPoint(x: bezel.maxX, y: bezel.maxY)))

            // Cap painted in the fitted finish, so it doubles as a swatch.
            let capR = bezelR * 0.78
            let cap = CGRect(x: centre.x - capR, y: centre.y - capR,
                             width: capR * 2, height: capR * 2)
            context.fill(Path(ellipseIn: cap), with: .linearGradient(
                Gradient(colors: [theme.paintTop, theme.paintBottom]),
                startPoint: CGPoint(x: cap.midX, y: cap.minY),
                endPoint: CGPoint(x: cap.midX, y: cap.maxY)))
            context.stroke(Path(ellipseIn: cap), with: .color(.black.opacity(0.55)), lineWidth: 0.8)

            // Pointer standing at the fitted finish's detent.
            var rotated = context
            rotated.translateBy(x: centre.x, y: centre.y)
            rotated.rotate(by: .radians(detentAngle(index)))
            rotated.translateBy(x: -centre.x, y: -centre.y)
            let width: CGFloat = 2.0
            let pointer = CGRect(x: centre.x - width / 2, y: centre.y - capR * 0.92,
                                 width: width, height: capR * 0.92)
            rotated.fill(Path(roundedRect: pointer, cornerRadius: width / 2),
                         with: .color(theme.textLight))

            // Gloss.
            context.fill(Path(ellipseIn: CGRect(x: centre.x - capR * 0.55, y: centre.y - capR * 0.72,
                                                 width: capR * 0.9, height: capR * 0.5)),
                         with: .radialGradient(
                            Gradient(colors: [.white.opacity(0.22), .clear]),
                            center: CGPoint(x: centre.x - capR * 0.1, y: centre.y - capR * 0.47),
                            startRadius: 0, endRadius: capR * 0.6))
        }
    }
}

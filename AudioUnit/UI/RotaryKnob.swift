import SwiftUI

/// Drag up/right to increase, double-click/tap to reset. Sends touch/release automation events.
struct RotaryKnob: View {
    enum Style {
        case hero
        case trim
    }

    let model: ParameterModel
    let label: String
    let diameter: CGFloat
    var style: Style = .trim

    @State private var dragOrigin: Double?

    private static let sweepDegrees = 270.0
    private static let startDegrees = 135.0

    var body: some View {
        VStack(spacing: style == .hero ? 10 : 6) {
            dial
            if style == .trim {
                KnobCaption(label: label, value: model.displayText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(model.displayText)
        .accessibilityAdjustableAction { direction in
            let step = 0.02
            switch direction {
            case .increment: model.commit(model.value + step * span)
            case .decrement: model.commit(model.value - step * span)
            @unknown default: break
            }
        }
    }

    private var span: Double { model.range.upperBound - model.range.lowerBound }

    private var dial: some View {
        ZStack {
            KnobArc(start: Self.startDegrees, sweep: Self.sweepDegrees, progress: 1)
                .stroke(EmberPalette.track, style: StrokeStyle(lineWidth: arcWidth, lineCap: .round))
            KnobArc(start: Self.startDegrees, sweep: Self.sweepDegrees, progress: model.normalizedValue)
                .stroke(EmberPalette.heat, style: StrokeStyle(lineWidth: arcWidth, lineCap: .round))
                .shadow(color: EmberPalette.flame.opacity(style == .hero ? 0.7 : 0.3), radius: style == .hero ? 10 : 4)
            // Arc angles count from 3 o'clock; the pointer counts from 12 o'clock, hence +90.
            KnobCap(rotation: Self.startDegrees + 90 + Self.sweepDegrees * model.normalizedValue,
                    inset: arcWidth * 1.8)
            if style == .hero {
                HeroReadout(label: label, value: model.displayText)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(dragGesture)
        .onTapGesture(count: 2) { model.resetToDefault() }
    }

    private var arcWidth: CGFloat { style == .hero ? 9 : 4 }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                let origin = dragOrigin ?? model.normalizedValue
                if dragOrigin == nil {
                    dragOrigin = origin
                    model.beginEditing()
                }
                let travel = gesture.translation.width - gesture.translation.height
                let pixelsForFullRange = style == .hero ? 320.0 : 220.0
                model.setNormalizedValue(origin + travel / pixelsForFullRange)
            }
            .onEnded { _ in
                model.endEditing()
                dragOrigin = nil
            }
    }
}

/// Arc starting at `start` degrees (0 = 3 o'clock, clockwise on screen) sweeping `sweep * progress`.
private struct KnobArc: Shape {
    let start: Double
    let sweep: Double
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: .degrees(start), endAngle: .degrees(start + sweep * min(max(progress, 0), 1)),
                    clockwise: false)
        return path
    }
}

private struct KnobCap: View {
    /// Pointer angle in degrees, 0 = pointing up.
    let rotation: Double
    let inset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) - inset * 2
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.22), Color(white: 0.10)],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75))
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: size * 0.06, y: size * 0.03)
                Capsule()
                    .fill(EmberPalette.spark)
                    .frame(width: max(2, size * 0.035), height: size * 0.16)
                    .offset(y: -size * 0.36)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

private struct HeroReadout: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(EmberPalette.text)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(3)
                .foregroundStyle(EmberPalette.mutedText)
        }
        .allowsHitTesting(false)
    }
}

private struct KnobCaption: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(EmberPalette.mutedText)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(EmberPalette.text)
        }
    }
}

import SwiftUI

/// A knob bound to one AU parameter: silkscreened caption, bakelite knob, LED
/// readout. Drag up/right to increase, double-click to reset. Gestures go through
/// begin/set/end so hosts can record touch-style automation.
struct ParameterKnob: View {
    let model: ParameterModel
    let label: String
    var diameter: CGFloat = 54
    /// 0...1 - set for a knob that glows with its value (the Amount knob).
    var heat: Double?

    @State private var dragOrigin: Double?
    @State private var resets = 0

    /// Points of drag travel for the full range; bigger knobs turn finer.
    private var dragRange: Double { diameter > 100 ? 320 : 200 }
    private var isHero: Bool { diameter > 100 }

    var body: some View {
        VStack(spacing: isHero ? 8 : 5) {
            SilkscreenText(text: label, size: isHero ? 11 : 9.5)
                .frame(minHeight: 14)

            KnobView(normalized: model.normalizedValue, theme: GearTheme.current, heat: heat)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .gesture(dragGesture)
                .onTapGesture(count: 2) {
                    model.resetToDefault()
                    resets += 1
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: resets)

            // Wide enough for the longest readout so the window doesn't resize while turning.
            LedReadout(text: model.displayText,
                       minWidth: isHero ? 96 : max(diameter, 66),
                       fontSize: isHero ? 16 : 10.5,
                       glow: heat.map { 0.35 + 0.65 * $0 } ?? 0.75)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(model.displayText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.commit(model.value + 0.02 * span)
            case .decrement: model.commit(model.value - 0.02 * span)
            @unknown default: break
            }
        }
    }

    private var span: Double { model.range.upperBound - model.range.lowerBound }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                let origin = dragOrigin ?? model.normalizedValue
                if dragOrigin == nil {
                    dragOrigin = origin
                    model.beginEditing()
                }
                let travel = gesture.translation.width - gesture.translation.height
                model.setNormalizedValue(origin + travel / dragRange)
            }
            .onEnded { _ in
                model.endEditing()
                dragOrigin = nil
            }
    }
}

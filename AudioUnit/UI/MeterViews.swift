import SwiftUI

/// Horizontal gain-reduction bar that grows from the right.
struct GainReductionBar: View {
    let label: String
    /// Positive dB.
    let reductionDb: Double
    var fullScaleDb = 12.0

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(EmberPalette.mutedText)
                .frame(width: 44, alignment: .leading)
            GeometryReader { proxy in
                let fraction = min(max(reductionDb / fullScaleDb, 0), 1)
                ZStack(alignment: .trailing) {
                    Capsule().fill(EmberPalette.track)
                    Capsule()
                        .fill(EmberPalette.heat)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 5)
            Text(reductionDb >= 0.05 ? String(format: "-%.1f", reductionDb) : "0.0")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(EmberPalette.text)
                .frame(width: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) gain reduction")
        .accessibilityValue(String(format: "%.1f decibels", reductionDb))
    }
}

/// Stereo output peak meter (vertical bars).
struct PeakMeter: View {
    let left: Double
    let right: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                PeakBar(level: left)
                PeakBar(level: right)
            }
            Text("OUT")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(EmberPalette.mutedText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Output level")
    }
}

private struct PeakBar: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Capsule().fill(EmberPalette.track)
                Capsule()
                    .fill(LinearGradient(colors: [EmberPalette.flame, EmberPalette.spark], startPoint: .bottom, endPoint: .top))
                    .frame(height: proxy.size.height * min(max(level, 0), 1))
            }
        }
        .frame(width: 5)
    }
}

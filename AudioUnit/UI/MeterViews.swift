import SwiftUI

/// Gain reduction as one bar in a recessed slot, filling **right to left** from
/// rest - a bar that filled left-to-right would read as level.
///
/// Position goes as `(dB / fullScale)^0.7`, so the first dB takes far more of the
/// track than the last: the glue rarely exceeds a couple of dB, but it should show.
struct GainReductionMeter: View {
    let label: String
    /// Positive dB.
    let reductionDb: Double
    var fullScale: Double = 12

    private static let scaleMarks: [Double] = [0, 1, 3, 6, 12]

    private func fill(_ db: Double) -> Double {
        pow(min(max(db, 0), fullScale) / fullScale, 0.7)
    }

    var body: some View {
        let theme = GearTheme.current

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                SilkscreenText(text: label, size: 8)
                Spacer(minLength: 4)
                Text(reductionDb >= 0.05 ? String(format: "−%.1f dB", reductionDb) : "0.0 dB")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.ledText)
                    .shadow(color: theme.ledText.opacity(0.7), radius: 2)
            }

            // Labels placed by the same mapping as the fill, so they agree.
            BarScale(marks: Self.scaleMarks.filter { $0 <= fullScale },
                     fraction: { 1 - fill($0) }, theme: theme)

            GeometryReader { geo in
                ZStack(alignment: .trailing) {
                    BarTrack(theme: theme)
                    LinearGradient(colors: [theme.meterAmber, theme.meterAmber, theme.meterRed],
                                   startPoint: .trailing, endPoint: .leading)
                        .mask(alignment: .trailing) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .frame(width: max(0, (geo.size.width - 3) * fill(reductionDb)))
                        }
                        .padding(1.5)
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) gain reduction")
        .accessibilityValue(String(format: "%.1f decibels", reductionDb))
    }
}

/// The recessed slot a bar sits in.
private struct BarTrack: View {
    var theme: GearPalette

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(theme.ledBackground)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.black.opacity(0.7), lineWidth: 1))
            .overlay(
                // Light catching the lower lip, so the slot reads as cut in.
                RoundedRectangle(cornerRadius: 2)
                    .stroke(theme.panelEdgeLight.opacity(0.18), lineWidth: 0.6)
                    .padding(.top, 1.5)
            )
    }
}

/// Silkscreened tick labels above a bar.
private struct BarScale: View {
    var marks: [Double]
    var fraction: (Double) -> Double
    var theme: GearPalette

    var body: some View {
        GeometryReader { geo in
            ForEach(marks, id: \.self) { mark in
                Text(String(format: "%.0f", mark))
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textMuted.opacity(0.85))
                    .fixedSize()
                    // Nudged in at the ends so the outermost label stays on the plate.
                    .position(x: min(max(geo.size.width * fraction(mark), 6), geo.size.width - 6),
                              y: geo.size.height / 2)
            }
        }
        .frame(height: 9)
    }
}

/// Output level as segmented LED ladders behind a glass window, the way outboard
/// gear showed level before screens: ten lamps over 48 dB, green through amber into red.
struct LevelLadder: View {
    /// 0...1 on a -48...0 dBFS scale.
    let left: Double
    let right: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LadderRow(label: "L", level: left, theme: GearTheme.current)
            LadderRow(label: "R", level: right, theme: GearTheme.current)
        }
        .frame(width: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Output level")
    }
}

private struct LadderRow: View {
    let label: String
    let level: Double
    let theme: GearPalette

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundStyle(theme.textLight.opacity(0.85))
                .shadow(color: .black.opacity(0.6), radius: 0, y: 0.5)
                .frame(width: 10, alignment: .leading)

            LadderSegments(lit: Int((min(max(level, 0), 1) * Double(LadderSegments.count)).rounded(.down)),
                           theme: theme)
                .frame(height: 7)
                .padding(.horizontal, 2.5)
                .padding(.vertical, 2)
                .background(LedWindow(cornerRadius: 2))
        }
    }
}

private struct LadderSegments: View {
    static let count = 10

    let lit: Int
    let theme: GearPalette

    var body: some View {
        Canvas { context, size in
            let gap = size.width * 0.055 / CGFloat(Self.count - 1) * CGFloat(Self.count)
            let cellWidth = (size.width - gap * CGFloat(Self.count - 1)) / CGFloat(Self.count)

            for i in 0..<Self.count {
                let cell = CGRect(x: CGFloat(i) * (cellWidth + gap), y: 0,
                                  width: cellWidth, height: size.height)
                let path = Path(roundedRect: cell, cornerRadius: min(1.5, cellWidth * 0.35))
                if i < lit {
                    let colour = segmentColour(i)
                    context.fill(path.strokedPath(.init(lineWidth: 2.4)), with: .color(colour.opacity(0.35)))
                    context.fill(path, with: .color(colour))
                } else {
                    context.fill(path, with: .color(theme.meterOff))
                    context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 0.6)
                }
            }
        }
    }

    private func segmentColour(_ index: Int) -> Color {
        switch index {
        case 0..<6: theme.meterGreen
        case 6..<8: theme.meterAmber
        default: theme.meterRed
        }
    }
}

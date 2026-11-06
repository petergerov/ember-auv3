import SwiftUI

/// A console channel on its own screwed-on sub-plate: jewel lamp, silkscreened
/// title and subtitle, then the channel's controls. The lamp shows whether the
/// channel is currently reaching the output.
struct ChannelPanel<Content: View>: View {
    let title: String
    let subtitle: String
    var isLit: Bool = true
    /// 0...1 - warm light from the controls spilling onto the plate.
    var glow: Double = 0
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChannelHeader(title: title, subtitle: subtitle, isLit: isLit)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, PanelMetrics.plateInset)
        .padding(.top, 11)
        .padding(.bottom, 15)
        // Stretch inside the background so the plate itself fills a row whose
        // height was set by a taller neighbour.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PanelPlate(theme: GearTheme.current))
        .overlay { PlateGlow(glow: glow) }
    }
}

/// Light from a glowing control washing over its plate, strongest at the centre.
private struct PlateGlow: View {
    let glow: Double

    var body: some View {
        if glow > 0.001 {
            RoundedRectangle(cornerRadius: 5)
                .fill(RadialGradient(
                    colors: [EmberPalette.glowColor(glow).opacity(0.30 * glow),
                             EmberPalette.coal.opacity(0.10 * glow), .clear],
                    center: UnitPoint(x: 0.5, y: 0.5), startRadius: 0, endRadius: 190))
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}

private struct ChannelHeader: View {
    let title: String
    let subtitle: String
    let isLit: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            JewelLamp(isOn: isLit, color: GearTheme.accent, theme: GearTheme.current)
                .frame(width: 9, height: 9)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(2.0)
                    .foregroundStyle(isLit ? GearTheme.textLight : GearTheme.textMuted)
                    .shadow(color: .black.opacity(0.7), radius: 0, x: 0, y: 1)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(GearTheme.textMuted)
                    .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.leading, 6) // clear of the corner screw
        .accessibilityElement(children: .combine)
    }
}

/// A small silkscreened label over a group of controls inside a plate.
struct SectionLabel: View {
    let text: String

    var body: some View {
        SilkscreenText(text: text, size: 8.5, dimmed: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

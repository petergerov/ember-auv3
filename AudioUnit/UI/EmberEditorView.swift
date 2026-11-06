import SwiftUI

/// Root of the plugin editor: Ember's controls on screwed-on plates, bolted into a
/// rack chassis - the same family of hardware as the Exciting Compressor.
struct EmberEditorView: View {
    let viewModel: EmberViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ChassisBackground(theme: GearTheme.current)

                HStack(spacing: 0) {
                    RackEar(theme: GearTheme.current).frame(width: PanelMetrics.earWidth)
                    Spacer(minLength: 0)
                    RackEar(theme: GearTheme.current).frame(width: PanelMetrics.earWidth)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    // Centred when the host gives more height than needed;
                    // the spacers collapse and it scrolls when it's short.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        PanelContent(viewModel: viewModel)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                FooterRivetStrip(theme: GearTheme.current)
                    .frame(width: geo.size.width, height: PanelMetrics.footerHeight)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.colorScheme, .dark)
        .tint(GearTheme.accent)
        .task { await viewModel.runMeterLoop() }
    }
}

private struct PanelContent: View {
    let viewModel: EmberViewModel

    var body: some View {
        let inset = PanelMetrics.sideInset
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                EditorHeader(viewModel: viewModel, stacked: false)
                EditorHeader(viewModel: viewModel, stacked: true)
            }
            .padding(.horizontal, inset)
            .padding(.top, 10)
            .padding(.bottom, 8)

            EngravedGroove()
                .padding(.horizontal, inset)

            ViewThatFits(in: .horizontal) {
                WideLayout(viewModel: viewModel)
                CompactLayout(viewModel: viewModel)
            }
            .padding(.horizontal, inset)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ModelPlate(text: "MODEL EM-1  ·  WARM MASTERING  ·  \(Self.versionString)")
                .padding(.horizontal, inset)
                .padding(.bottom, PanelMetrics.footerHeight + 6)
        }
    }

    private static let versionString: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(version)"
    }()
}

// MARK: - Layouts

private struct WideLayout: View {
    let viewModel: EmberViewModel

    var body: some View {
        VStack(spacing: 12) {
            // fixedSize resolves the row to the Heat plate's height and the side
            // plates stretch to it - modules cut to one height, as in a rack.
            HStack(alignment: .top, spacing: 12) {
                InputSection(viewModel: viewModel).frame(width: 134)
                HeatSection(viewModel: viewModel)
                OutputSection(viewModel: viewModel).frame(width: 134)
            }
            .fixedSize(horizontal: false, vertical: true)
            DynamicsSection(viewModel: viewModel, stacked: false)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 520)
    }
}

private struct CompactLayout: View {
    let viewModel: EmberViewModel

    var body: some View {
        VStack(spacing: 12) {
            HeatSection(viewModel: viewModel)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                InputSection(viewModel: viewModel)
                OutputSection(viewModel: viewModel)
            }
            .fixedSize(horizontal: false, vertical: true)
            DynamicsSection(viewModel: viewModel, stacked: true)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Header

private struct EditorHeader: View {
    let viewModel: EmberViewModel
    let stacked: Bool

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    FinishSelector(theme: GearTheme.current).frame(width: 26, height: 26)
                    Wordmark()
                    Spacer(minLength: 8)
                    HeaderMeters(viewModel: viewModel)
                }
                ModeButtons(viewModel: viewModel)
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                FinishSelector(theme: GearTheme.current).frame(width: 26, height: 26)
                Wordmark()
                Spacer(minLength: 12)
                HeaderMeters(viewModel: viewModel)
                ModeButtons(viewModel: viewModel)
            }
        }
    }
}

/// Its own view so the per-frame meter updates re-render only the ladder.
private struct HeaderMeters: View {
    let viewModel: EmberViewModel

    var body: some View {
        LevelLadder(left: viewModel.meters.outputLeft, right: viewModel.meters.outputRight)
    }
}

private struct Wordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Ember")
                .font(.custom("Georgia-BoldItalic", size: 20))
                .foregroundStyle(GearTheme.textLight)
                .shadow(color: .black.opacity(0.75), radius: 0, x: 0, y: 1.5)
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
                .lineLimit(1)
            Text("ONE-KNOB WARM MASTERING")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(GearTheme.textLight.opacity(0.88))
                .shadow(color: .black.opacity(0.75), radius: 0, x: 0, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

private struct ModeButtons: View {
    let viewModel: EmberViewModel

    var body: some View {
        HStack(spacing: 8) {
            ModeButton(model: viewModel.truePeak, title: "True Peak", accessibilityName: "True peak limiting",
                       help: "Limit inter-sample peaks (dBTP) so the master stays under the ceiling after conversion and encoding")
            ModeButton(model: viewModel.match, title: "Match", accessibilityName: "Loudness match",
                       help: "Loudness match: turns the output down so you hear the colour, not just the level")
        }
    }
}

/// A latching illuminated push button bound to an on/off parameter.
private struct ModeButton: View {
    let model: ParameterModel
    let title: String
    let accessibilityName: String
    let help: String

    @State private var taps = 0

    var body: some View {
        Button {
            model.commit(model.isOn ? 0 : 1)
            taps += 1
        } label: {
            Text(title.uppercased())
        }
        .buttonStyle(IlluminatedButtonStyle(isOn: model.isOn, lampColor: GearTheme.accent,
                                            theme: GearTheme.current))
        .frame(width: 84, height: 26)
        .contentShape(Rectangle())
        .help(help)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(model.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}

// MARK: - Sections

private struct InputSection: View {
    let viewModel: EmberViewModel

    var body: some View {
        ChannelPanel(title: "Input", subtitle: "Drive in") {
            VStack {
                Spacer(minLength: 0)
                ParameterKnob(model: viewModel.inputGain, label: "Gain", diameter: 62)
                Spacer(minLength: 0)
            }
        }
    }
}

/// The Amount knob on its own plate. The further it is turned, the hotter it glows:
/// knob, halo, sparks and the light on the plate all follow the Amount, and breathe
/// with the output level.
private struct HeatSection: View {
    let viewModel: EmberViewModel

    private static let heroDiameter: CGFloat = 150

    var body: some View {
        let amount = viewModel.amount.normalizedValue
        let heat = amount * (0.85 + 0.15 * viewModel.meters.energy)

        ChannelPanel(title: "Heat", subtitle: "Saturation, glue and limiting",
                     isLit: amount > 0.001, glow: heat) {
            ParameterKnob(model: viewModel.amount, label: "Amount",
                          diameter: Self.heroDiameter, heat: heat)
                // A background, so the sparks may spread past the knob without widening the plate.
                .background {
                    EmberSparksView(heat: amount, energy: viewModel.meters.energy)
                        .frame(width: Self.heroDiameter * 1.6, height: Self.heroDiameter * 1.6)
                        .offset(y: -8)
                }
        }
    }
}

private struct OutputSection: View {
    let viewModel: EmberViewModel

    var body: some View {
        ChannelPanel(title: "Output", subtitle: "Master") {
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                ParameterKnob(model: viewModel.outputGain, label: "Gain", diameter: 56)
                ParameterKnob(model: viewModel.ceiling, label: "Ceiling", diameter: 44)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Its own view so the per-frame meter updates re-render only the bars.
private struct DynamicsSection: View {
    let viewModel: EmberViewModel
    let stacked: Bool

    var body: some View {
        let glue = GainReductionMeter(label: "Glue", reductionDb: viewModel.meters.glueReduction)
        let limit = GainReductionMeter(label: "Limit", reductionDb: viewModel.meters.limiterReduction)

        ChannelPanel(title: "Dynamics", subtitle: "Gain reduction") {
            if stacked {
                VStack(spacing: 10) { glue; limit }
            } else {
                HStack(spacing: 24) { glue; limit }
            }
        }
    }
}

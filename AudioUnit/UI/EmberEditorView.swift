import SwiftUI

/// Root of the plugin editor.
struct EmberEditorView: View {
    let viewModel: EmberViewModel

    var body: some View {
        GeometryReader { proxy in
            let heroDiameter = min(proxy.size.width * 0.38, proxy.size.height * 0.48, 220)
            VStack(spacing: 0) {
                EditorHeader(truePeak: viewModel.truePeak, match: viewModel.match)
                Spacer(minLength: 8)
                KnobRow(viewModel: viewModel, heroDiameter: heroDiameter)
                Spacer(minLength: 8)
                MeterPanel(viewModel: viewModel)
            }
            .padding(20)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(EditorBackground())
        .task { await viewModel.runMeterLoop() }
    }
}

private struct EditorBackground: View {
    var body: some View {
        LinearGradient(colors: [EmberPalette.backgroundTop, EmberPalette.backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

private struct EditorHeader: View {
    let truePeak: ParameterModel
    let match: ParameterModel

    var body: some View {
        HStack {
            Text("EMBER")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .tracking(7)
                .foregroundStyle(EmberPalette.text)
            Spacer()
            HStack(spacing: 8) {
                PillToggle(model: truePeak, title: "TRUE PEAK", accessibilityName: "True peak limiting",
                           help: "Limit inter-sample peaks (dBTP) so the master stays under the ceiling after conversion and encoding")
                PillToggle(model: match, title: "MATCH", accessibilityName: "Loudness match",
                           help: "Loudness match: turns the output down so you hear the colour, not just the level")
            }
        }
    }
}

private struct PillToggle: View {
    let model: ParameterModel
    let title: String
    let accessibilityName: String
    let help: String

    var body: some View {
        Button {
            model.commit(model.isOn ? 0 : 1)
        } label: {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(model.isOn ? Color.black : EmberPalette.mutedText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(model.isOn ? AnyShapeStyle(EmberPalette.heat) : AnyShapeStyle(EmberPalette.panel)))
                .overlay(Capsule().stroke(EmberPalette.panelStroke))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(model.isOn ? "On" : "Off")
    }
}

private struct KnobRow: View {
    let viewModel: EmberViewModel
    let heroDiameter: CGFloat

    var body: some View {
        HStack(alignment: .center) {
            RotaryKnob(model: viewModel.inputGain, label: "INPUT", diameter: 58)
            Spacer(minLength: 12)
            ZStack {
                EmberSparksView(heat: viewModel.amount.normalizedValue, energy: viewModel.meters.energy)
                    .frame(width: heroDiameter * 1.7, height: heroDiameter * 1.5)
                RotaryKnob(model: viewModel.amount, label: "AMOUNT", diameter: heroDiameter, style: .hero)
            }
            .frame(width: heroDiameter * 1.3, height: heroDiameter * 1.2)
            Spacer(minLength: 12)
            RotaryKnob(model: viewModel.outputGain, label: "OUTPUT", diameter: 58)
        }
    }
}

private struct MeterPanel: View {
    let viewModel: EmberViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 10) {
                GainReductionBar(label: "GLUE", reductionDb: viewModel.meters.glueReduction)
                GainReductionBar(label: "LIMIT", reductionDb: viewModel.meters.limiterReduction)
            }
            RotaryKnob(model: viewModel.ceiling, label: "CEILING", diameter: 36)
            PeakMeter(left: viewModel.meters.outputLeft, right: viewModel.meters.outputRight)
                .frame(height: 64)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(EmberPalette.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(EmberPalette.panelStroke))
    }
}

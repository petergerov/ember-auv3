import AudioToolbox
import Observation

/// Display-ready meter values (ballistics applied).
struct MeterLevels: Equatable {
    /// 0...1 on a -48...0 dBFS scale.
    var outputLeft: Double = 0
    var outputRight: Double = 0
    /// Positive dB of gain reduction.
    var glueReduction: Double = 0
    var limiterReduction: Double = 0
    /// 0...1, drives the visualizer.
    var energy: Double = 0
}

@Observable
@MainActor
final class EmberViewModel {
    let amount: ParameterModel
    let inputGain: ParameterModel
    let outputGain: ParameterModel
    let ceiling: ParameterModel
    let match: ParameterModel
    let truePeak: ParameterModel
    private(set) var meters = MeterLevels()

    @ObservationIgnored private let audioUnit: EmberAudioUnit
    @ObservationIgnored private var observerToken: AUParameterObserverToken?

    private static let meterFloorDb = -48.0
    private static let peakFallPerFrame = 0.025
    private static let reductionFallPerFrame = 0.6

    init?(audioUnit: EmberAudioUnit) {
        guard let tree = audioUnit.parameterTree,
              let amount = tree.parameter(withAddress: EmberParam.amount.rawValue),
              let inputGain = tree.parameter(withAddress: EmberParam.inputGain.rawValue),
              let outputGain = tree.parameter(withAddress: EmberParam.outputGain.rawValue),
              let ceiling = tree.parameter(withAddress: EmberParam.ceiling.rawValue),
              let match = tree.parameter(withAddress: EmberParam.match.rawValue),
              let truePeak = tree.parameter(withAddress: EmberParam.truePeak.rawValue)
        else { return nil }

        self.audioUnit = audioUnit
        self.amount = ParameterModel(parameter: amount)
        self.inputGain = ParameterModel(parameter: inputGain)
        self.outputGain = ParameterModel(parameter: outputGain)
        self.ceiling = ParameterModel(parameter: ceiling)
        self.match = ParameterModel(parameter: match)
        self.truePeak = ParameterModel(parameter: truePeak)

        // The observer runs on arbitrary threads: keep it @Sendable (not main-actor isolated)
        // and hop to the main actor explicitly.
        let observer: AUParameterObserver = { @Sendable [weak self] address, value in
            Task { @MainActor in
                self?.receive(address: address, value: value)
            }
        }
        let token = tree.token(byAddingParameterObserver: observer)
        observerToken = token
        for model in allParameters {
            model.originatorToken = token
        }
        // The Ceiling readout switches between dB and dBTP with the True Peak mode.
        let ceilingModel = self.ceiling
        self.truePeak.onValueChange = { ceilingModel.refreshDisplay() }
    }

    var allParameters: [ParameterModel] {
        [amount, inputGain, outputGain, ceiling, match, truePeak]
    }

    func disconnect() {
        if let observerToken {
            audioUnit.parameterTree?.removeParameterObserver(observerToken)
        }
        observerToken = nil
    }

    /// Polls the kernel meters at ~30 fps while the editor is visible. Cancelled by `.task`.
    func runMeterLoop() async {
        while !Task.isCancelled {
            refreshMeters()
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    private func receive(address: AUParameterAddress, value: AUValue) {
        allParameters.first { $0.address == address }?.receiveExternalValue(value)
    }

    private func refreshMeters() {
        let snapshot = audioUnit.consumeMeters()
        var next = meters
        next.outputLeft = max(Self.normalized(snapshot.outputPeakLeft), meters.outputLeft - Self.peakFallPerFrame)
        next.outputRight = max(Self.normalized(snapshot.outputPeakRight), meters.outputRight - Self.peakFallPerFrame)
        next.glueReduction = max(Double(-snapshot.compressorGainReductionDb), meters.glueReduction - Self.reductionFallPerFrame)
        next.limiterReduction = max(Double(-snapshot.limiterGainReductionDb), meters.limiterReduction - Self.reductionFallPerFrame)
        next.energy = meters.energy + 0.25 * (max(next.outputLeft, next.outputRight) - meters.energy)
        if next != meters {
            meters = next
        }
    }

    private static func normalized(_ linear: Float) -> Double {
        let db = 20 * log10(max(Double(linear), 1e-6))
        return min(max((db - meterFloorDb) / -meterFloorDb, 0), 1)
    }
}

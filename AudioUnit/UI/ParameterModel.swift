import AudioToolbox
import Observation

/// Observable mirror of one `AUParameter`. Gestures go through begin/set/end so hosts can
/// record touch-style automation.
@Observable
@MainActor
final class ParameterModel {
    let address: AUParameterAddress
    let name: String
    let range: ClosedRange<Double>
    let defaultValue: Double
    private(set) var value: Double
    private(set) var isEditing = false
    /// Bumped when the value string depends on another parameter (e.g. Ceiling dB vs dBTP).
    private var displayRevision = 0

    @ObservationIgnored private let parameter: AUParameter
    /// Set by the owner once it registered its observer, so our own writes are not echoed back.
    @ObservationIgnored var originatorToken: AUParameterObserverToken?
    /// Called after any value change, local or from the host.
    @ObservationIgnored var onValueChange: (@MainActor () -> Void)?

    init(parameter: AUParameter) {
        self.parameter = parameter
        address = parameter.address
        name = parameter.displayName
        range = Double(parameter.minValue)...Double(parameter.maxValue)
        defaultValue = Double(EmberParamDefaultValue(EmberParam(rawValue: parameter.address) ?? .amount))
        value = Double(parameter.value)
    }

    var normalizedValue: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var isOn: Bool { value >= 0.5 }

    var displayText: String {
        _ = displayRevision
        var current = AUValue(value)
        return parameter.string(fromValue: &current)
    }

    func refreshDisplay() {
        displayRevision &+= 1
    }

    func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        send(.touch)
    }

    func setNormalizedValue(_ normalized: Double) {
        setValue(range.lowerBound + min(max(normalized, 0), 1) * (range.upperBound - range.lowerBound))
    }

    func setValue(_ newValue: Double) {
        let clamped = min(max(newValue, range.lowerBound), range.upperBound)
        guard clamped != value else { return }
        value = clamped
        send(.value)
        onValueChange?()
    }

    func endEditing() {
        guard isEditing else { return }
        send(.release)
        isEditing = false
    }

    /// One complete gesture: touch, value, release.
    func commit(_ newValue: Double) {
        beginEditing()
        setValue(newValue)
        endEditing()
    }

    func resetToDefault() {
        commit(defaultValue)
    }

    /// A change that came from the host (automation, preset, another view).
    func receiveExternalValue(_ newValue: AUValue) {
        guard !isEditing, Double(newValue) != value else { return }
        value = Double(newValue)
        onValueChange?()
    }

    private func send(_ eventType: AUParameterAutomationEventType) {
        parameter.setValue(AUValue(value), originator: originatorToken, atHostTime: 0, eventType: eventType)
    }
}

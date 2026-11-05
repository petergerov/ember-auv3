#ifndef EmberParameterAddresses_h
#define EmberParameterAddresses_h

// Shared by the C++ DSP kernel, the Objective-C++ Audio Unit and Swift (via the bridging header).
// Keep it plain C so every layer can include it.

#include <stdint.h>

typedef enum __attribute__((enum_extensibility(closed))) EmberParam : uint64_t {
    EmberParamAmount = 0,     ///< 0...100 %   - the one macro knob
    EmberParamInputGain = 1,  ///< -12...+12 dB
    EmberParamOutputGain = 2, ///< -12...+12 dB
    EmberParamCeiling = 3,    ///< -6...0 dB   - limiter ceiling (dBTP when TruePeak is on, else dBFS)
    EmberParamMatch = 4,      ///< 0/1         - loudness-match (only ever turns down)
    EmberParamTruePeak = 5,   ///< 0/1         - limit inter-sample (true) peaks, not just samples
} EmberParam;

#define EMBER_PARAMETER_COUNT 6

static inline float EmberParamDefaultValue(EmberParam parameter) {
    switch (parameter) {
        case EmberParamAmount: return 45.0f;
        case EmberParamInputGain: return 0.0f;
        case EmberParamOutputGain: return 0.0f;
        case EmberParamCeiling: return -0.3f;
        case EmberParamMatch: return 0.0f;
        case EmberParamTruePeak: return 1.0f;
    }
    return 0.0f;
}

#endif /* EmberParameterAddresses_h */

#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

#import "EmberParameterAddresses.h"

NS_ASSUME_NONNULL_BEGIN

/// Meter values accumulated since the previous `-consumeMeters` call.
typedef struct EmberMeterSnapshot {
    float inputPeak;                 ///< linear
    float outputPeakLeft;            ///< linear
    float outputPeakRight;           ///< linear
    float compressorGainReductionDb; ///< <= 0
    float limiterGainReductionDb;    ///< <= 0
} EmberMeterSnapshot;

/// The Ember AUv3 effect. Rendering happens in a C++ kernel; this class only bridges it to
/// the Audio Unit API. AUAudioUnit is designed to be used across threads, so it is Sendable.
NS_SWIFT_SENDABLE
@interface EmberAudioUnit : AUAudioUnit

/// Thread-safe. Intended for UI meter polling.
- (EmberMeterSnapshot)consumeMeters;

@end

NS_ASSUME_NONNULL_END

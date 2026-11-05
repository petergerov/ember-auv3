#import "EmberAudioUnit.h"

#import <AVFoundation/AVFoundation.h>

#include "../DSP/EmberDSP.hpp"

#include <algorithm>
#include <memory>

namespace {

/// Render-thread view of resources owned by the Audio Unit. Filled in allocateRenderResources.
struct RenderResources {
    AudioBufferList *inputList = nullptr;
    AUAudioFrameCount maxFrames = 0;
    UInt32 channelCount = 0;
};

NSString *const kEmberParametersStateKey = @"ember.parameters";

struct FactoryPreset {
    NSString *name;
    float amount;
};

const FactoryPreset kFactoryPresets[] = {
    {@"Glow", 20.0f},
    {@"Warm", 45.0f},
    {@"Hot", 70.0f},
    {@"Blaze", 95.0f},
};

AUParameter *MakeParameter(NSString *identifier, NSString *name, EmberParam address, AUValue min, AUValue max,
                           AudioUnitParameterUnit unit, BOOL canRamp) {
    AudioUnitParameterOptions flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
    if (canRamp) {
        flags |= kAudioUnitParameterFlag_CanRamp;
    }
    AUParameter *parameter = [AUParameterTree createParameterWithIdentifier:identifier
                                                                       name:name
                                                                    address:address
                                                                        min:min
                                                                        max:max
                                                                       unit:unit
                                                                   unitName:nil
                                                                      flags:flags
                                                               valueStrings:nil
                                                        dependentParameters:nil];
    parameter.value = EmberParamDefaultValue(address);
    return parameter;
}

void ApplyRenderEvent(ember::EmberKernel *kernel, const AURenderEvent *event) {
    switch (event->head.eventType) {
        case AURenderEventParameter:
        case AURenderEventParameterRamp:
            // Ramps jump to the target; the kernel's smoothers provide the glide.
            kernel->setParameter(event->parameter.parameterAddress, event->parameter.value);
            break;
        default:
            break;
    }
}

/// Splits the buffer at event timestamps so parameter changes are sample-accurate.
void RenderWithEvents(ember::EmberKernel *kernel, const AudioTimeStamp *timestamp, AUAudioFrameCount frameCount,
                      const AURenderEvent *events, const AudioBufferList *input, AudioBufferList *output,
                      UInt32 channelCount) {
    const AUEventSampleTime now = static_cast<AUEventSampleTime>(timestamp->mSampleTime);
    AUAudioFrameCount done = 0;
    while (done < frameCount) {
        while (events != nullptr && events->head.eventSampleTime <= now + done) {
            ApplyRenderEvent(kernel, events);
            events = events->head.next;
        }
        AUAudioFrameCount segmentEnd = frameCount;
        if (events != nullptr) {
            const AUEventSampleTime offset = events->head.eventSampleTime - now;
            segmentEnd = static_cast<AUAudioFrameCount>(std::min<AUEventSampleTime>(offset, frameCount));
        }

        const float *inputs[ember::EmberKernel::kMaxChannels] = {};
        float *outputs[ember::EmberKernel::kMaxChannels] = {};
        for (UInt32 channel = 0; channel < channelCount; ++channel) {
            inputs[channel] = static_cast<const float *>(input->mBuffers[channel].mData) + done;
            outputs[channel] = static_cast<float *>(output->mBuffers[channel].mData) + done;
        }
        kernel->process(inputs, outputs, static_cast<int>(channelCount), static_cast<int>(segmentEnd - done));
        done = segmentEnd;
    }
}

} // namespace

@implementation EmberAudioUnit {
    std::unique_ptr<ember::EmberKernel> _kernel;
    std::unique_ptr<RenderResources> _render;
    AUAudioUnitBus *_inputBus;
    AUAudioUnitBus *_outputBus;
    AUAudioUnitBusArray *_inputBusArray;
    AUAudioUnitBusArray *_outputBusArray;
    AVAudioPCMBuffer *_inputBuffer;
    AUParameterTree *_parameterTree;
    NSArray<AUAudioUnitPreset *> *_factoryPresets;
    AUAudioUnitPreset *_currentPreset;
}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (self == nil) {
        return nil;
    }

    _kernel = std::make_unique<ember::EmberKernel>();
    _render = std::make_unique<RenderResources>();

    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000.0 channels:2];
    _inputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:outError];
    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:outError];
    if (_inputBus == nil || _outputBus == nil) {
        return nil;
    }
    _inputBus.maximumChannelCount = 2;
    _outputBus.maximumChannelCount = 2;
    _inputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                            busType:AUAudioUnitBusTypeInput
                                                             busses:@[ _inputBus ]];
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                             busType:AUAudioUnitBusTypeOutput
                                                              busses:@[ _outputBus ]];

    [self setUpParameterTree];
    [self setUpFactoryPresets];
    return self;
}

- (void)setUpParameterTree {
    NSArray<AUParameter *> *parameters = @[
        MakeParameter(@"amount", @"Amount", EmberParamAmount, 0, 100, kAudioUnitParameterUnit_Percent, YES),
        MakeParameter(@"input", @"Input", EmberParamInputGain, -12, 12, kAudioUnitParameterUnit_Decibels, YES),
        MakeParameter(@"output", @"Output", EmberParamOutputGain, -12, 12, kAudioUnitParameterUnit_Decibels, YES),
        MakeParameter(@"ceiling", @"Ceiling", EmberParamCeiling, -6, 0, kAudioUnitParameterUnit_Decibels, YES),
        MakeParameter(@"match", @"Match", EmberParamMatch, 0, 1, kAudioUnitParameterUnit_Boolean, NO),
        MakeParameter(@"truePeak", @"True Peak", EmberParamTruePeak, 0, 1, kAudioUnitParameterUnit_Boolean, NO),
    ];
    _parameterTree = [AUParameterTree createTreeWithChildren:parameters];

    // The tree outlives neither the kernel nor this object, so a raw pointer is safe here.
    ember::EmberKernel *kernel = _kernel.get();
    _parameterTree.implementorValueObserver = ^(AUParameter *parameter, AUValue value) {
        kernel->setParameter(parameter.address, value);
    };
    _parameterTree.implementorValueProvider = ^AUValue(AUParameter *parameter) {
        return kernel->parameter(parameter.address);
    };
    _parameterTree.implementorStringFromValueCallback = ^NSString *(AUParameter *parameter, const AUValue *valuePtr) {
        const AUValue value = valuePtr != nullptr ? *valuePtr : parameter.value;
        switch (static_cast<EmberParam>(parameter.address)) {
            case EmberParamAmount:
                return [NSString stringWithFormat:@"%.0f%%", value];
            case EmberParamMatch:
            case EmberParamTruePeak:
                return value >= 0.5f ? @"On" : @"Off";
            case EmberParamCeiling:
                return [NSString stringWithFormat:@"%.1f %@", value,
                                                  kernel->parameter(EmberParamTruePeak) >= 0.5f ? @"dBTP" : @"dB"];
            case EmberParamInputGain:
            case EmberParamOutputGain:
                return [NSString stringWithFormat:@"%+.1f dB", value];
        }
        return [NSString stringWithFormat:@"%.2f", value];
    };
}

- (void)setUpFactoryPresets {
    NSMutableArray<AUAudioUnitPreset *> *presets = [NSMutableArray array];
    NSInteger number = 0;
    for (const FactoryPreset &factory : kFactoryPresets) {
        AUAudioUnitPreset *preset = [AUAudioUnitPreset new];
        preset.number = number++;
        preset.name = factory.name;
        [presets addObject:preset];
    }
    _factoryPresets = [presets copy];
    _currentPreset = _factoryPresets[1]; // "Warm" matches the default parameter values.
}

// MARK: - Busses and formats

- (AUAudioUnitBusArray *)inputBusses {
    return _inputBusArray;
}

- (AUAudioUnitBusArray *)outputBusses {
    return _outputBusArray;
}

- (NSArray<NSNumber *> *)channelCapabilities {
    return @[ @1, @1, @2, @2 ]; // mono -> mono, stereo -> stereo
}

- (AUParameterTree *)parameterTree {
    return _parameterTree;
}

// MARK: - Render resources

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }

    AVAudioFormat *inputFormat = _inputBus.format;
    AVAudioFormat *outputFormat = _outputBus.format;
    const BOOL supported = inputFormat.channelCount == outputFormat.channelCount && inputFormat.channelCount >= 1 &&
                           inputFormat.channelCount <= ember::EmberKernel::kMaxChannels &&
                           inputFormat.commonFormat == AVAudioPCMFormatFloat32 && !inputFormat.isInterleaved &&
                           outputFormat.commonFormat == AVAudioPCMFormatFloat32 && !outputFormat.isInterleaved;
    if (!supported) {
        if (outError != nullptr) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:kAudioUnitErr_FormatNotSupported userInfo:nil];
        }
        [super deallocateRenderResources];
        return NO;
    }

    _inputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inputFormat frameCapacity:self.maximumFramesToRender];
    _render->inputList = _inputBuffer.mutableAudioBufferList;
    _render->maxFrames = self.maximumFramesToRender;
    _render->channelCount = inputFormat.channelCount;
    _kernel->prepare(outputFormat.sampleRate, static_cast<int>(outputFormat.channelCount));
    return YES;
}

- (void)deallocateRenderResources {
    _render->inputList = nullptr;
    _render->maxFrames = 0;
    _inputBuffer = nil;
    [super deallocateRenderResources];
}

- (void)reset {
    [super reset];
    _kernel->reset();
}

- (AUInternalRenderBlock)internalRenderBlock {
    // Capture plain pointers only - never `self` - so the render thread does no Objective-C messaging.
    ember::EmberKernel *kernel = _kernel.get();
    RenderResources *resources = _render.get();

    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags, const AudioTimeStamp *timestamp,
                              AUAudioFrameCount frameCount, NSInteger outputBusNumber, AudioBufferList *outputData,
                              const AURenderEvent *realtimeEventListHead, AURenderPullInputBlock pullInputBlock) {
        (void)actionFlags;
        (void)outputBusNumber;
        AudioBufferList *inputList = resources->inputList;
        if (inputList == nullptr || pullInputBlock == nullptr) {
            return kAudioUnitErr_NoConnection;
        }
        if (frameCount > resources->maxFrames) {
            return kAudioUnitErr_TooManyFramesToProcess;
        }

        const UInt32 byteSize = frameCount * sizeof(float);
        for (UInt32 buffer = 0; buffer < inputList->mNumberBuffers; ++buffer) {
            inputList->mBuffers[buffer].mDataByteSize = byteSize;
        }
        AudioUnitRenderActionFlags pullFlags = 0;
        const AUAudioUnitStatus status = pullInputBlock(&pullFlags, timestamp, frameCount, 0, inputList);
        if (status != noErr) {
            return status;
        }

        // In-place rendering when the host gives us no output memory.
        for (UInt32 buffer = 0; buffer < outputData->mNumberBuffers; ++buffer) {
            if (outputData->mBuffers[buffer].mData == nullptr && buffer < inputList->mNumberBuffers) {
                outputData->mBuffers[buffer].mData = inputList->mBuffers[buffer].mData;
            }
            outputData->mBuffers[buffer].mDataByteSize = byteSize;
        }

        const UInt32 channelCount =
            std::min({resources->channelCount, inputList->mNumberBuffers, outputData->mNumberBuffers});
        RenderWithEvents(kernel, timestamp, frameCount, realtimeEventListHead, inputList, outputData, channelCount);
        return noErr;
    };
}

// MARK: - Properties

- (NSTimeInterval)latency {
    const double sampleRate = _kernel->sampleRate();
    return sampleRate > 0 ? _kernel->latencySamples() / sampleRate : 0;
}

- (NSTimeInterval)tailTime {
    return 0.3;
}

- (BOOL)shouldBypassEffect {
    return _kernel->isBypassed();
}

- (void)setShouldBypassEffect:(BOOL)shouldBypassEffect {
    _kernel->setBypassed(shouldBypassEffect);
}

- (BOOL)canProcessInPlace {
    return YES;
}

- (EmberMeterSnapshot)consumeMeters {
    const ember::MeterSnapshot meters = _kernel->consumeMeters();
    return EmberMeterSnapshot{meters.inputPeak, meters.outputPeakLeft, meters.outputPeakRight,
                              meters.compressorGainReductionDb, meters.limiterGainReductionDb};
}

// MARK: - Presets and state

- (NSArray<AUAudioUnitPreset *> *)factoryPresets {
    return _factoryPresets;
}

- (BOOL)supportsUserPresets {
    return YES;
}

- (AUAudioUnitPreset *)currentPreset {
    return _currentPreset;
}

- (void)setCurrentPreset:(AUAudioUnitPreset *)currentPreset {
    if (currentPreset == nil) {
        _currentPreset = nil;
        return;
    }
    if (currentPreset.number >= 0) {
        for (AUAudioUnitPreset *factory in _factoryPresets) {
            if (factory.number == currentPreset.number) {
                for (AUParameter *parameter in _parameterTree.allParameters) {
                    parameter.value = EmberParamDefaultValue(static_cast<EmberParam>(parameter.address));
                }
                [_parameterTree parameterWithAddress:EmberParamAmount].value =
                    kFactoryPresets[factory.number].amount;
                _currentPreset = factory;
                return;
            }
        }
        return;
    }
    // User preset: only load ones that actually exist. -presetStateFor: throws (rather than
    // failing with an error) for unknown presets, which would take down the extension process.
    AUAudioUnitPreset *match = nil;
    for (AUAudioUnitPreset *user in self.userPresets) {
        if (user.number == currentPreset.number && [user.name isEqualToString:currentPreset.name]) {
            match = user;
            break;
        }
    }
    if (match == nil) {
        return;
    }
    NSDictionary<NSString *, id> *state = nil;
    @try {
        NSError *error = nil;
        state = [self presetStateFor:match error:&error];
    } @catch (NSException *exception) {
        state = nil;
    }
    if (state != nil) {
        self.fullState = state;
        _currentPreset = match;
    }
}

- (NSDictionary<NSString *, id> *)fullState {
    NSMutableDictionary<NSString *, id> *state = [[super fullState] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *values = [NSMutableDictionary dictionary];
    for (AUParameter *parameter in _parameterTree.allParameters) {
        values[parameter.identifier] = @(parameter.value);
    }
    state[kEmberParametersStateKey] = values;
    return state;
}

- (void)setFullState:(NSDictionary<NSString *, id> *)fullState {
    [super setFullState:fullState];
    NSDictionary *values = fullState[kEmberParametersStateKey];
    if (![values isKindOfClass:NSDictionary.class]) {
        return;
    }
    for (AUParameter *parameter in _parameterTree.allParameters) {
        NSNumber *value = values[parameter.identifier];
        if ([value isKindOfClass:NSNumber.class]) {
            parameter.value = value.floatValue;
        }
    }
}

@end

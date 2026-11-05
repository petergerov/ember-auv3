// Ember - one-knob warm mastering processor.
// Pure C++ (no Apple frameworks) so it can be unit-tested with a plain compiler.
//
// Signal flow (per sample, stereo-linked):
//   input trim -> DC block -> tone (low shelf / mud dip / air shelf) -> glue compressor
//   -> 4x oversampled asymmetric tanh saturation -> DC block -> M/S width
//   -> push into lookahead brickwall limiter (true-peak or sample-peak) -> loudness match -> output trim
//
// The Amount macro drives every stage through its own curve (see EmberKernel::updateControl).
// Real-time rules: process() never allocates, locks or blocks.

#pragma once

#include "../Bridge/EmberParameterAddresses.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <vector>

#if defined(__x86_64__)
#include <xmmintrin.h>
#endif

namespace ember {

inline constexpr double kPi = 3.14159265358979323846;
inline constexpr double kTwoPi = 2.0 * kPi;

inline float dbToGain(float db) noexcept { return std::pow(10.0f, db * 0.05f); }
inline float gainToDb(float gain) noexcept { return 20.0f * std::log10(std::max(gain, 1.0e-9f)); }

/// Flushes denormals to zero for the lifetime of the object (render thread only).
class ScopedFlushDenormals {
public:
    ScopedFlushDenormals() noexcept {
#if defined(__aarch64__)
        uint64_t fpcr = 0;
        asm volatile("mrs %0, fpcr" : "=r"(fpcr));
        saved_ = fpcr;
        asm volatile("msr fpcr, %0" ::"r"(fpcr | (uint64_t(1) << 24)));
#elif defined(__x86_64__)
        saved_ = _mm_getcsr();
        _mm_setcsr(static_cast<unsigned>(saved_) | 0x8040u);
#endif
    }
    ~ScopedFlushDenormals() noexcept {
#if defined(__aarch64__)
        asm volatile("msr fpcr, %0" ::"r"(saved_));
#elif defined(__x86_64__)
        _mm_setcsr(static_cast<unsigned>(saved_));
#endif
    }
    ScopedFlushDenormals(const ScopedFlushDenormals&) = delete;
    ScopedFlushDenormals& operator=(const ScopedFlushDenormals&) = delete;

private:
    uint64_t saved_ = 0;
};

/// One-pole exponential smoother for parameters.
class Smoother {
public:
    void prepare(double sampleRate, double timeSeconds) noexcept {
        coeff_ = static_cast<float>(std::exp(-1.0 / (timeSeconds * sampleRate)));
    }
    void snap(float value) noexcept { current_ = target_ = value; }
    void snapToTarget() noexcept { current_ = target_; }
    void setTarget(float value) noexcept { target_ = value; }
    float next() noexcept {
        current_ = target_ + coeff_ * (current_ - target_);
        return current_;
    }
    float current() const noexcept { return current_; }

private:
    float coeff_ = 0.0f;
    float current_ = 0.0f;
    float target_ = 0.0f;
};

// MARK: - Filters

struct BiquadCoefficients {
    float b0 = 1.0f, b1 = 0.0f, b2 = 0.0f, a1 = 0.0f, a2 = 0.0f;

    // RBJ Audio EQ Cookbook designs.
    static BiquadCoefficients lowShelf(double sampleRate, double frequency, double gainDb, double q) noexcept {
        const auto [A, cosw, alpha] = common(sampleRate, frequency, gainDb, q);
        const double sqrtA2alpha = 2.0 * std::sqrt(A) * alpha;
        return normalized(A * ((A + 1) - (A - 1) * cosw + sqrtA2alpha),
                          2 * A * ((A - 1) - (A + 1) * cosw),
                          A * ((A + 1) - (A - 1) * cosw - sqrtA2alpha),
                          (A + 1) + (A - 1) * cosw + sqrtA2alpha,
                          -2 * ((A - 1) + (A + 1) * cosw),
                          (A + 1) + (A - 1) * cosw - sqrtA2alpha);
    }

    static BiquadCoefficients highShelf(double sampleRate, double frequency, double gainDb, double q) noexcept {
        const auto [A, cosw, alpha] = common(sampleRate, frequency, gainDb, q);
        const double sqrtA2alpha = 2.0 * std::sqrt(A) * alpha;
        return normalized(A * ((A + 1) + (A - 1) * cosw + sqrtA2alpha),
                          -2 * A * ((A - 1) + (A + 1) * cosw),
                          A * ((A + 1) + (A - 1) * cosw - sqrtA2alpha),
                          (A + 1) - (A - 1) * cosw + sqrtA2alpha,
                          2 * ((A - 1) - (A + 1) * cosw),
                          (A + 1) - (A - 1) * cosw - sqrtA2alpha);
    }

    static BiquadCoefficients peak(double sampleRate, double frequency, double gainDb, double q) noexcept {
        const auto [A, cosw, alpha] = common(sampleRate, frequency, gainDb, q);
        return normalized(1 + alpha * A, -2 * cosw, 1 - alpha * A, 1 + alpha / A, -2 * cosw, 1 - alpha / A);
    }

private:
    struct Common {
        double A, cosw, alpha;
    };
    static Common common(double sampleRate, double frequency, double gainDb, double q) noexcept {
        const double f = std::min(frequency, 0.45 * sampleRate);
        const double w0 = kTwoPi * f / sampleRate;
        return {std::pow(10.0, gainDb / 40.0), std::cos(w0), std::sin(w0) / (2.0 * q)};
    }
    static BiquadCoefficients normalized(double b0, double b1, double b2, double a0, double a1, double a2) noexcept {
        return {static_cast<float>(b0 / a0), static_cast<float>(b1 / a0), static_cast<float>(b2 / a0),
                static_cast<float>(a1 / a0), static_cast<float>(a2 / a0)};
    }
};

/// Transposed direct form II state.
struct BiquadState {
    float z1 = 0.0f, z2 = 0.0f;
    void reset() noexcept { z1 = z2 = 0.0f; }
    float process(const BiquadCoefficients& c, float x) noexcept {
        const float y = c.b0 * x + z1;
        z1 = c.b1 * x - c.a1 * y + z2;
        z2 = c.b2 * x - c.a2 * y;
        return y;
    }
};

class DCBlocker {
public:
    void prepare(double sampleRate) noexcept { r_ = static_cast<float>(std::exp(-kTwoPi * 5.0 / sampleRate)); }
    void reset() noexcept { x1_ = y1_ = 0.0f; }
    float process(float x) noexcept {
        const float y = x - x1_ + r_ * y1_;
        x1_ = x;
        y1_ = y;
        return y;
    }

private:
    float r_ = 0.9995f, x1_ = 0.0f, y1_ = 0.0f;
};

class OnePoleLowpass {
public:
    void prepare(double sampleRate, double frequency) noexcept {
        k_ = static_cast<float>(1.0 - std::exp(-kTwoPi * frequency / sampleRate));
    }
    void reset() noexcept { y_ = 0.0f; }
    float process(float x) noexcept {
        y_ += k_ * (x - y_);
        return y_;
    }

private:
    float k_ = 0.0f, y_ = 0.0f;
};

// MARK: - Oversampling

namespace detail {

inline double besselI0(double x) noexcept {
    double sum = 1.0, term = 1.0;
    const double half = 0.5 * x;
    for (int k = 1; k < 64; ++k) {
        term *= (half / k) * (half / k);
        sum += term;
        if (term < 1.0e-12 * sum) {
            break;
        }
    }
    return sum;
}

/// Kaiser-windowed sinc lowpass at `cutoffScale` x the base-rate Nyquist for `factor`x oversampling,
/// unity DC gain.
/// With an odd tap count the zeros fall on every `factor`-th tap, so phase 0 of the derived
/// interpolator reproduces the original samples exactly.
template <int Taps>
std::array<double, Taps> designInterpolationLowpass(int factor, double beta, double cutoffScale = 1.0) noexcept {
    static_assert(Taps % 2 == 1, "odd length gives an integer group delay");
    const double cutoff = cutoffScale * 0.5 / factor; // cycles per oversampled sample
    const double centre = (Taps - 1) / 2.0;
    std::array<double, Taps> h{};
    double sum = 0.0;
    for (int n = 0; n < Taps; ++n) {
        const double t = n - centre;
        const double sinc = t == 0.0 ? 2.0 * cutoff : std::sin(kTwoPi * cutoff * t) / (kPi * t);
        const double ratio = t / centre;
        const double window = besselI0(beta * std::sqrt(std::max(0.0, 1.0 - ratio * ratio))) / besselI0(beta);
        h[n] = sinc * window;
        sum += h[n];
    }
    for (double& tap : h) {
        tap /= sum;
    }
    return h;
}

/// Splits a lowpass into `Factor` interpolation phases (scaled by Factor for zero-stuffing loss).
template <int Factor, int PhaseTaps, size_t Taps>
std::array<std::array<float, PhaseTaps>, Factor> polyphase(const std::array<double, Taps>& h) noexcept {
    std::array<std::array<float, PhaseTaps>, Factor> phases{};
    for (int p = 0; p < Factor; ++p) {
        for (int k = 0; k < PhaseTaps; ++k) {
            const size_t index = static_cast<size_t>(k * Factor + p);
            phases[p][k] = index < Taps ? static_cast<float>(Factor * h[index]) : 0.0f;
        }
    }
    return phases;
}

inline float dot(const float* a, const float* b, int count) noexcept {
    float acc = 0.0f;
    for (int i = 0; i < count; ++i) {
        acc += a[i] * b[i];
    }
    return acc;
}

} // namespace detail

/// 4x polyphase FIR oversampler (Kaiser-windowed sinc, ~80 dB stopband).
/// Latency is exactly kLatency samples at the base rate.
class Oversampler4x {
public:
    static constexpr int kFactor = 4;
    static constexpr int kTaps = 129;                          // odd -> integer group delay (64 OS samples)
    static constexpr int kPhaseTaps = (kTaps + kFactor - 1) / kFactor; // 33
    static constexpr int kLatency = (kTaps - 1) / kFactor;    // (64 + 64) / 4 = 32 base samples

    Oversampler4x() noexcept {
        const auto h = detail::designInterpolationLowpass<kTaps>(kFactor, 7.86); // ~80 dB
        for (int n = 0; n < kTaps; ++n) {
            decimator_[n] = static_cast<float>(h[n]);
        }
        interpolator_ = detail::polyphase<kFactor, kPhaseTaps>(h);
    }

    void reset() noexcept {
        inputHistory_.fill(0.0f);
        osHistory_.fill(0.0f);
        inputIndex_ = 0;
        osIndex_ = 0;
    }

    /// Upsamples one base-rate sample, runs `shaper` on each oversampled sample and returns one
    /// decimated base-rate sample (delayed by kLatency).
    template <typename Shaper>
    float process(float x, const Shaper& shaper) noexcept {
        inputIndex_ = inputIndex_ == 0 ? kPhaseTaps - 1 : inputIndex_ - 1;
        inputHistory_[inputIndex_] = x;
        inputHistory_[inputIndex_ + kPhaseTaps] = x;
        const float* recentInputs = &inputHistory_[inputIndex_];

        float output = 0.0f;
        for (int p = 0; p < kFactor; ++p) {
            const float upsampled = dot(interpolator_[p].data(), recentInputs, kPhaseTaps);
            const float shaped = shaper(upsampled);

            osIndex_ = osIndex_ == 0 ? kTaps - 1 : osIndex_ - 1;
            osHistory_[osIndex_] = shaped;
            osHistory_[osIndex_ + kTaps] = shaped;
            if (p == 0) {
                // Decimating on phase 0 keeps the total delay an integer number of base samples.
                output = dot(decimator_.data(), &osHistory_[osIndex_], kTaps);
            }
        }
        return output;
    }

private:
    using Phases = std::array<std::array<float, kPhaseTaps>, kFactor>;
    static float dot(const float* a, const float* b, int count) noexcept { return detail::dot(a, b, count); }

    Phases interpolator_{};
    std::array<float, kTaps> decimator_{};
    // Histories are stored twice so the newest-to-oldest window is always contiguous.
    std::array<float, 2 * kPhaseTaps> inputHistory_{};
    std::array<float, 2 * kTaps> osHistory_{};
    int inputIndex_ = 0;
    int osIndex_ = 0;
};

/// Stereo-linked inter-sample (true) peak estimator: polyphase interpolation in the spirit of
/// ITU-R BS.1770, but at 8x rather than 4x.
///
/// Each call reports the largest absolute value of the reconstructed waveform on the CLOSED
/// interval [n - kDelay, n - kDelay + 1]. In sample-peak mode it reports |x[n - kDelay]| only, with
/// the same delay, so the plugin latency doesn't change when the mode is switched.
///
/// Two things limit accuracy for content near Nyquist: passband droop (set by taps per phase) and
/// how far a peak can fall between grid points, cos(pi * f / (Factor * fs)). 4x with 24 taps per
/// phase under-reads up to ~0.5 dB on strong 19 kHz content at 44.1 kHz.
template <int Factor, int Taps, int BetaTimes10>
class TruePeakDetectorT {
public:
    static constexpr int kFactor = Factor;
    static constexpr int kTaps = Taps;
    static constexpr int kPhaseTaps = (kTaps + kFactor - 1) / kFactor;
    static constexpr int kDelay = (kTaps - 1) / 2 / kFactor; // base samples
    static_assert((kTaps - 1) % (2 * kFactor) == 0, "group delay must be a whole number of base samples");

    TruePeakDetectorT() noexcept {
        phases_ = detail::polyphase<kFactor, kPhaseTaps>(
            detail::designInterpolationLowpass<kTaps>(kFactor, BetaTimes10 / 10.0));
    }

    void reset() noexcept {
        left_.fill(0.0f);
        right_.fill(0.0f);
        index_ = 0;
    }

    float process(float left, float right, bool truePeak) noexcept {
        index_ = index_ == 0 ? kPhaseTaps - 1 : index_ - 1;
        left_[index_] = left_[index_ + kPhaseTaps] = left;
        right_[index_] = right_[index_ + kPhaseTaps] = right;
        const float* recentLeft = &left_[index_];
        const float* recentRight = &right_[index_];

        // Phase 0 is the delayed sample itself. In true-peak mode the interval is closed - both
        // endpoint samples are included - because the limiter applies this requirement to both of
        // them; without the right endpoint a peak just before it would only be seen one interval late.
        float peak = std::max(std::fabs(recentLeft[kDelay]), std::fabs(recentRight[kDelay]));
        if (truePeak) {
            peak = std::max(peak, std::max(std::fabs(recentLeft[kDelay - 1]), std::fabs(recentRight[kDelay - 1])));
            for (int p = 1; p < kFactor; ++p) {
                const float l = detail::dot(phases_[p].data(), recentLeft, kPhaseTaps);
                const float r = detail::dot(phases_[p].data(), recentRight, kPhaseTaps);
                peak = std::max(peak, std::max(std::fabs(l), std::fabs(r)));
            }
        }
        return peak;
    }

private:
    std::array<std::array<float, kPhaseTaps>, kFactor> phases_{};
    std::array<float, 2 * kPhaseTaps> left_{}, right_{};
    int index_ = 0;
};

/// 8x, 385 taps (48 per phase): 24 samples of delay, ~700 multiply-adds per stereo frame.
/// Measured (full chain, harsh 17/19 kHz material, 64 runs at 44.1/48 kHz, no margin): worst
/// overshoot +0.088 dB, vs +0.177 dB with 24 taps per phase (8x/193) and +0.138 dB with 16x/385.
using TruePeakDetector = TruePeakDetectorT<8, 385, 80>;

/// Asymmetric tanh waveshaper with unity small-signal gain, blended with the clean signal.
struct WarmShaper {
    float drive = 1.0f; // linear gain into the curve
    float bias = 0.0f;  // asymmetry -> even harmonics
    float biasTanh = 0.0f;
    float normalisation = 1.0f;
    float wet = 0.0f;

    void configure(float driveDb, float asymmetry, float wetAmount) noexcept {
        drive = dbToGain(driveDb);
        bias = asymmetry;
        biasTanh = std::tanh(bias);
        normalisation = 1.0f / (drive * (1.0f - biasTanh * biasTanh));
        wet = wetAmount;
    }

    float operator()(float x) const noexcept {
        const float shaped = (std::tanh(drive * x + bias) - biasTanh) * normalisation;
        return x + wet * (shaped - x);
    }
};

// MARK: - Dynamics

/// Feed-forward, stereo-linked "glue" compressor with a soft knee (gain computed in dB).
class GlueCompressor {
public:
    void prepare(double sampleRate) noexcept {
        attack_ = static_cast<float>(std::exp(-1.0 / (0.012 * sampleRate)));
        release_ = static_cast<float>(std::exp(-1.0 / (0.180 * sampleRate)));
        reset();
    }
    void reset() noexcept { envelopeDb_ = 0.0f; }
    void setCurve(float thresholdDb, float ratio, float kneeDb) noexcept {
        threshold_ = thresholdDb;
        slope_ = 1.0f / std::max(ratio, 1.0f) - 1.0f;
        knee_ = std::max(kneeDb, 0.01f);
    }
    /// Returns the linear gain to apply for the given detector level.
    float process(float detector) noexcept {
        const float over = gainToDb(detector) - threshold_;
        float target = 0.0f;
        if (2.0f * over <= -knee_) {
            target = 0.0f;
        } else if (2.0f * std::fabs(over) < knee_) {
            const float t = over + 0.5f * knee_;
            target = slope_ * t * t / (2.0f * knee_);
        } else {
            target = slope_ * over;
        }
        const float coeff = target < envelopeDb_ ? attack_ : release_;
        envelopeDb_ = target + coeff * (envelopeDb_ - target);
        return dbToGain(envelopeDb_);
    }
    float gainReductionDb() const noexcept { return envelopeDb_; }

private:
    float attack_ = 0.0f, release_ = 0.0f, envelopeDb_ = 0.0f;
    float threshold_ = 0.0f, slope_ = 0.0f, knee_ = 8.0f;
};

/// Stereo-linked lookahead brickwall limiter with optional true-peak detection.
///
/// Gain law: each detector value r[q] (required gain for the interval [q, q+1)) goes through a
/// min-hold of L + 1 samples and a box filter of L samples; the audio is delayed so that sample q
/// leaves after L - 1 samples. The hold window then spans both r[q-1] and r[q] for every box tap,
/// so the gain at sample q is <= the requirement of BOTH intervals touching it. Inter-sample peaks
/// are therefore bounded at the samples on either side, and the slowly varying gain keeps the
/// reconstructed waveform in between under the ceiling (verified against a 16x reference meter).
///
/// True-peak mode aims kTruePeakSafetyDb below the ceiling. That covers what remains: detector
/// error plus the small reconstruction error from a gain that changes during heavy limiting.
/// Worst measured overshoot without the margin is +0.088 dB, so the margin leaves ~0.06 dB spare.
class LookaheadLimiter {
public:
    static constexpr float kTruePeakSafetyDb = 0.15f;

    void prepare(double sampleRate, int lookaheadSamples) {
        lookahead_ = std::max(1, lookaheadSamples);
        required_.assign(static_cast<size_t>(lookahead_) + 1, 1.0f);
        box_.assign(lookahead_, 1.0f);
        const size_t delay = static_cast<size_t>(lookahead_) + TruePeakDetector::kDelay; // ring of size L + D
        delayLeft_.assign(delay, 0.0f);
        delayRight_.assign(delay, 0.0f);
        release_ = static_cast<float>(std::exp(-1.0 / (0.080 * sampleRate)));
        reset();
    }
    void reset() noexcept {
        std::fill(required_.begin(), required_.end(), 1.0f);
        std::fill(box_.begin(), box_.end(), 1.0f);
        std::fill(delayLeft_.begin(), delayLeft_.end(), 0.0f);
        std::fill(delayRight_.begin(), delayRight_.end(), 0.0f);
        detector_.reset();
        boxSum_ = static_cast<double>(lookahead_);
        envelope_ = 1.0f;
        requiredIndex_ = boxIndex_ = delayIndex_ = 0;
    }
    /// Detector delay + lookahead. The same in both detection modes.
    int latency() const noexcept { return TruePeakDetector::kDelay + lookahead_ - 1; }

    /// Processes one stereo frame in place and returns the applied linear gain.
    float process(float& left, float& right, float ceiling, bool truePeak) noexcept {
        const float peak = detector_.process(left, right, truePeak);
        const float target = truePeak ? ceiling * truePeakSafety_ : ceiling;
        required_[requiredIndex_] = peak > target ? target / peak : 1.0f;
        if (++requiredIndex_ == static_cast<int>(required_.size())) {
            requiredIndex_ = 0;
        }

        float held = 1.0f;
        for (const float value : required_) {
            held = std::min(held, value);
        }
        boxSum_ += static_cast<double>(held) - static_cast<double>(box_[boxIndex_]);
        box_[boxIndex_] = held;
        if (++boxIndex_ == lookahead_) {
            boxIndex_ = 0;
        }
        const float smoothed = static_cast<float>(boxSum_ / lookahead_);
        // Attack is handled by the box filter; release recovers from below, so envelope <= smoothed.
        envelope_ = smoothed < envelope_ ? smoothed : smoothed + release_ * (envelope_ - smoothed);

        // Ring of size L + D: the oldest entry was written L - 1 + D samples ago.
        delayLeft_[delayIndex_] = left;
        delayRight_[delayIndex_] = right;
        const int oldest = delayIndex_ + 1 == static_cast<int>(delayLeft_.size()) ? 0 : delayIndex_ + 1;
        left = std::clamp(delayLeft_[oldest] * envelope_, -ceiling, ceiling);
        right = std::clamp(delayRight_[oldest] * envelope_, -ceiling, ceiling);
        delayIndex_ = oldest;
        return envelope_;
    }

private:
    TruePeakDetector detector_;
    std::vector<float> required_, box_, delayLeft_, delayRight_;
    double boxSum_ = 1.0;
    float envelope_ = 1.0f, release_ = 0.0f;
    const float truePeakSafety_ = dbToGain(-kTruePeakSafetyDb);
    int lookahead_ = 1, requiredIndex_ = 0, boxIndex_ = 0, delayIndex_ = 0;
};

class DelayLine {
public:
    void prepare(int delaySamples) {
        delay_ = std::max(0, delaySamples);
        buffer_.assign(static_cast<size_t>(delay_) + 1, 0.0f);
        write_ = 0;
    }
    void reset() noexcept {
        std::fill(buffer_.begin(), buffer_.end(), 0.0f);
        write_ = 0;
    }
    float process(float x) noexcept {
        const int size = static_cast<int>(buffer_.size());
        buffer_[write_] = x;
        int read = write_ - delay_;
        if (read < 0) {
            read += size;
        }
        const float y = buffer_[read];
        if (++write_ == size) {
            write_ = 0;
        }
        return y;
    }

private:
    std::vector<float> buffer_{0.0f};
    int delay_ = 0, write_ = 0;
};

// MARK: - Kernel

struct MeterSnapshot {
    float inputPeak = 0.0f;
    float outputPeakLeft = 0.0f;
    float outputPeakRight = 0.0f;
    float compressorGainReductionDb = 0.0f; // <= 0
    float limiterGainReductionDb = 0.0f;    // <= 0
};

class EmberKernel {
public:
    static constexpr int kControlBlock = 32;
    static constexpr int kMaxChannels = 2;

    EmberKernel() {
        for (uint64_t address = 0; address < EMBER_PARAMETER_COUNT; ++address) {
            parameters_[address].store(EmberParamDefaultValue(static_cast<EmberParam>(address)));
        }
        prepare(48000.0, 2);
    }

    /// Not real-time safe (allocates). Call while rendering is stopped.
    void prepare(double sampleRate, int channelCount) {
        sampleRate_ = sampleRate;
        channels_ = std::clamp(channelCount, 1, kMaxChannels);

        limiter_.prepare(sampleRate, static_cast<int>(std::lround(0.0015 * sampleRate)));
        latency_ = Oversampler4x::kLatency + limiter_.latency();
        for (auto& delay : dryDelay_) {
            delay.prepare(latency_);
        }

        compressor_.prepare(sampleRate);
        for (int c = 0; c < kMaxChannels; ++c) {
            dcInput_[c].prepare(sampleRate);
            dcOutput_[c].prepare(sampleRate);
        }
        sideLowpass_.prepare(sampleRate, 150.0);

        amount_.prepare(sampleRate, 0.060);
        inputGain_.prepare(sampleRate, 0.030);
        outputGain_.prepare(sampleRate, 0.030);
        ceilingDb_.prepare(sampleRate, 0.030);
        bypassMix_.prepare(sampleRate, 0.015);
        matchGain_.prepare(sampleRate, 0.300);
        loudnessCoeff_ = std::exp(-1.0 / (1.2 * sampleRate));

        reset();
    }

    void reset() noexcept {
        for (int c = 0; c < kMaxChannels; ++c) {
            dcInput_[c].reset();
            dcOutput_[c].reset();
            lowShelfState_[c].reset();
            mudState_[c].reset();
            airState_[c].reset();
            oversamplers_[c].reset();
            dryDelay_[c].reset();
        }
        compressor_.reset();
        limiter_.reset();
        sideLowpass_.reset();
        inputEnergy_ = outputEnergy_ = 0.0;

        readParameterTargets();
        amount_.snapToTarget();
        inputGain_.snapToTarget();
        outputGain_.snapToTarget();
        ceilingDb_.snapToTarget();
        bypassMix_.snapToTarget();
        matchGain_.snap(1.0f);
        lastAmount_ = -1.0f;
        updateControl();
    }

    // Thread-safe: may be called from the UI thread or from render events.
    void setParameter(uint64_t address, float value) noexcept {
        if (address < EMBER_PARAMETER_COUNT) {
            parameters_[address].store(value, std::memory_order_relaxed);
        }
    }
    float parameter(uint64_t address) const noexcept {
        return address < EMBER_PARAMETER_COUNT ? parameters_[address].load(std::memory_order_relaxed) : 0.0f;
    }
    void setBypassed(bool bypassed) noexcept { bypassed_.store(bypassed, std::memory_order_relaxed); }
    bool isBypassed() const noexcept { return bypassed_.load(std::memory_order_relaxed); }

    int latencySamples() const noexcept { return latency_; }
    double sampleRate() const noexcept { return sampleRate_; }

    /// Real-time safe. `input` and `output` may point at the same buffers.
    void process(const float* const* input, float* const* output, int channelCount, int frameCount) noexcept {
        ScopedFlushDenormals noDenormals;
        readParameterTargets();
        const bool stereo = channelCount >= 2 && channels_ >= 2;

        float inputPeak = 0.0f, outputPeakLeft = 0.0f, outputPeakRight = 0.0f;
        float minCompressorDb = 0.0f, minLimiterGain = 1.0f;

        for (int start = 0; start < frameCount; start += kControlBlock) {
            const int end = std::min(frameCount, start + kControlBlock);
            updateControl();

            for (int i = start; i < end; ++i) {
                amount_.next();
                ceilingDb_.next();
                const float inGain = inputGain_.next();
                const float outGain = outputGain_.next();
                const float bypass = bypassMix_.next();
                const float match = matchGain_.next();

                const float dryLeft = input[0][i];
                const float dryRight = stereo ? input[1][i] : dryLeft;
                inputPeak = std::max(inputPeak, std::max(std::fabs(dryLeft), std::fabs(dryRight)));
                inputEnergy_ = loudnessCoeff_ * inputEnergy_ +
                               (1.0 - loudnessCoeff_) * 0.5 * (double(dryLeft) * dryLeft + double(dryRight) * dryRight);

                float left = dcInput_[0].process(dryLeft * inGain);
                float right = stereo ? dcInput_[1].process(dryRight * inGain) : left;

                left = airState_[0].process(air_, mudState_[0].process(mud_, lowShelfState_[0].process(lowShelf_, left)));
                if (stereo) {
                    right = airState_[1].process(air_, mudState_[1].process(mud_, lowShelfState_[1].process(lowShelf_, right)));
                } else {
                    right = left;
                }

                const float compressorGain = compressor_.process(std::max(std::fabs(left), std::fabs(right)));
                minCompressorDb = std::min(minCompressorDb, compressor_.gainReductionDb());
                left *= compressorGain;
                right *= compressorGain;

                left = dcOutput_[0].process(oversamplers_[0].process(left, shaper_));
                if (stereo) {
                    right = dcOutput_[1].process(oversamplers_[1].process(right, shaper_));

                    const float mid = 0.5f * (left + right);
                    const float side = 0.5f * (left - right);
                    const float sideLow = sideLowpass_.process(side);
                    const float widened = sideLow * lowSideGain_ + (side - sideLow) * highSideGain_;
                    left = mid + widened;
                    right = mid - widened;
                } else {
                    right = left;
                }

                left *= push_;
                right *= push_;
                minLimiterGain = std::min(minLimiterGain, limiter_.process(left, right, ceiling_, truePeak_));

                outputEnergy_ = loudnessCoeff_ * outputEnergy_ +
                                (1.0 - loudnessCoeff_) * 0.5 * (double(left) * left + double(right) * right);

                left *= match * outGain;
                right *= match * outGain;

                const float delayedLeft = dryDelay_[0].process(dryLeft);
                const float delayedRight = stereo ? dryDelay_[1].process(dryRight) : delayedLeft;
                left += bypass * (delayedLeft - left);
                right += bypass * (delayedRight - right);

                output[0][i] = left;
                outputPeakLeft = std::max(outputPeakLeft, std::fabs(left));
                if (stereo) {
                    output[1][i] = right;
                    outputPeakRight = std::max(outputPeakRight, std::fabs(right));
                } else {
                    outputPeakRight = outputPeakLeft;
                }
            }
        }

        atomicMax(meterInputPeak_, inputPeak);
        atomicMax(meterOutputLeft_, outputPeakLeft);
        atomicMax(meterOutputRight_, outputPeakRight);
        atomicMin(meterCompressorDb_, minCompressorDb);
        atomicMin(meterLimiterDb_, gainToDb(minLimiterGain));
    }

    /// Returns the meter values accumulated since the previous call. Thread-safe.
    MeterSnapshot consumeMeters() noexcept {
        MeterSnapshot snapshot;
        snapshot.inputPeak = meterInputPeak_.exchange(0.0f, std::memory_order_relaxed);
        snapshot.outputPeakLeft = meterOutputLeft_.exchange(0.0f, std::memory_order_relaxed);
        snapshot.outputPeakRight = meterOutputRight_.exchange(0.0f, std::memory_order_relaxed);
        snapshot.compressorGainReductionDb = meterCompressorDb_.exchange(0.0f, std::memory_order_relaxed);
        snapshot.limiterGainReductionDb = meterLimiterDb_.exchange(0.0f, std::memory_order_relaxed);
        return snapshot;
    }

private:
    static void atomicMax(std::atomic<float>& target, float value) noexcept {
        float current = target.load(std::memory_order_relaxed);
        while (value > current && !target.compare_exchange_weak(current, value, std::memory_order_relaxed)) {
        }
    }
    static void atomicMin(std::atomic<float>& target, float value) noexcept {
        float current = target.load(std::memory_order_relaxed);
        while (value < current && !target.compare_exchange_weak(current, value, std::memory_order_relaxed)) {
        }
    }

    void readParameterTargets() noexcept {
        amount_.setTarget(std::clamp(parameter(EmberParamAmount) / 100.0f, 0.0f, 1.0f));
        inputGain_.setTarget(dbToGain(parameter(EmberParamInputGain)));
        outputGain_.setTarget(dbToGain(parameter(EmberParamOutputGain)));
        ceilingDb_.setTarget(std::clamp(parameter(EmberParamCeiling), -24.0f, 0.0f));
        matchEnabled_ = parameter(EmberParamMatch) >= 0.5f;
        truePeak_ = parameter(EmberParamTruePeak) >= 0.5f;
        bypassMix_.setTarget(isBypassed() ? 1.0f : 0.0f);
    }

    /// The Amount macro: one value in [0, 1] mapped onto every stage. At 0 the chain is neutral
    /// apart from the ceiling limiter.
    void updateControl() noexcept {
        const float a = amount_.current();
        if (std::fabs(a - lastAmount_) > 1.0e-4f) {
            lastAmount_ = a;
            lowShelf_ = BiquadCoefficients::lowShelf(sampleRate_, 105.0, 3.0 * a, 0.7);  // weight
            mud_ = BiquadCoefficients::peak(sampleRate_, 320.0, -1.5 * a, 0.9);         // clear the low mids
            air_ = BiquadCoefficients::highShelf(sampleRate_, 10000.0, 1.5 * a, 0.7);   // gentle sheen
            compressor_.setCurve(-10.0f - 10.0f * a, 1.0f + 1.5f * a, 8.0f);
            shaper_.configure(9.0f * a, 0.25f * a, std::min(1.0f, 2.0f * a));
            lowSideGain_ = 1.0f - 0.4f * a;  // tighter, more mono low end
            highSideGain_ = 1.0f + 0.25f * a; // wider top
            push_ = dbToGain(8.0f * a);       // drive into the limiter
        }
        ceiling_ = dbToGain(ceilingDb_.current());

        if (!matchEnabled_) {
            matchGain_.setTarget(1.0f);
        } else if (inputEnergy_ > 1.0e-10 && outputEnergy_ > 1.0e-10) {
            // Only ever turns down, so the ceiling stays a hard guarantee.
            const float gain = static_cast<float>(std::sqrt(inputEnergy_ / outputEnergy_));
            matchGain_.setTarget(std::clamp(gain, dbToGain(-24.0f), 1.0f));
        }
    }

    std::array<std::atomic<float>, EMBER_PARAMETER_COUNT> parameters_{};
    std::atomic<bool> bypassed_{false};

    double sampleRate_ = 48000.0;
    int channels_ = 2;
    int latency_ = 0;

    Smoother amount_, inputGain_, outputGain_, ceilingDb_, bypassMix_, matchGain_;
    bool matchEnabled_ = false;
    bool truePeak_ = true;
    float lastAmount_ = -1.0f;

    BiquadCoefficients lowShelf_, mud_, air_;
    std::array<BiquadState, kMaxChannels> lowShelfState_{}, mudState_{}, airState_{};
    std::array<DCBlocker, kMaxChannels> dcInput_{}, dcOutput_{};
    std::array<Oversampler4x, kMaxChannels> oversamplers_{};
    std::array<DelayLine, kMaxChannels> dryDelay_{};
    GlueCompressor compressor_;
    WarmShaper shaper_;
    OnePoleLowpass sideLowpass_;
    LookaheadLimiter limiter_;

    float lowSideGain_ = 1.0f, highSideGain_ = 1.0f, push_ = 1.0f, ceiling_ = 1.0f;
    double loudnessCoeff_ = 0.0, inputEnergy_ = 0.0, outputEnergy_ = 0.0;

    std::atomic<float> meterInputPeak_{0.0f}, meterOutputLeft_{0.0f}, meterOutputRight_{0.0f};
    std::atomic<float> meterCompressorDb_{0.0f}, meterLimiterDb_{0.0f};
};

} // namespace ember

// Standalone DSP tests: Scripts/run-dsp-tests.sh
#include "../AudioUnit/DSP/EmberDSP.hpp"

#include <cstdio>
#include <random>
#include <string>
#include <vector>

using ember::EmberKernel;

namespace {

int failures = 0;

void check(bool condition, const std::string& name, const std::string& detail = {}) {
    std::printf("%s  %s%s%s\n", condition ? "PASS" : "FAIL", name.c_str(), detail.empty() ? "" : "  - ", detail.c_str());
    if (!condition) {
        ++failures;
    }
}

struct Stereo {
    std::vector<float> left, right;
    explicit Stereo(size_t n) : left(n, 0.0f), right(n, 0.0f) {}
};

/// Runs `in` through the kernel in host-sized blocks.
Stereo render(EmberKernel& kernel, const Stereo& in, int block = 512) {
    Stereo out(in.left.size());
    for (size_t start = 0; start < in.left.size(); start += block) {
        const int frames = static_cast<int>(std::min<size_t>(block, in.left.size() - start));
        const float* inputs[2] = {in.left.data() + start, in.right.data() + start};
        float* outputs[2] = {out.left.data() + start, out.right.data() + start};
        kernel.process(inputs, outputs, 2, frames);
    }
    return out;
}

Stereo sine(size_t n, double sampleRate, double frequency, float amplitude) {
    Stereo s(n);
    for (size_t i = 0; i < n; ++i) {
        s.left[i] = s.right[i] = amplitude * static_cast<float>(std::sin(ember::kTwoPi * frequency * i / sampleRate));
    }
    return s;
}

double rms(const std::vector<float>& x, size_t from) {
    double sum = 0.0;
    for (size_t i = from; i < x.size(); ++i) {
        sum += double(x[i]) * x[i];
    }
    return std::sqrt(sum / double(x.size() - from));
}

float peak(const std::vector<float>& x, size_t from) {
    float p = 0.0f;
    for (size_t i = from; i < x.size(); ++i) {
        p = std::max(p, std::fabs(x[i]));
    }
    return p;
}

bool allFinite(const Stereo& s) {
    for (size_t i = 0; i < s.left.size(); ++i) {
        if (!std::isfinite(s.left[i]) || !std::isfinite(s.right[i])) {
            return false;
        }
    }
    return true;
}

EmberKernel& prepared(EmberKernel& kernel, double sampleRate, float amount) {
    kernel.setParameter(EmberParamAmount, amount);
    kernel.prepare(sampleRate, 2);
    return kernel;
}

/// Independent reference meter: 16x band-limited reconstruction with a long (128-tap) Kaiser sinc,
/// evaluated directly (no shared code with the plugin's 4x detector). Returns dBTP.
double referenceTruePeakDb(const Stereo& s, size_t from) {
    constexpr int kHalf = 64;
    constexpr int kFactor = 16;
    constexpr double beta = 9.0;
    auto i0 = [](double x) {
        double sum = 1.0, term = 1.0;
        for (int k = 1; k < 80; ++k) {
            term *= (0.5 * x / k) * (0.5 * x / k);
            sum += term;
        }
        return sum;
    };
    std::vector<std::vector<double>> kernels(kFactor, std::vector<double>(2 * kHalf));
    for (int f = 0; f < kFactor; ++f) {
        const double frac = double(f) / kFactor;
        for (int k = -kHalf + 1; k <= kHalf; ++k) {
            const double t = frac - k;
            const double sinc = std::fabs(t) < 1e-12 ? 1.0 : std::sin(ember::kPi * t) / (ember::kPi * t);
            const double r = t / (kHalf + 0.5);
            kernels[f][k + kHalf - 1] = sinc * i0(beta * std::sqrt(std::max(0.0, 1.0 - r * r))) / i0(beta);
        }
    }
    double peak = 0.0;
    for (const auto* channel : {&s.left, &s.right}) {
        const auto& x = *channel;
        for (size_t n = std::max<size_t>(from, kHalf); n + kHalf < x.size(); ++n) {
            for (int f = 0; f < kFactor; ++f) {
                double acc = 0.0;
                for (int k = -kHalf + 1; k <= kHalf; ++k) {
                    acc += x[n + k] * kernels[f][k + kHalf - 1];
                }
                peak = std::max(peak, std::fabs(acc));
            }
        }
    }
    return 20.0 * std::log10(std::max(peak, 1e-12));
}

/// Quarter-sample-rate sine at 45 degrees: every sample lands at 0.707 of the true peak (+3 dB ISP).
Stereo interSampleTorture(size_t n, float amplitude) {
    Stereo s(n);
    for (size_t i = 0; i < n; ++i) {
        s.left[i] = amplitude * static_cast<float>(std::sin(ember::kPi * 0.5 * i + ember::kPi * 0.25));
        s.right[i] = -s.left[i];
    }
    return s;
}

/// Harsh but realistic "bright master": 55 Hz plus strong 17 kHz and 19 kHz tones and noise
/// band-limited to 19 kHz (real masters carry little energy above ~20 kHz).
Stereo brightProgram(size_t n, double sampleRate, unsigned seed) {
    constexpr int kTaps = 255;
    const auto lowpass = ember::detail::designInterpolationLowpass<kTaps>(1, 8.0, 19000.0 / (0.5 * sampleRate));
    std::mt19937 rng(seed);
    std::normal_distribution<float> noise(0.0f, 0.35f);
    std::vector<float> rawLeft(n + kTaps), rawRight(n + kTaps);
    for (size_t i = 0; i < rawLeft.size(); ++i) {
        rawLeft[i] = noise(rng);
        rawRight[i] = noise(rng);
    }
    Stereo s(n);
    for (size_t i = 0; i < n; ++i) {
        double left = 0.0, right = 0.0;
        for (int k = 0; k < kTaps; ++k) {
            left += lowpass[k] * rawLeft[i + k];
            right += lowpass[k] * rawRight[i + k];
        }
        const double t = i / sampleRate;
        const double tone = 0.5 * std::sin(ember::kTwoPi * 55.0 * t) + 0.25 * std::sin(ember::kTwoPi * 17000.0 * t) +
                            0.25 * std::sin(ember::kTwoPi * 19000.0 * t + 1.0);
        s.left[i] = static_cast<float>(tone + left);
        s.right[i] = static_cast<float>(tone + right);
    }
    return s;
}

} // namespace

int main() {
    constexpr double sr = 48000.0;

    { // Silence in -> silence out.
        EmberKernel kernel;
        prepared(kernel, sr, 100.0f);
        const Stereo out = render(kernel, Stereo(48000));
        check(peak(out.left, 0) == 0.0f && peak(out.right, 0) == 0.0f, "silence stays silent");
    }

    { // Reported latency matches the actual impulse delay.
        EmberKernel kernel;
        kernel.setParameter(EmberParamCeiling, 0.0f);
        prepared(kernel, sr, 0.0f);
        Stereo in(4096);
        in.left[1000] = in.right[1000] = 0.5f;
        const Stereo out = render(kernel, in);
        size_t argmax = 0;
        for (size_t i = 0; i < out.left.size(); ++i) {
            if (std::fabs(out.left[i]) > std::fabs(out.left[argmax])) {
                argmax = i;
            }
        }
        const long measured = long(argmax) - 1000;
        check(measured == kernel.latencySamples(), "latency matches report",
              "reported " + std::to_string(kernel.latencySamples()) + ", measured " + std::to_string(measured));
    }

    for (double rate : {44100.0, 48000.0, 96000.0, 192000.0}) { // Ceiling is never exceeded.
        EmberKernel kernel;
        kernel.setParameter(EmberParamInputGain, 12.0f);
        kernel.setParameter(EmberParamOutputGain, 0.0f);
        kernel.setParameter(EmberParamCeiling, -1.0f);
        prepared(kernel, rate, 100.0f);
        const size_t n = size_t(rate * 3);
        Stereo in = sine(n, rate, 60.0, 0.9f);
        std::mt19937 rng(7);
        std::normal_distribution<float> noise(0.0f, 0.3f);
        for (size_t i = 0; i < n; ++i) {
            in.left[i] += noise(rng);
            in.right[i] -= noise(rng);
        }
        const Stereo out = render(kernel, in);
        const float ceiling = ember::dbToGain(-1.0f);
        const float maxPeak = std::max(peak(out.left, 0), peak(out.right, 0));
        check(maxPeak <= ceiling * 1.00001f && allFinite(out), "ceiling holds @" + std::to_string(int(rate)) + " Hz",
              "peak " + std::to_string(ember::gainToDb(maxPeak)) + " dBFS");
    }

    { // Inter-sample torture signal: sample-peak mode lets ~3 dB of ISPs through, true-peak mode doesn't.
        auto run = [&](bool truePeak) {
            EmberKernel kernel;
            kernel.setParameter(EmberParamInputGain, 12.0f);
            kernel.setParameter(EmberParamCeiling, -1.0f);
            kernel.setParameter(EmberParamTruePeak, truePeak ? 1.0f : 0.0f);
            prepared(kernel, sr, 0.0f);
            return referenceTruePeakDb(render(kernel, interSampleTorture(size_t(sr), 0.9f)), size_t(sr / 2));
        };
        const double samplePeakMode = run(false);
        const double truePeakMode = run(true);
        check(samplePeakMode > 1.0, "sample-peak mode overshoots on ISPs (control)",
              std::to_string(samplePeakMode) + " dBTP");
        check(truePeakMode <= -1.0 + 0.005, "true-peak mode holds ceiling on ISP torture",
              std::to_string(truePeakMode) + " dBTP");
    }

    for (double rate : {44100.0, 48000.0, 96000.0, 192000.0}) { // Full chain, bright material, hard push.
        EmberKernel kernel;
        kernel.setParameter(EmberParamInputGain, 12.0f);
        kernel.setParameter(EmberParamCeiling, -1.0f);
        prepared(kernel, rate, 100.0f);
        const Stereo out = render(kernel, brightProgram(size_t(rate * 2), rate, 3));
        const double tp = referenceTruePeakDb(out, size_t(rate));
        check(tp <= -1.0 + 0.005, "true peak holds ceiling (full chain) @" + std::to_string(int(rate)) + " Hz",
              std::to_string(tp) + " dBTP");
    }

    { // Margin sweep: many harsh renders must all stay under the ceiling.
        double worst = -100.0;
        for (double rate : {44100.0, 48000.0}) {
            for (unsigned seed = 1; seed <= 8; ++seed) {
                for (float amount : {40.0f, 100.0f}) {
                    EmberKernel kernel;
                    kernel.setParameter(EmberParamInputGain, 12.0f);
                    kernel.setParameter(EmberParamCeiling, -1.0f);
                    prepared(kernel, rate, amount);
                    const Stereo out = render(kernel, brightProgram(size_t(rate * 1.2), rate, seed));
                    worst = std::max(worst, referenceTruePeakDb(out, size_t(rate * 0.5)));
                }
            }
        }
        check(worst <= -1.0, "true peak holds across 32 harsh renders", "worst " + std::to_string(worst) + " dBTP");
    }

    { // Amount 0 is (nearly) transparent below the ceiling.
        EmberKernel kernel;
        prepared(kernel, sr, 0.0f);
        const Stereo in = sine(96000, sr, 1000.0, 0.25f);
        const Stereo out = render(kernel, in);
        const double diffDb = 20.0 * std::log10(rms(out.left, 48000) / rms(in.left, 48000));
        check(std::fabs(diffDb) < 0.05, "amount 0 is level-transparent", std::to_string(diffDb) + " dB");
    }

    { // Amount adds level/density (it should sound "more").
        EmberKernel quiet, hot;
        prepared(quiet, sr, 0.0f);
        prepared(hot, sr, 100.0f);
        const Stereo in = sine(96000, sr, 220.0, 0.2f);
        const double gainDb = 20.0 * std::log10(rms(render(hot, in).left, 48000) / rms(render(quiet, in).left, 48000));
        check(gainDb > 3.0, "amount 100 is louder than amount 0", std::to_string(gainDb) + " dB");
    }

    { // Match brings the processed level back near the input.
        EmberKernel kernel;
        kernel.setParameter(EmberParamMatch, 1.0f);
        prepared(kernel, sr, 100.0f);
        const Stereo in = sine(size_t(sr * 8), sr, 220.0, 0.2f);
        const Stereo out = render(kernel, in);
        const double diffDb = 20.0 * std::log10(rms(out.left, size_t(sr * 6)) / rms(in.left, size_t(sr * 6)));
        check(std::fabs(diffDb) < 1.5, "match keeps loudness", std::to_string(diffDb) + " dB");
    }

    { // Bypass outputs the latency-aligned dry signal.
        EmberKernel kernel;
        kernel.setBypassed(true);
        prepared(kernel, sr, 100.0f);
        const Stereo in = sine(9600, sr, 440.0, 0.5f);
        const Stereo out = render(kernel, in);
        const int latency = kernel.latencySamples();
        float maxError = 0.0f;
        for (size_t i = 4800; i < in.left.size(); ++i) {
            maxError = std::max(maxError, std::fabs(out.left[i] - in.left[i - latency]));
        }
        check(maxError < 1.0e-6f, "bypass is latency-compensated dry", "max error " + std::to_string(maxError));
    }

    { // Mono path and odd block sizes.
        EmberKernel kernel;
        kernel.setParameter(EmberParamAmount, 80.0f);
        kernel.prepare(sr, 1);
        Stereo in = sine(20000, sr, 100.0, 0.8f);
        std::vector<float> out(in.left.size());
        for (size_t start = 0; start < in.left.size(); start += 37) {
            const int frames = int(std::min<size_t>(37, in.left.size() - start));
            const float* inputs[1] = {in.left.data() + start};
            float* outputs[1] = {out.data() + start};
            kernel.process(inputs, outputs, 1, frames);
        }
        bool finite = true;
        for (float v : out) finite = finite && std::isfinite(v);
        check(finite && peak(out, 0) <= ember::dbToGain(-0.3f) * 1.00001f, "mono path stays finite and under ceiling");
    }

    { // Extreme input never produces NaN/Inf.
        EmberKernel kernel;
        kernel.setParameter(EmberParamInputGain, 12.0f);
        prepared(kernel, sr, 100.0f);
        Stereo in(48000);
        for (size_t i = 0; i < in.left.size(); ++i) {
            in.left[i] = (i % 2 ? 1.0f : -1.0f) * 1000.0f;
            in.right[i] = i % 100 == 0 ? 1.0e30f : 1.0e-30f;
        }
        check(allFinite(render(kernel, in)), "extreme input stays finite");
    }

    std::printf("\n%s (%d failure%s)\n", failures == 0 ? "ALL PASSED" : "FAILED", failures, failures == 1 ? "" : "s");
    return failures == 0 ? 0 : 1;
}

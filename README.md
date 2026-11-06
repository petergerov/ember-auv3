# Ember

One-knob warm mastering — an AUv3 Audio Unit effect for macOS and iOS/iPadOS.

| | |
|---|---|
| AU type / subtype / manufacturer | `aufx` / `Embr` / `Grov` |
| Host name | **Gerov: Ember** |
| Parameters | Amount (0–100 %), Input (±12 dB), Output (±12 dB), Ceiling (−6…0 dB / dBTP), True Peak (on/off, default on), Match (on/off) |
| Factory presets | Glow 20 %, Warm 45 % (default), Hot 70 %, Blaze 95 % |
| Latency | 32 (4× saturation oversampler) + 24 (true-peak detector) + 1.5 ms lookahead − 1 samples = 127 @ 48 kHz; constant in both peak modes, reported to the host |
| CPU | ≈ 3.1 % of one Apple-silicon core @ 48 kHz stereo (true peak adds ≈ 0.8 %) |

## Signal flow

Input trim → DC block → tone (105 Hz low shelf, 320 Hz mud dip, 10 kHz air shelf) → stereo-linked
glue compressor → 4× oversampled asymmetric-tanh saturation → DC block → M/S width (tighter lows,
wider highs) → push into a lookahead limiter (true-peak or sample-peak) → loudness match → output trim.

**Amount** drives every stage on its own curve (`EmberKernel::updateControl` in
`AudioUnit/DSP/EmberDSP.hpp`). At 0 % the chain is neutral apart from the ceiling limiter.
**True Peak** (default on) runs the limiter's sidechain through an 8× polyphase interpolator
(385 taps) that measures the reconstructed waveform over each closed sample interval, so
inter-sample peaks are limited too. In this mode the limiter aims a fixed **0.15 dB safety margin**
below the ceiling, so the output never measurably exceeds it. Without the margin, the worst
overshoot measured across 64 harsh renders (strong 17/19 kHz content, up to +12 dB into the
chain) is +0.088 dB, so the margin leaves about 0.06 dB spare. Measured against an independent 16×
reference meter, the worst case is −1.06 dBTP for a −1.0 dBTP ceiling. In practice the true peak
lands about 0.06–0.15 dB below the Ceiling setting. Leave ≥ 0.3 dB of ceiling headroom for lossy
encoding anyway. With True Peak off the limiter is a strict sample-peak limiter, with no margin,
and a +3 dB inter-sample peak can get through.

**Match** compares long-term input and output energy and only ever turns the output *down*, so
the ceiling stays a hard limit.

## Layout

```
AudioUnit/DSP/      C++ kernel - no Apple frameworks, unit-testable
AudioUnit/Bridge/   EmberAudioUnit (Objective-C++ AUAudioUnit), parameter addresses, bridging header
AudioUnit/UI/       SwiftUI editor (@Observable @MainActor view models)
Extension/          AUv3 app extension entry point + Info.plist (AudioComponents)
App/                Container app (ships and registers the extension)
Tests/              Standalone DSP tests
```

## Build & test

```sh
brew install xcodegen          # once
cp .env.example .env           # once: fill in BUNDLE_ID (and TEAM_ID for iOS / installer)
Scripts/generate-project.sh    # generate Ember.xcodeproj from project.yml + .env
Scripts/run-dsp-tests.sh       # DSP tests (ceiling, true peak vs 16x reference, latency, transparency, match, bypass, mono, NaN safety)

xcodebuild -scheme Ember_macOS -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Ember.app   # registers the extension
auval -v aufx Embr Grov
```

iOS: open `Ember.xcodeproj`, pick the `Ember_iOS` scheme and run on a device with your development team.

Keep parameter **identifiers** (`amount`, `input`, …) stable: AUv2-bridged hosts derive their
parameter IDs from them, so renaming one breaks saved automation.

## Installer (macOS)

The installer also needs `TEAM_ID` and `DEVELOPER_NAME` (the name on your Developer ID
certificates) in `.env`.

```sh
Scripts/make-installer.sh                                  # -> dist/Ember-<version>.pkg, signed
NOTARY_PROFILE=ember-notary Scripts/make-installer.sh      # ...and notarized + stapled
```

The script runs the DSP tests, builds a universal (arm64 + x86_64) Release with the Developer ID
Application certificate, hardened runtime and secure timestamp, and verifies the signatures and
entitlements. It then packages `Ember.app` for `/Applications` (non-relocatable) and signs the
product with the Developer ID Installer certificate. A postinstall script registers the Audio
Unit for the logged-in user, so hosts see it without launching the app first. Installer pages
live in `Installer/`.

Notarization needs a keychain profile, created once:

```sh
xcrun notarytool store-credentials ember-notary --apple-id <apple-id> --team-id <team-id>
```

iOS/iPadOS ships through TestFlight / the App Store (Xcode → Product → Archive), not a `.pkg`.

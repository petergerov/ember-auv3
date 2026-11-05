# Reference analysis: Cradle "The God Particle" 1.2.4 (surface only)

Scope: bundle metadata, AU registration, linked frameworks, exported symbols,
RTTI class names, resource names. No disassembly/decompilation, and the
product's embedded Lua scripts (main.lua, coreAudioGraph.lua) were NOT read.
Purpose: understand the product category and architecture so we can design
our OWN plugin with our own DSP. Nothing below is code or coefficients.

## Identity
- AUv2 `aufx` / manufacturer `Crdl` / subtype `Tgpj`, v1.2.4, universal (x86_64 + arm64)
- Built on JUCE (`JuceAUFactory` + `TheGodParticleAUFactory` exports)
- Frameworks of note: Accelerate (vDSP/FFT), Metal/MetalKit (GUI), WebKit, Security/IOKit (licensing)

## Architecture
- One shared "Cradle engine" binary: a node-based C++ audio graph
  (`AudioGraph`, `AudioProcessorNode`, `OversampledAudioGraph`) driven by an
  embedded Lua runtime. Each product is mostly a Lua script that wires
  generic nodes together plus image resources.
- So the engine contains ~200 DSP node types, most unused by this product
  (sampler, chorus, BBD delay, etc.). Which ones TGP's graph uses is defined in
  its script; we did not read it.

## Mastering-relevant node types present in the engine
Oversampler, AsymmetricTanhWaveshaper, PolynomialWaveshaper, Clipper,
Distortion, tape saturation module, FeedforwardCompressor, FeedbackCompressor,
UpwardCompressor, Expander, Crossover + multiBand wrapper, DynamicShelvingFilter,
DynamicPeakingEqualizer, ParametricEnhancer, passive tilt EQ, StereoWidener,
SubharmonicSynthesizer, TransientShaper / SpectralTransientShaper, GainRider,
Maximizer, BrickwallLimiter, LoudnessMeter, LinearLoudnessGain, Convolution, DCBlocker.
Engine property names include: drive / driveAmount / driveShape, ceiling,
ceilingEnabled, clipperEnabled, autoMakeUpGainEnabled, dryGain.

## UI
- Three knobs (large, medium, small sprite images) on a baked backplate
- An animated 30 FPS sprite visualizer (color / white / off states)
- Gain-reduction meter component, preset browser, UI scaling menu

## Takeaways for our design
1. One macro knob that drives several stages at once through per-stage curves
2. Separate input and output trims
3. Oversampled nonlinear stages, then a brickwall limiter with a ceiling
4. Loudness-compensated output so turning the knob doesn't just sound "louder"

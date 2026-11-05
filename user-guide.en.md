# Ember – User Guide

**Ember** is a one-knob warm mastering effect (Audio Unit v3) for macOS and iOS/iPadOS.
A single control, **Amount**, drives a complete mastering chain: tone, compression, saturation,
stereo width and limiting. The rest of the interface is there for fine control.

---

## Contents

1. [Installation](#1-installation)
2. [The interface](#2-the-interface)
3. [What Amount does](#3-what-amount-does)
4. [Match – loudness matching](#4-match--loudness-matching)
5. [Ceiling and True Peak](#5-ceiling-and-true-peak)
6. [Meters](#6-meters)
7. [Presets](#7-presets)
8. [Workflow: a master in five steps](#8-workflow-a-master-in-five-steps)
9. [Specifications](#9-specifications)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Installation

**macOS:** double-click `Ember-<version>.pkg` and follow the installer. Ember.app is copied to
*Applications* and the plug-in is registered automatically. Then restart your host (Logic Pro,
GarageBand, Ableton Live, Reaper …). Ember appears under **Audio Units → Gerov → Ember**.

> If Ember doesn't show up, open **Ember** from the Applications folder once. This forces macOS
> to register the plug-in.

**iOS/iPadOS:** install the app and open it once. In AUM, Logic Pro for iPad, GarageBand and
other hosts you'll find Ember among the Audio Unit effects.

**Uninstalling (macOS):** drag Ember.app from *Applications* to the Trash.

---

## 2. The interface

```
 EMBER                                   [TRUE PEAK] [MATCH]

   (INPUT)            ( AMOUNT )             (OUTPUT)

 ┌──────────────────────────────────────────────────────────┐
 │ GLUE  ▬▬▬▬▬▬▬▬▬▬▬▬▬  -1.2      (CEILING)       ▌▌ OUT     │
 │ LIMIT ▬▬▬▬▬▬▬▬▬▬▬▬▬  -2.4                                  │
 └──────────────────────────────────────────────────────────┘
```

| Control | Range | Default | Function |
|---|---|---|---|
| **Amount** | 0–100 % | 45 % | The main control. Drives every stage at once (see [section 3](#3-what-amount-does)). |
| **Input** | −12 … +12 dB | 0 dB | Level *into* the chain. More input means more compression, saturation and limiting. |
| **Output** | −12 … +12 dB | 0 dB | Level at the very end, after the limiter. |
| **Ceiling** | −6 … 0 dB | −0.3 dB | Maximum output level of the limiter (in dBTP when True Peak is on). |
| **True Peak** | on/off | on | Also limits peaks *between* samples (see [section 5](#5-ceiling-and-true-peak)). |
| **Match** | on/off | off | Loudness matching for fair comparisons (see [section 4](#4-match--loudness-matching)). |

**Using the controls**

- **Drag** up or right to increase a value, down or left to decrease it.
- **Double-click** (or double-tap) a knob to reset it to its default.
- Every parameter can be automated in the host; dragging writes "touch" automation.
- With VoiceOver, every knob can be adjusted in 2 % steps with a swipe.

**Bypass** is handled by the host. Ember crossfades smoothly (15 ms) and outputs the dry signal
perfectly time-aligned, so switching never shifts the audio.

---

## 3. What Amount does

Amount is not a simple wet/dry control. Each stage of the chain follows its own curve. At
**0 %** Ember is tonally neutral; only the limiter catches peaks above the ceiling. At
**100 %** every stage works at full intensity.

Signal flow:

```
Input → Tone EQ → Glue compressor → Saturation (4× oversampled) → Stereo width → Limiter → Match → Output
```

| Stage | At 0 % | At 100 % | Effect |
|---|---|---|---|
| **Lows** (shelf 105 Hz) | 0 dB | +3 dB | Weight and foundation |
| **Mud cut** (320 Hz) | 0 dB | −1.5 dB | Less muddiness in the low mids |
| **Air** (shelf 10 kHz) | 0 dB | +1.5 dB | Subtle sheen |
| **Glue compressor** | 1:1 (off) | 2.5:1 from −20 dB | Gently glues the mix (soft knee 8 dB, attack 12 ms, release 180 ms) |
| **Saturation** | off | +9 dB drive, fully wet | Warm, slightly asymmetric tube character – even harmonics |
| **Stereo width** | neutral | lows < 150 Hz −40 % side, highs +25 % side | Tighter, mono-solid low end; wider top |
| **Push into the limiter** | 0 dB | +8 dB | Loudness |

Saturation reaches its full wet amount at 50 %. Above that, only the drive increases.

**Rules of thumb**

- **20–35 %** – light polish, barely audible compression
- **40–60 %** – clearly warmer and denser; a typical master
- **70–100 %** – loud, saturated, aggressive; keep an eye on the gain-reduction meters

---

## 4. Match – loudness matching

### The problem

Louder almost always sounds "better". Turning up Amount makes the signal noticeably louder (up to
+8 dB of push, plus compression and saturation). A direct comparison with the original is then
unfair: what you mostly hear is the level difference, not whether Ember actually improves the
sound.

### What Match does

With **Match** on, Ember automatically turns the output down so that the processed signal is
**about as loud as the input**. You then hear only the *tonal* change (warmth, density, width),
not the loudness.

### How it works

1. Ember continuously measures the **average energy (RMS)** of the signal at two points:
   - at the **input**, *before* the Input control
   - at the **limiter output**, *before* the Output control
2. Both measurements are smoothed over about **1.2 seconds**, so individual transients don't
   affect the match.
3. Their ratio gives a correction that follows smoothly over about **300 ms**. There are no jumps
   and no pumping.
4. The correction is applied **after the limiter**. The Output control then works as usual.

### Important details

- **Match only turns down, never up** (range 0 to −24 dB). This keeps the ceiling a hard limit.
  If the processed signal is quieter than the original (e.g. with Input at −12 dB), Match does
  nothing.
- **Match also cancels out the Input control.** Because the input is measured *before* the Input
  control, loudness stays the same with Match on, however much input you give. You hear only how
  the harder drive *sounds* in compression and saturation.
- **Match measures RMS, not LUFS.** That's plenty for listening comparisons. For a reliable
  loudness reading (e.g. −14 LUFS for streaming), use a LUFS meter in your host.
- After switching Match on, it needs **1–2 seconds of music** to settle.
- During pauses and silence the last correction is held.

### How to use Match

1. **Turn Match on.**
2. Set Amount (and Input, if needed) while comparing with the **host's bypass**. Both versions are
   now about equally loud. Decide by sound: is it really better?
3. **Turn Match off before exporting!** Otherwise the master won't be any louder than the
   original, and Ember's loudness gain is lost.

> **Rule of thumb:** Match is a tool for *listening*, not for *exporting*.

---

## 5. Ceiling and True Peak

**Ceiling** sets the maximum output level. The limiter uses 1.5 ms of lookahead: it sees peaks
before they arrive and reduces gain without audible clicks.

### True Peak (default: on)

Digital samples are only measurement points. The actual waveform reconstructed by a D/A converter
or an MP3/AAC decoder can rise **between** two samples – in extreme cases by more than 3 dB.
These *inter-sample peaks* cause distortion on playback and when streaming services encode your
track.

- **True Peak on:** Ember reconstructs the waveform internally with 8× oversampling and limits the
  peaks between samples as well. The Ceiling readout switches to **dBTP**. Ember aims a fixed
  **safety margin of 0.15 dB** below the ceiling. The actual true peak therefore usually sits
  0.06–0.15 dB below the set value. In return, the ceiling is not exceeded even on extremely
  bright material.
- **True Peak off:** the limiter only limits sample values, exactly at the ceiling with no margin.
  This is very slightly louder, but inter-sample peaks can get through.

**Recommendations**

| Target | Ceiling | True Peak |
|---|---|---|
| Streaming (Spotify, Apple Music, YouTube …) | −1.0 dB | on |
| CD / WAV master | −0.3 dB | on |
| Further processing (stems, mastering engineer) | −1.0 dB or lower | on |

Latency is the same in both modes, so switching never shifts anything in your host.

---

## 6. Meters

| Meter | Shows | Scale |
|---|---|---|
| **GLUE** | Gain reduction of the glue compressor | 0–12 dB |
| **LIMIT** | Gain reduction of the limiter | 0–12 dB |
| **OUT** | Output level left/right (sample peak) | −48 … 0 dBFS |

The sparks behind the Amount knob are a visualisation: their number follows Amount, their
brightness follows the output level.

**Guidelines:**

- **GLUE** around 1–3 dB: healthy compression. Much more than that all the time quickly sounds
  flat.
- **LIMIT** briefly at 2–4 dB on peaks: unobtrusive. If LIMIT stays above 6 dB, it becomes
  audible. Back off Input or Amount.
- The OUT meter shows sample peaks. Use your host's meter to check true peak and LUFS.

---

## 7. Presets

| Preset | Amount | Character |
|---|---|---|
| **Glow** | 20 % | Subtle polish |
| **Warm** | 45 % | Default – warm and dense |
| **Hot** | 70 % | Loud and strongly saturated |
| **Blaze** | 95 % | Maximum – for aggressive genres |

Factory presets reset all other parameters to their defaults (Input/Output 0 dB, Ceiling −0.3 dB,
True Peak on, Match off). Save your own presets with your host's preset dialog.

---

## 8. Workflow: a master in five steps

1. **Put Ember last** on the master bus. Leave headroom in the mix (peaks around −6 dBFS).
2. **Turn Match on.** Slowly raise Amount and compare with bypass until the sound fits best.
3. **Adjust Input:** more input gives more density and bite. Keep an eye on GLUE and LIMIT.
4. **Set Ceiling** for your target (see [section 5](#5-ceiling-and-true-peak)) and leave True Peak
   on.
5. **Turn Match off**, check the target loudness with a LUFS meter, and export.

---

## 9. Specifications

| | |
|---|---|
| Format | Audio Unit v3 (effect), macOS 14+ (Apple silicon and Intel), iOS/iPadOS 17+ |
| Channels | Mono → mono, stereo → stereo |
| Sample rates | All common rates (tested from 11.025 to 192 kHz) |
| Latency | 127 samples at 48 kHz (≈ 2.6 ms), reported to the host and compensated automatically |
| Oversampling | 4× for saturation, 8× for true-peak detection |
| CPU | About 3 % of one Apple-silicon core at 48 kHz stereo |
| AU identifier | `aufx` / `Embr` / `Grov` – "Gerov: Ember" |

---

## 10. Troubleshooting

**Ember doesn't appear in my host.**
Open Ember.app once and restart the host. In Logic Pro, also choose "Reset & Rescan Selection" in
the Plug-in Manager.

**Match didn't make it louder.**
That's what Match is for (see [section 4](#4-match--loudness-matching)). Turn Match off for the
export.

**The master audibly distorts.**
Back off Amount or Input. If LIMIT stays above 6 dB, the limiter is getting too much level.

**The bass sounds narrower.**
That's intentional: as Amount rises, Ember makes frequencies below 150 Hz more mono-solid. This
gives a firmer low end on club systems and mono speakers.

**My host's meter shows a true peak just below the ceiling.**
That's the built-in safety margin of 0.15 dB (see [section 5](#5-ceiling-and-true-peak)).

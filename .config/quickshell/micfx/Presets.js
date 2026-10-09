.pragma library
// From WhoIsCalebBrown/mic-effects (MIT, see LICENSE here), used by SettingsPages/AudioFxPage.qml.

// Presets live beside the microphone panel so the console UI and the original
// panel expose the same sound, rather than maintaining two divergent lists.
var eq = [
  { key: "flat", label: "Flat", bands: [] },
  { key: "warm", label: "Warm", bands: [{ type: "lowshelf", freq: 250, gain: 4, q: 0.707 }, { type: "highshelf", freq: 6000, gain: -3, q: 0.707 }] },
  { key: "bright", label: "Bright", bands: [{ type: "lowshelf", freq: 150, gain: -2, q: 0.707 }, { type: "highshelf", freq: 4000, gain: 5, q: 0.707 }] },
  { key: "clarity", label: "Clarity", bands: [{ type: "lowshelf", freq: 180, gain: -3, q: 0.707 }, { type: "bell", freq: 700, gain: -3, q: 1.2 }, { type: "bell", freq: 3000, gain: 5, q: 1.1 }] },
  { key: "podcast", label: "Podcast", bands: [{ type: "lowshelf", freq: 120, gain: 3, q: 0.707 }, { type: "bell", freq: 2600, gain: 4, q: 1.0 }, { type: "highshelf", freq: 7500, gain: -3, q: 0.707 }] },
  { key: "telephone", label: "Telephone", bands: [{ type: "highpass", freq: 400, gain: 0, q: 0.8 }, { type: "lowpass", freq: 3200, gain: 0, q: 0.8 }, { type: "bell", freq: 1800, gain: 4, q: 1.0 }] },
  { key: "broadcast", label: "Broadcast Voice", bands: [{ type: "highpass", freq: 80, gain: 0, q: 0.707 }, { type: "bell", freq: 200, gain: -3, q: 1.0 }, { type: "bell", freq: 3000, gain: 4, q: 1.2 }, { type: "highshelf", freq: 8000, gain: 2, q: 0.707 }] },
  { key: "radio", label: "Radio Presence", bands: [{ type: "highpass", freq: 100, gain: 0, q: 0.707 }, { type: "bell", freq: 250, gain: -4, q: 1.2 }, { type: "bell", freq: 2000, gain: 5, q: 1.0 }, { type: "highshelf", freq: 6000, gain: 3, q: 0.707 }] },
  { key: "deep", label: "Deep Voice", bands: [{ type: "lowshelf", freq: 100, gain: 5, q: 0.707 }, { type: "bell", freq: 500, gain: -3, q: 1.2 }, { type: "bell", freq: 2500, gain: 2, q: 1.0 }] },
  { key: "intimate", label: "Intimate", bands: [{ type: "lowshelf", freq: 200, gain: 4, q: 0.707 }, { type: "bell", freq: 3000, gain: -2, q: 1.5 }, { type: "highshelf", freq: 8000, gain: 2, q: 0.707 }] },
  { key: "air", label: "Vocal Air", bands: [{ type: "highshelf", freq: 12000, gain: 4, q: 0.707 }] },
  { key: "tunedtrap", label: "Tuned Trap Vocal", bands: [{ type: "highpass", freq: 85, gain: 0, q: 0.707 }, { type: "bell", freq: 260, gain: -3, q: 1.2 }, { type: "bell", freq: 750, gain: -2, q: 1.3 }, { type: "bell", freq: 3500, gain: 3, q: 1.0 }, { type: "highshelf", freq: 11000, gain: 3, q: 0.707 }] },
  { key: "mudcut", label: "Mud Cut", bands: [{ type: "highpass", freq: 90, gain: 0, q: 0.707 }, { type: "bell", freq: 220, gain: -5, q: 1.4 }] },
  { key: "boxy", label: "Boxy Fix", bands: [{ type: "bell", freq: 350, gain: -5, q: 2.0 }, { type: "bell", freq: 500, gain: -3, q: 1.5 }] },
  { key: "nasal", label: "Nasal Fix", bands: [{ type: "bell", freq: 1000, gain: -4, q: 3.0 }] },
  { key: "harsh", label: "Harsh Tame", bands: [{ type: "bell", freq: 3200, gain: -4, q: 2.5 }, { type: "highshelf", freq: 9000, gain: -2, q: 0.707 }] },
  { key: "sibilance", label: "Sibilance Tame", bands: [{ type: "bell", freq: 7000, gain: -5, q: 3.5 }] },
  { key: "rumble", label: "Rumble Kill", bands: [{ type: "highpass", freq: 120, gain: 0, q: 0.707 }] },
  { key: "plosive", label: "Plosive Guard", bands: [{ type: "highpass", freq: 110, gain: 0, q: 0.9 }, { type: "bell", freq: 180, gain: -3, q: 1.4 }] },
  { key: "thinmic", label: "Thin Mic Fix", bands: [{ type: "lowshelf", freq: 150, gain: 5, q: 0.707 }, { type: "bell", freq: 4000, gain: 2, q: 1.0 }] },
  { key: "darkmic", label: "Dark Mic Fix", bands: [{ type: "bell", freq: 2500, gain: 3, q: 1.0 }, { type: "highshelf", freq: 5000, gain: 5, q: 0.707 }] },
  { key: "closemic", label: "Close Mic", bands: [{ type: "bell", freq: 200, gain: -4, q: 1.0 }, { type: "bell", freq: 5000, gain: 2, q: 1.2 }] },
  { key: "roomtame", label: "Room Tame", bands: [{ type: "bell", freq: 160, gain: -3, q: 1.2 }, { type: "bell", freq: 400, gain: -3, q: 1.5 }] },
  { key: "megaphone", label: "Megaphone", bands: [{ type: "highpass", freq: 600, gain: 0, q: 0.9 }, { type: "lowpass", freq: 3600, gain: 0, q: 0.9 }, { type: "bell", freq: 2000, gain: 5, q: 1.2 }] },
  { key: "oldradio", label: "Old Radio", bands: [{ type: "highpass", freq: 300, gain: 0, q: 0.8 }, { type: "lowpass", freq: 4000, gain: 0, q: 0.8 }, { type: "bell", freq: 1000, gain: 6, q: 1.5 }] },
  { key: "lofi", label: "Lo-Fi", bands: [{ type: "highpass", freq: 250, gain: 0, q: 0.8 }, { type: "lowpass", freq: 5500, gain: 0, q: 0.8 }, { type: "bell", freq: 900, gain: 4, q: 1.2 }] }
]

var mic = [
  { key: "clean", label: "Clean", set: { voiceIsolation: false, noiseGate: false, autoLevel: false, deEsser: false, humFilter: false, highPass: true, eqPreset: "flat", voice: "none", space: "none", autoTune: false, pitch: 0, formant: 0 } },
  { key: "voice", label: "Voice", set: { voiceIsolation: true, voiceIsolationIntensity: 0.6, noiseGate: false, autoLevel: false, deEsser: false, humFilter: false, highPass: true, eqPreset: "flat", voice: "none", space: "none", autoTune: false, pitch: 0, formant: 0 } },
  { key: "meeting", label: "Meeting", set: { voiceIsolation: true, voiceIsolationIntensity: 0.7, noiseGate: true, noiseGateIntensity: 0.55, autoLevel: true, autoLevelIntensity: 0.6, autoLevelRatio: 0.6, autoLevelThreshold: 0.6, deEsser: true, deEsserIntensity: 0.5, humFilter: false, highPass: true, eqPreset: "clarity", voice: "none", space: "none", autoTune: false, pitch: 0, formant: 0 } },
  { key: "podcast", label: "Podcast", set: { voiceIsolation: true, voiceIsolationIntensity: 0.4, noiseGate: false, autoLevel: true, autoLevelIntensity: 0.5, autoLevelRatio: 0.5, autoLevelThreshold: 0.5, deEsser: true, deEsserIntensity: 0.6, humFilter: false, highPass: true, eqPreset: "podcast", voice: "none", space: "none", autoTune: false, pitch: 0, formant: 0 } },
  { key: "tunedtrap", label: "Tuned Trap", set: { voiceIsolation: false, noiseGate: false, autoLevel: true, autoLevelIntensity: 0.70, autoLevelRatio: 0.70, autoLevelThreshold: 0.70, compMix: 0.90, glueComp: true, glueCompIntensity: 0.42, deEsser: true, deEsserIntensity: 0.65, humFilter: false, highPass: true, eqPreset: "tunedtrap", chain: ["hpf", "nr", "gate", "deess", "pitch", "comp", "eq", "fx", "verb", "hum", "limit"], voice: "none", tape: true, tapeMix: 0.25, ringMod: false, megaphone: false, space: "hall", spaceSize: 0.58, spaceDecay: 0.68, spaceTone: 0.42, spacePreDelay: 0.20, spaceDiffusion: 0.72, spaceLowCut: 0.20, spaceModRate: 0.30, spaceModDepth: 0.06, spaceMix: 0.78, autoTune: true, autoTuneSpeed: 0.92, autoTuneAmount: 0.92, autoTuneScale: "minor", pitch: 0, formant: 0, doubler: true, doublerMix: 0.26, pitchMix: 1.0 } }
]

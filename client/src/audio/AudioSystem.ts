// Game SFX, synthesised procedurally with the Web Audio API.
//
// Deliberately NOT sample-based: the project ships no audio files and authors
// all of its assets itself (see assets/blender/*), so the sound follows the same
// rule. Every cue below is a few oscillators and a noise burst through an
// envelope - a handful of KB of code instead of MB of samples, no loading, no
// licensing, and each one is tunable by numbers like everything else in the
// game. Swapping in recorded samples later means replacing only this file.
//
// Browsers refuse to start audio before a user gesture, so the context is
// created lazily and resumed on the first interaction (see `unlock`).

type Cue = "footstep" | "pickup" | "deposit" | "jail" | "rescue" | "roundEnd" | "win" | "lose" | "matchWin" | "matchLose";

const MASTER_VOLUME = 0.35;

export class AudioSystem {
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private muted = false;
  private noiseBuffer: AudioBuffer | null = null;

  // Called from a user-gesture handler (pointer-lock click). Safe to call often.
  unlock() {
    if (!this.ctx) {
      const Ctor = window.AudioContext ?? (window as any).webkitAudioContext;
      if (!Ctor) return;
      this.ctx = new Ctor();
      this.master = this.ctx.createGain();
      this.master.gain.value = MASTER_VOLUME;
      this.master.connect(this.ctx.destination);
      this.noiseBuffer = this.makeNoiseBuffer(this.ctx);
    }
    if (this.ctx.state === "suspended") void this.ctx.resume();
  }

  setMuted(muted: boolean) {
    this.muted = muted;
    if (this.master) this.master.gain.value = muted ? 0 : MASTER_VOLUME;
  }

  isMuted(): boolean {
    return this.muted;
  }

  // `intensity` (0..1) scales level where a cue supports it (e.g. landing hard).
  play(cue: Cue, intensity = 1) {
    if (!this.ctx || !this.master || this.muted) return;
    const t = this.ctx.currentTime;
    switch (cue) {
      case "footstep":
        // Dull, short noise thump - felt more than heard.
        this.noise(t, 0.07, 900, 0.16 * intensity);
        break;
      case "pickup":
        // Cha-ching: two bright ascending blips.
        this.tone(t, "triangle", 880, 1320, 0.09, 0.28);
        this.tone(t + 0.07, "triangle", 1320, 1760, 0.12, 0.24);
        break;
      case "deposit":
        // Weighty thud plus a coin sparkle on top.
        this.tone(t, "sine", 220, 70, 0.28, 0.5);
        this.tone(t + 0.04, "triangle", 1046, 1568, 0.18, 0.18);
        this.noise(t, 0.1, 1600, 0.12);
        break;
      case "jail":
        // Harsh descending buzzer.
        this.tone(t, "square", 320, 140, 0.42, 0.24);
        this.tone(t + 0.02, "sawtooth", 160, 70, 0.42, 0.16);
        break;
      case "rescue":
        // Bright rising pop.
        this.tone(t, "sine", 520, 1180, 0.22, 0.3);
        break;
      case "roundEnd":
        // Neutral three-blast klaxon - only used for a drawn round.
        for (let i = 0; i < 3; i++) {
          this.tone(t + i * 0.22, "square", 440, 440, 0.16, 0.26);
        }
        break;
      case "win":
        // Rising major arpeggio (C-E-G-C): unmistakably "you took that one".
        this.arpeggio(t, [523, 659, 784, 1046], 0.13, 0.3, "triangle");
        break;
      case "lose":
        // Falling minor arpeggio - the same shape inverted, so the two read as
        // a matched pair rather than unrelated sounds.
        this.arpeggio(t, [523, 440, 349, 262], 0.16, 0.26, "sine");
        break;
      case "matchWin":
        // Longer fanfare: the win arpeggio, then a held triad on top.
        this.arpeggio(t, [523, 659, 784, 1046], 0.12, 0.3, "triangle");
        this.tone(t + 0.5, "triangle", 1046, 1046, 0.7, 0.26);
        this.tone(t + 0.5, "sine", 659, 659, 0.7, 0.2);
        this.tone(t + 0.5, "sine", 784, 784, 0.7, 0.2);
        break;
      case "matchLose":
        // Slow descent onto a held low note.
        this.arpeggio(t, [523, 415, 330], 0.2, 0.26, "sine");
        this.tone(t + 0.62, "sine", 262, 247, 0.9, 0.24);
        break;
    }
  }

  dispose() {
    void this.ctx?.close();
    this.ctx = null;
    this.master = null;
  }

  // ---- primitives ----

  private arpeggio(start: number, freqs: number[], step: number, peak: number, type: OscillatorType) {
    freqs.forEach((f, i) => this.tone(start + i * step, type, f, f, step * 1.7, peak));
  }

  private tone(
    start: number,
    type: OscillatorType,
    freqFrom: number,
    freqTo: number,
    duration: number,
    peak: number
  ) {
    const ctx = this.ctx!;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freqFrom, start);
    osc.frequency.exponentialRampToValueAtTime(Math.max(1, freqTo), start + duration);
    // Fast attack, exponential decay - a percussive envelope, so nothing clicks.
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(peak, start + 0.012);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);
    osc.connect(gain).connect(this.master!);
    osc.start(start);
    osc.stop(start + duration + 0.02);
  }

  private noise(start: number, duration: number, cutoff: number, peak: number) {
    const ctx = this.ctx!;
    const src = ctx.createBufferSource();
    src.buffer = this.noiseBuffer;
    const filter = ctx.createBiquadFilter();
    filter.type = "lowpass";
    filter.frequency.value = cutoff;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(peak, start);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);
    src.connect(filter).connect(gain).connect(this.master!);
    src.start(start);
    src.stop(start + duration + 0.02);
  }

  private makeNoiseBuffer(ctx: AudioContext): AudioBuffer {
    const length = Math.floor(ctx.sampleRate * 0.4);
    const buffer = ctx.createBuffer(1, length, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1;
    return buffer;
  }
}

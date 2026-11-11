import 'dart:math' as math;
import 'dart:typed_data';

import '../models/beat_pattern.dart';
import '../models/chord.dart';

/// Renders a [BeatPattern] to audio entirely in Dart — no samples, no
/// native audio engine. Every hit is placed at an exact sample offset, so
/// timing is tight on web, iOS and Android alike; the app then loops the
/// rendered WAV with a plain audio player.
///
/// Sounds are simple synthesis (sine-sweep kick, noise snare/hats, sine
/// bass, Rhodes-ish keys, plucked guitar, saw-ish brass): good enough to
/// hear a groove and chord movement, not a production mix.
class BeatSynth {
  static const sampleRate = 22050;

  static double stepSeconds(int bpm) => 60.0 / bpm / 4;

  static double loopSeconds(BeatPattern p) => stepSeconds(p.bpm) * p.steps;

  /// Start time of [step] in seconds, with swing applied to the off-beat
  /// 16th of each 8th-note pair.
  static double stepTime(int step, int bpm, double swing) {
    final pair = stepSeconds(bpm) * 2;
    return (step ~/ 2) * pair + (step.isOdd ? pair * swing : 0);
  }

  /// Which step is sounding [seconds] into the loop (for the playhead).
  static int stepAt(BeatPattern p, double seconds) {
    final t = seconds % loopSeconds(p);
    for (var i = p.steps - 1; i >= 0; i--) {
      if (stepTime(i, p.bpm, p.swing) <= t) return i;
    }
    return 0;
  }

  /// Mono samples in −1..1 for [repeats] back-to-back loops. Tails that
  /// ring past the loop end wrap round to its start, so the loop is
  /// seamless.
  static Float64List render(BeatPattern p, {int repeats = 1}) {
    final n = (loopSeconds(p) * sampleRate).round();
    final loop = Float64List(n);
    final rnd = math.Random(7);

    void mix(double atSeconds, Float64List sig, double gain) {
      final start = (atSeconds * sampleRate).round();
      for (var i = 0; i < sig.length; i++) {
        loop[(start + i) % n] += sig[i] * gain;
      }
    }

    double at(int step) => stepTime(step, p.bpm, p.swing);
    final step = stepSeconds(p.bpm);

    /// Seconds from [s] to the next hit on [track] (wrapping), capped.
    double gate(BeatTrack track, int s, double maxSteps) {
      final all = p.stepsOf(track);
      final next = all.firstWhere(
        (x) => x > s,
        orElse: () => all.first + p.steps,
      );
      return math.min(next - s, maxSteps) * step;
    }

    for (final s in p.stepsOf(BeatTrack.kick)) {
      mix(at(s), _kick(), 0.9);
    }
    for (final s in p.stepsOf(BeatTrack.snare)) {
      mix(at(s), _snare(rnd), 0.55);
    }
    for (final s in p.stepsOf(BeatTrack.hats)) {
      mix(at(s), _hat(rnd, accent: s.isEven), 0.22);
    }
    for (final s in p.stepsOf(BeatTrack.bass)) {
      final midi = bassMidi(p.bassNotes[s]!);
      if (midi == null) continue;
      mix(at(s), _bass(_hz(midi), gate(BeatTrack.bass, s, 2) * 0.92), 0.55);
    }
    for (final s in p.stepsOf(BeatTrack.keys)) {
      final len = gate(BeatTrack.keys, s, 16);
      for (final m in chordMidi(p.chordAt(s))) {
        mix(at(s), _keys(_hz(m), len), 0.11);
      }
    }
    for (final s in p.stepsOf(BeatTrack.guitar)) {
      for (final m in chordMidi(p.chordAt(s))) {
        mix(at(s), _pluck(_hz(m + 12)), 0.07);
      }
    }
    for (final s in p.stepsOf(BeatTrack.horns)) {
      final len = gate(BeatTrack.horns, s, 2) * 0.85;
      final notes = chordMidi(p.chordAt(s));
      // Brass voices the top three chord tones an octave up.
      for (final m in notes.skip(math.max(0, notes.length - 3))) {
        mix(at(s), _brass(_hz(m + 12), len), 0.07);
      }
    }

    var peak = 0.0;
    for (final x in loop) {
      peak = math.max(peak, x.abs());
    }
    final scale = peak > 0.9 ? 0.9 / peak : 1.0;
    final out = Float64List(n * repeats);
    for (var r = 0; r < repeats; r++) {
      for (var i = 0; i < n; i++) {
        out[r * n + i] = _softClip(loop[i] * scale);
      }
    }
    return out;
  }

  /// 16-bit PCM mono WAV of [render].
  static Uint8List renderWav(BeatPattern p, {int repeats = 2}) =>
      encodeWav(render(p, repeats: repeats));

  static Uint8List encodeWav(Float64List samples) {
    final data = samples.length * 2;
    final b = ByteData(44 + data);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + data, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, sampleRate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, data, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
      b.setInt16(44 + i * 2, v, Endian.little);
    }
    return b.buffer.asUint8List();
  }

  // ---- voices -------------------------------------------------------------

  static double _hz(int midi) => 440.0 * math.pow(2, (midi - 69) / 12);

  static double _softClip(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  static Float64List _buf(double seconds) =>
      Float64List(math.max(1, (seconds * sampleRate).round()));

  /// Attack/release ramp so notes don't click.
  static double _edges(
    double t,
    double len, {
    double attack = 0.004,
    double release = 0.02,
  }) {
    if (t < attack) return t / attack;
    final left = len - t;
    return left < release ? math.max(0, left / release) : 1.0;
  }

  static Float64List _kick() {
    final out = _buf(0.35);
    var phase = 0.0;
    for (var i = 0; i < out.length; i++) {
      final t = i / sampleRate;
      phase += 2 * math.pi * (45 + 80 * math.exp(-t * 28)) / sampleRate;
      out[i] =
          math.sin(phase) * math.exp(-t * 9) * _edges(t, 0.35, attack: 0.001);
    }
    return out;
  }

  static Float64List _snare(math.Random rnd) {
    final out = _buf(0.2);
    for (var i = 0; i < out.length; i++) {
      final t = i / sampleRate;
      final noise = rnd.nextDouble() * 2 - 1;
      out[i] =
          noise * math.exp(-t * 20) * 0.7 +
          math.sin(2 * math.pi * 185 * t) * math.exp(-t * 28) * 0.5;
    }
    return out;
  }

  static Float64List _hat(math.Random rnd, {required bool accent}) {
    final out = _buf(0.05);
    var prev = 0.0;
    for (var i = 0; i < out.length; i++) {
      final t = i / sampleRate;
      final noise = rnd.nextDouble() * 2 - 1;
      out[i] = (noise - prev) * math.exp(-t * 80) * (accent ? 1.0 : 0.6);
      prev = noise;
    }
    return out;
  }

  static Float64List _bass(double hz, double len) {
    final out = _buf(len);
    for (var i = 0; i < out.length; i++) {
      final t = i / sampleRate;
      final ph = 2 * math.pi * hz * t;
      out[i] =
          (math.sin(ph) + 0.3 * math.sin(2 * ph) + 0.1 * math.sin(3 * ph)) *
          math.exp(-t * 2.5) *
          _edges(t, len);
    }
    return out;
  }

  static Float64List _keys(double hz, double len) {
    final total = len + 0.15;
    final out = _buf(total);
    for (var i = 0; i < out.length; i++) {
      final t = i / sampleRate;
      final ph = 2 * math.pi * hz * t;
      final tremolo = 1 + 0.12 * math.sin(2 * math.pi * 4.5 * t);
      out[i] =
          (math.sin(ph) + 0.25 * math.sin(2 * ph) * math.exp(-t * 8)) *
          math.exp(-t * 1.2) *
          tremolo *
          _edges(t, total, attack: 0.006, release: 0.15);
    }
    return out;
  }

  static Float64List _pluck(double hz) {
    final out = _buf(0.16);
    for (var i = 0; i < out.length; i++) {
      final t = i / sampleRate;
      final ph = 2 * math.pi * hz * t;
      var x = 0.0;
      for (var k = 1; k <= 4; k++) {
        x += math.sin(k * ph) / k * math.exp(-t * (18 + 8 * k));
      }
      out[i] = x * _edges(t, 0.16, attack: 0.002);
    }
    return out;
  }

  static Float64List _brass(double hz, double len) {
    final out = _buf(len);
    for (var i = 0; i < out.length; i++) {
      final t = i / sampleRate;
      final ph =
          2 * math.pi * hz * t * (1 + 0.003 * math.sin(2 * math.pi * 5 * t));
      var x = 0.0;
      for (var k = 1; k <= 6; k++) {
        x += math.sin(k * ph) / k;
      }
      out[i] = x * _edges(t, len, attack: 0.018, release: 0.04);
    }
    return out;
  }
}

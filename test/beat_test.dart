import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:happy_family_studio/audio/beat_synth.dart';
import 'package:happy_family_studio/models/beat_pattern.dart';
import 'package:happy_family_studio/models/beat_presets.dart';
import 'package:happy_family_studio/models/chord.dart';

void main() {
  group('chords', () {
    test('parses common chart symbols', () {
      expect(chordMidi('Am7'), [57, 60, 64, 67]); // A C E G
      expect(chordMidi('Dm9'), [62, 65, 69, 72, 76]); // D F A C E
      expect(chordMidi('Cmaj7'), [60, 64, 67, 71]);
      expect(chordMidi('F#m'), [66, 69, 73]);
      expect(chordMidi('Bb'), [58, 62, 65]);
    });

    test('rejects nonsense', () {
      expect(isValidChord('H7'), isFalse);
      expect(isValidChord('Cxyz'), isFalse);
      expect(isValidChord(''), isFalse);
    });

    test('bass notes sit in A1..G#2', () {
      expect(bassMidi('A'), 33);
      expect(bassMidi('Db'), 37);
      expect(bassMidi('G#'), 44);
      expect(bassMidi('X'), isNull);
    });

    test('chord root names', () {
      expect(chordRootName('Dm9'), 'D');
      expect(chordRootName('F#m7'), 'Gb');
    });
  });

  group('pattern', () {
    test('City Pop preset matches the reel', () {
      final p = BeatPresets.cityPop();
      expect(p.bpm, 105);
      expect(p.steps, 32);
      expect(p.chordAt(0), 'Am7');
      expect(p.chordAt(8), 'Dm9');
      expect(p.stepsOf(BeatTrack.horns), [26, 28, 30, 31]);
      expect(p.bassNotes[7], 'Db');
      expect(p.bassNotes[23], 'Db');
    });

    test('toggle adds and removes; bass uses the chord root', () {
      final p = BeatPresets.empty();
      p.toggle(BeatTrack.kick, 3);
      expect(p.isOn(BeatTrack.kick, 3), isTrue);
      p.toggle(BeatTrack.kick, 3);
      expect(p.isOn(BeatTrack.kick, 3), isFalse);
      p.toggle(BeatTrack.bass, 9); // slot 1 → Am
      expect(p.bassNotes[9], 'A');
      p.toggle(BeatTrack.bass, 9);
      expect(p.bassNotes.containsKey(9), isFalse);
    });

    test('copy is independent', () {
      final a = BeatPresets.cityPop();
      final b = a.copy()..toggle(BeatTrack.kick, 1);
      expect(a.isOn(BeatTrack.kick, 1), isFalse);
      expect(b.isOn(BeatTrack.kick, 1), isTrue);
    });

    test('prompt describes the groove and fits the style limit', () {
      final prompt = BeatPresets.cityPop().toPrompt();
      expect(prompt, contains('105 BPM'));
      expect(prompt, contains('swing 54%'));
      expect(prompt, contains('Am7 (2 beats) → Dm9 (2 beats)'));
      expect(prompt, contains('busy 16th-note hi-hats'));
      expect(prompt, contains('brass'));
      expect(prompt.length, lessThanOrEqualTo(1000));
      for (final e in BeatPresets.all) {
        expect(e.build().toPrompt().length, lessThanOrEqualTo(1000));
      }
    });

    test('rock preset reads as straight with a backbeat', () {
      final prompt = BeatPresets.saturdayRock().toPrompt();
      expect(prompt, contains('straight 16ths'));
      expect(prompt, contains('snare on 2 and 4'));
      expect(prompt, contains('G (4 beats) → B7 (4 beats)'));
    });
  });

  group('synth', () {
    test('swing pushes only the off-beat 16ths', () {
      const bpm = 120; // 16th = 0.125 s, 8th pair = 0.25 s
      expect(BeatSynth.stepTime(2, bpm, 0.6), closeTo(0.25, 1e-9));
      expect(BeatSynth.stepTime(3, bpm, 0.6), closeTo(0.25 + 0.15, 1e-9));
      expect(BeatSynth.stepTime(3, bpm, 0.5), closeTo(0.375, 1e-9));
    });

    test('playhead maps time back to steps', () {
      final p = BeatPresets.cityPop();
      expect(BeatSynth.stepAt(p, 0), 0);
      final t5 = BeatSynth.stepTime(5, p.bpm, p.swing) + 0.001;
      expect(BeatSynth.stepAt(p, t5), 5);
      expect(BeatSynth.stepAt(p, BeatSynth.loopSeconds(p) + t5), 5);
    });

    test('renders a loop of the right length with sound in it', () {
      final p = BeatPresets.cityPop();
      final samples = BeatSynth.render(p, repeats: 2);
      final loop = (BeatSynth.loopSeconds(p) * BeatSynth.sampleRate).round();
      expect(samples.length, loop * 2);
      expect(samples.every((x) => x.abs() <= 1), isTrue);
      expect(samples.any((x) => x.abs() > 0.1), isTrue);
      // Repeats are identical, so the loop point is seamless.
      expect(samples[loop + 1234], samples[1234]);
    });

    test('empty grid renders silence', () {
      final p = BeatPresets.empty()..clear();
      expect(BeatSynth.render(p).every((x) => x == 0), isTrue);
    });

    test('WAV header is valid 16-bit mono PCM', () {
      final wav = BeatSynth.encodeWav(Float64List.fromList([0, 0.5, -0.5]));
      final b = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(b.getUint16(22, Endian.little), 1);
      expect(b.getUint32(24, Endian.little), BeatSynth.sampleRate);
      expect(b.getUint32(40, Endian.little), 6);
      expect(b.getInt16(46, Endian.little), 16384);
    });
  });
}

import 'beat_pattern.dart';

/// Starting grooves for the beat grid.
class BeatPresets {
  /// Transcribed from the @paragonrhythms "City Pop" step-sequencer reel
  /// (bar 2 of their loop, 105 BPM, swing 54%, F major). Bar 1 is the same
  /// groove without horns, so the horns arrive "on top" in bar 2.
  static BeatPattern cityPop() {
    const kick = [0, 6, 8, 14];
    const snare = [3, 4, 9, 12, 15];
    const guitar = [2, 3, 5, 6, 7, 10, 11, 13, 14, 15];
    const bass = {
      0: 'A', 2: 'A', 4: 'E', 6: 'A', 7: 'Db', //
      8: 'D', 10: 'D', 12: 'A', 13: 'C', 15: 'A',
    };
    Set<int> both(List<int> s) => {...s, for (final x in s) x + 16};
    return BeatPattern(
      name: 'City Pop',
      bpm: 105,
      swing: 0.54,
      chords: ['Am7', 'Dm9', 'Am7', 'Dm9'],
      hits: {
        BeatTrack.kick: both(kick),
        BeatTrack.snare: both(snare),
        BeatTrack.hats: {for (var i = 0; i < 32; i++) i},
        BeatTrack.keys: {0, 8, 16, 24},
        BeatTrack.guitar: both(guitar),
        BeatTrack.horns: {26, 28, 30, 31},
      },
      bassNotes: {
        for (final e in bass.entries) ...{e.key: e.value, e.key + 16: e.value},
      },
    );
  }

  /// A straight 90s guitar-rock groove in the spirit of 星期六返嚟
  /// (G major, ~121 BPM): kick on 1 and the "and" of 2, backbeat snare,
  /// 8th hats, root-note 8th bass, guitar chords on every 8th.
  static BeatPattern saturdayRock() {
    final eighths = [for (var i = 0; i < 32; i += 2) i];
    const chords = ['G', 'G', 'B7', 'B7'];
    return BeatPattern(
      name: '星期六返嚟 Rock',
      bpm: 121,
      swing: 0.5,
      chords: [...chords],
      hits: {
        BeatTrack.kick: {0, 6, 8, 16, 22, 24},
        BeatTrack.snare: {4, 12, 20, 28},
        BeatTrack.hats: {...eighths},
        BeatTrack.guitar: {...eighths},
      },
      bassNotes: {for (final s in eighths) s: s < 16 ? 'G' : 'B'},
    );
  }

  static BeatPattern empty() =>
      BeatPattern(name: '空白', chords: ['C', 'Am', 'F', 'G']);

  static final all = <({String label, BeatPattern Function() build})>[
    (label: 'City Pop', build: cityPop),
    (label: '星期六返嚟 Rock', build: saturdayRock),
    (label: '空白', build: empty),
  ];
}

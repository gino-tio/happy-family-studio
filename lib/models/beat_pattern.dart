import 'chord.dart';

/// Rows of the beat grid, top to bottom.
enum BeatTrack {
  kick('Kick', '大鼓'),
  snare('Snare', '軍鼓'),
  hats('Hats', '踩鑔'),
  bass('Bass', 'Bass'),
  keys('E. Piano', '電琴'),
  guitar('Guitar', '結他'),
  horns('Horns', '銅管');

  const BeatTrack(this.label, this.zhLabel);
  final String label;
  final String zhLabel;

  bool get isDrum => this == kick || this == snare || this == hats;

  /// Tracks that play the current chord rather than a single note.
  bool get isChordal => this == keys || this == guitar || this == horns;
}

/// A step-sequencer loop: 16th-note steps, a chord per half bar, and per-
/// track hits. Bass hits carry their own note name. Mutable on purpose —
/// the beat screen edits one in place and calls setState.
class BeatPattern {
  BeatPattern({
    required this.name,
    this.bpm = 105,
    this.swing = 0.54,
    this.bars = 2,
    List<String>? chords,
    Map<BeatTrack, Set<int>>? hits,
    Map<int, String>? bassNotes,
  }) : chords = chords ?? List.filled(bars * 2, 'C'),
       hits = {
         for (final t in BeatTrack.values)
           if (t != BeatTrack.bass) t: {...?hits?[t]},
       },
       bassNotes = {...?bassNotes} {
    assert(this.chords.length == chordSlots);
  }

  static const stepsPerBar = 16;

  /// One chord per half bar (two beats, eight 16ths).
  static const stepsPerChord = 8;

  String name;
  int bpm;

  /// Where the off-beat 16th lands inside each 8th-note pair: 0.5 is
  /// straight, ~0.67 is triplet swing.
  double swing;
  final int bars;
  final List<String> chords;
  final Map<BeatTrack, Set<int>> hits;
  final Map<int, String> bassNotes;

  int get steps => bars * stepsPerBar;
  int get chordSlots => steps ~/ stepsPerChord;

  String chordAt(int step) => chords[(step ~/ stepsPerChord) % chords.length];

  bool isOn(BeatTrack track, int step) => track == BeatTrack.bass
      ? bassNotes.containsKey(step)
      : hits[track]!.contains(step);

  /// Steps of [track] that sound, in order.
  List<int> stepsOf(BeatTrack track) => track == BeatTrack.bass
      ? (bassNotes.keys.toList()..sort())
      : (hits[track]!.toList()..sort());

  /// Tap behaviour: drums and chord rows toggle; a bass tap adds the root of
  /// the chord under that step, or clears the note that is there.
  void toggle(BeatTrack track, int step) {
    if (track == BeatTrack.bass) {
      if (bassNotes.remove(step) == null) {
        bassNotes[step] = chordRootName(chordAt(step)) ?? 'C';
      }
      return;
    }
    final set = hits[track]!;
    if (!set.remove(step)) set.add(step);
  }

  void clear() {
    for (final s in hits.values) {
      s.clear();
    }
    bassNotes.clear();
  }

  BeatPattern copy() => BeatPattern(
    name: name,
    bpm: bpm,
    swing: swing,
    bars: bars,
    chords: [...chords],
    hits: hits,
    bassNotes: bassNotes,
  );

  /// Turns the grid into a style prompt for the AI composer, so a groove
  /// sketched here can seed a full song. Kept well under the 1000-char
  /// style limit.
  String toPrompt() {
    final parts = <String>[
      '$bpm BPM, ${swing <= 0.51 ? 'straight 16ths' : 'swing ${(swing * 100).round()}%'}, 4/4.',
    ];

    final progression = <String>[];
    var i = 0;
    while (i < chords.length) {
      var j = i;
      while (j + 1 < chords.length && chords[j + 1] == chords[i]) {
        j++;
      }
      final beats = (j - i + 1) * 2;
      progression.add('${chords[i]} ($beats beats)');
      i = j + 1;
    }
    parts.add('Chord loop: ${progression.join(' → ')}.');

    final drums = <String>[];
    final kicks = stepsOf(BeatTrack.kick);
    if (kicks.isNotEmpty) {
      final fourOnFloor =
          kicks.length == steps ~/ 4 && kicks.every((s) => s % 4 == 0);
      drums.add(
        fourOnFloor
            ? 'four-on-the-floor kick'
            : kicks.any((s) => s % 4 != 0)
            ? 'syncopated kick'
            : 'kick on the beat',
      );
    }
    final snares = stepsOf(BeatTrack.snare);
    if (snares.isNotEmpty) {
      final backbeat =
          List.generate(bars, (b) => b * 16 + 4).every(snares.contains) &&
          List.generate(bars, (b) => b * 16 + 12).every(snares.contains);
      drums.add(backbeat ? 'snare on 2 and 4' : 'syncopated snare');
    }
    final hats = stepsOf(BeatTrack.hats).length;
    if (hats >= steps * 3 ~/ 4) {
      drums.add('busy 16th-note hi-hats');
    } else if (hats >= steps ~/ 2) {
      drums.add('8th-note hi-hats');
    } else if (hats > 0) {
      drums.add('sparse hi-hats');
    }
    if (drums.isNotEmpty) parts.add('Drums: ${drums.join(', ')}.');

    final bass = stepsOf(BeatTrack.bass).map((s) => bassNotes[s]).toList();
    if (bass.isNotEmpty) {
      parts.add(
        'Bass line (16th-note grid, one bar loop shown): '
        '${bass.take(16).join(' ')}.',
      );
    }
    if (stepsOf(BeatTrack.keys).isNotEmpty) {
      parts.add('Warm Rhodes electric piano holding the chords.');
    }
    final guitar = stepsOf(BeatTrack.guitar);
    if (guitar.isNotEmpty) {
      parts.add(
        guitar.any((s) => s.isOdd)
            ? 'Clean funky guitar chord stabs on the off-beats.'
            : 'Clean guitar chords on the beat.',
      );
    }
    if (stepsOf(BeatTrack.horns).isNotEmpty) {
      parts.add('Bright brass section stabs on top.');
    }
    return parts.join(' ');
  }
}

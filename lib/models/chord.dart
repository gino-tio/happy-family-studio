/// Tiny music-theory helpers for the beat grid: note names and chord
/// symbols → MIDI note numbers. Covers the symbols a band chart uses
/// (Am7, Dm9, Cmaj7, G7, F, Bm, Esus4, F#m7…), not full jazz notation.
library;

const _pitchClass = <String, int>{
  'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11, //
};

/// Note names offered in pickers, flats spelled the way charts usually do.
const noteNames = <String>[
  'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B', //
];

/// Chord qualities, longest suffix first so `maj7` wins over `m`.
const _qualities = <String, List<int>>{
  'maj9': [0, 4, 7, 11, 14],
  'maj7': [0, 4, 7, 11],
  'sus4': [0, 5, 7],
  'sus2': [0, 2, 7],
  'm7b5': [0, 3, 6, 10],
  'dim': [0, 3, 6],
  'aug': [0, 4, 8],
  'm9': [0, 3, 7, 10, 14],
  'm7': [0, 3, 7, 10],
  'm6': [0, 3, 7, 9],
  '9': [0, 4, 7, 10, 14],
  '7': [0, 4, 7, 10],
  '6': [0, 4, 7, 9],
  'm': [0, 3, 7],
  '': [0, 4, 7],
};

/// Pitch class 0–11 of a note name such as `A`, `Db`, `F#`; null if invalid.
int? pitchClassOf(String name) {
  final (pc, rest) = _splitRoot(name.trim());
  return (pc != null && rest.isEmpty) ? pc : null;
}

(int?, String) _splitRoot(String s) {
  if (s.isEmpty) return (null, '');
  final base = _pitchClass[s[0].toUpperCase()];
  if (base == null) return (null, s);
  var i = 1;
  var pc = base;
  if (s.length > 1 && (s[1] == '#' || s[1] == '♯')) {
    pc += 1;
    i = 2;
  } else if (s.length > 1 && (s[1] == 'b' || s[1] == '♭')) {
    pc -= 1;
    i = 2;
  }
  return (pc % 12, s.substring(i));
}

/// Root pitch class + intervals of a chord symbol, or null if not understood.
({int root, List<int> intervals})? parseChord(String symbol) {
  final (root, rest) = _splitRoot(symbol.trim());
  if (root == null) return null;
  final intervals = _qualities[rest];
  if (intervals == null) return null;
  return (root: root, intervals: intervals);
}

bool isValidChord(String symbol) => parseChord(symbol) != null;

/// Close-voiced chord around middle C: root placed in A3..G#4 (57–68).
List<int> chordMidi(String symbol) {
  final c = parseChord(symbol);
  if (c == null) return const [];
  final root = 57 + ((c.root - 9) % 12);
  return [for (final i in c.intervals) root + i];
}

/// Bass register: A1..G#2 (33–44), where a finger bass sits.
int? bassMidi(String note) {
  final pc = pitchClassOf(note);
  return pc == null ? null : 33 + ((pc - 9) % 12);
}

/// Root note name of a chord symbol (`Dm9` → `D`), for one-tap bass notes.
String? chordRootName(String symbol) {
  final c = parseChord(symbol);
  return c == null ? null : noteNames[c.root];
}

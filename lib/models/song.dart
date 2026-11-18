enum SongStatus {
  queued,
  generating,
  done,
  failed;

  static SongStatus parse(Object? raw) => SongStatus.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => SongStatus.queued,
  );

  bool get isPending => this == queued || this == generating;
}

/// One sung line with its timing in the audio (from MusicGPT's lyric timestamps).
class LyricLine {
  const LyricLine({required this.start, required this.end, required this.text});

  final Duration start;
  final Duration end;
  final String text;

  /// Parses `songs.lyrics_timed` ([{start, end, text}] in ms); null when absent or unusable.
  static List<LyricLine>? parseList(Object? raw) {
    if (raw is! List) return null;
    final lines = <LyricLine>[];
    for (final x in raw) {
      if (x is! Map) continue;
      final text = x['text'];
      final start = x['start'];
      final end = x['end'];
      if (text is! String || start is! num || end is! num) continue;
      if (text.trim().isEmpty) continue;
      lines.add(
        LyricLine(
          start: Duration(milliseconds: start.round()),
          end: Duration(milliseconds: end.round()),
          text: text.trim(),
        ),
      );
    }
    lines.sort((a, b) => a.start.compareTo(b.start));
    return lines.isEmpty ? null : lines;
  }

  /// Index of the line being sung at [pos]: the last line that has started, or -1 before the first.
  static int activeIndex(List<LyricLine> lines, Duration pos) {
    var lo = 0;
    var hi = lines.length - 1;
    var found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].start <= pos) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }
}

/// One row of `app_studio.songs`. [Song.fromRow] is the single parser for
/// PostgREST selects, the Realtime stream and the Edge Function response.
class Song {
  const Song({
    required this.id,
    required this.createdBy,
    required this.title,
    required this.style,
    required this.lyrics,
    required this.instrumental,
    required this.lengthMs,
    required this.provider,
    required this.model,
    required this.status,
    required this.error,
    required this.audioPath,
    required this.createdAt,
    this.coverPath,
    this.lyricsTimed,
  });

  final String id;
  final String createdBy;
  final String title;
  final String style;
  final String lyrics;
  final bool instrumental;
  final int? lengthMs;
  final String provider;
  final String model;
  final SongStatus status;
  final String? error;
  final String? audioPath;
  final DateTime createdAt;

  /// Object in the private `studio-covers` bucket (.jpg from MusicGPT or .svg drawn by Claude).
  final String? coverPath;

  /// Timed lyrics for karaoke-style highlighting; null = show [lyrics] as plain text.
  final List<LyricLine>? lyricsTimed;

  bool get isPlayable => status == SongStatus.done && audioPath != null;

  factory Song.fromRow(Map<String, dynamic> row) => Song(
    id: row['id'] as String,
    createdBy: row['created_by'] as String,
    title: row['title'] as String,
    style: (row['style'] as String?) ?? '',
    lyrics: (row['lyrics'] as String?) ?? '',
    instrumental: (row['instrumental'] as bool?) ?? false,
    lengthMs: (row['length_ms'] as num?)?.toInt(),
    provider: (row['provider'] as String?) ?? '',
    model: (row['model'] as String?) ?? '',
    status: SongStatus.parse(row['status']),
    error: row['error'] as String?,
    audioPath: row['audio_path'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    coverPath: row['cover_path'] as String?,
    lyricsTimed: LyricLine.parseList(row['lyrics_timed']),
  );
}

/// What the compose screen sends to the `studio-generate-song` Edge Function.
class SongDraft {
  const SongDraft({
    required this.title,
    this.style = '',
    this.lyrics = '',
    this.instrumental = false,
    this.lengthMs,
    this.provider = 'elevenlabs',
  });

  final String title;
  final String style;
  final String lyrics;
  final bool instrumental;
  final int? lengthMs;

  /// Which AI sings it: `elevenlabs`, `musicgpt` or `acestep` (see studio-generate-song).
  final String provider;

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'style': style.trim(),
    'lyrics': instrumental ? '' : lyrics.trim(),
    'instrumental': instrumental,
    if (lengthMs != null) 'length_ms': lengthMs,
    'provider': provider,
  };
}

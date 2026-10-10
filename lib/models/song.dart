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

/// One row of `public.songs`. [Song.fromRow] is the single parser for
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
  );
}

/// What the compose screen sends to the `generate-song` Edge Function.
class SongDraft {
  const SongDraft({
    required this.title,
    this.style = '',
    this.lyrics = '',
    this.instrumental = false,
    this.lengthMs,
  });

  final String title;
  final String style;
  final String lyrics;
  final bool instrumental;
  final int? lengthMs;

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'style': style.trim(),
    'lyrics': instrumental ? '' : lyrics.trim(),
    'instrumental': instrumental,
    if (lengthMs != null) 'length_ms': lengthMs,
  };
}

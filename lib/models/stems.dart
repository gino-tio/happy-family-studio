/// One track of a split song (`app_studio.song_stems.stems`).
class Stem {
  const Stem({required this.kind, required this.path});

  final String kind;
  final String path;

  /// Cantonese label for the track.
  String get label => switch (kind) {
    'vocals' => '人聲',
    'instrumental' => '伴奏（冇人聲）',
    'piano' => '鋼琴',
    'bass' => 'Bass',
    'drums' => '鼓',
    'guitar' => '結他',
    _ => kind,
  };
}

/// One split of a song into tracks (拆樂器). Written only by the
/// studio-song-tools Edge Function; the app reads it over Realtime.
class SongStems {
  const SongStems({
    required this.id,
    required this.songId,
    required this.status,
    required this.stems,
    this.error,
  });

  final String id;
  final String songId;

  /// 'generating', 'done' or 'failed'.
  final String status;
  final List<Stem> stems;
  final String? error;

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';

  Stem? get instrumental {
    for (final s in stems) {
      if (s.kind == 'instrumental') return s;
    }
    return null;
  }

  factory SongStems.fromRow(Map<String, dynamic> row) => SongStems(
    id: row['id'] as String,
    songId: row['song_id'] as String,
    status: (row['status'] as String?) ?? 'generating',
    error: row['error'] as String?,
    stems: [
      for (final s in (row['stems'] as List?) ?? const [])
        if (s is Map && s['kind'] is String && s['path'] is String)
          Stem(kind: s['kind'] as String, path: s['path'] as String),
    ],
  );
}

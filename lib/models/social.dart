/// A band member as `app_studio.members()` returns them.
class Member {
  const Member({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.role = 'member',
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final String role;

  factory Member.fromRow(Map<String, dynamic> row) => Member(
    userId: row['user_id'] as String,
    name: (row['name'] as String?) ?? '?',
    avatarUrl: row['avatar_url'] as String?,
    role: (row['role'] as String?) ?? 'member',
  );

  /// Shown when a row's author is no longer a member.
  static const unknown = Member(userId: '', name: '樂隊成員');
}

/// One row of `app_studio.song_comments`. A reply has [parentId] (one level only).
class SongComment {
  const SongComment({
    required this.id,
    required this.songId,
    required this.userId,
    required this.parentId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String songId;
  final String userId;
  final String? parentId;
  final String body;
  final DateTime createdAt;

  factory SongComment.fromRow(Map<String, dynamic> row) => SongComment(
    id: row['id'] as String,
    songId: row['song_id'] as String,
    userId: row['user_id'] as String,
    parentId: row['parent_id'] as String?,
    body: (row['body'] as String?) ?? '',
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
  );
}

/// Top-level comments, newest first, each with its replies oldest first.
List<({SongComment comment, List<SongComment> replies})> threadComments(
  List<SongComment> all,
) {
  final tops = all.where((c) => c.parentId == null).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return [
    for (final t in tops)
      (
        comment: t,
        replies: all.where((c) => c.parentId == t.id).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      ),
  ];
}

/// One row of `app_studio.playlists`.
class Playlist {
  const Playlist({
    required this.id,
    required this.createdBy,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String createdBy;
  final String name;
  final DateTime createdAt;

  factory Playlist.fromRow(Map<String, dynamic> row) => Playlist(
    id: row['id'] as String,
    createdBy: row['created_by'] as String,
    name: (row['name'] as String?) ?? '',
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
  );
}

/// One row of `app_studio.playlist_songs`.
class PlaylistEntry {
  const PlaylistEntry({
    required this.playlistId,
    required this.songId,
    required this.position,
    required this.addedAt,
  });

  final String playlistId;
  final String songId;
  final int position;
  final DateTime addedAt;

  factory PlaylistEntry.fromRow(Map<String, dynamic> row) => PlaylistEntry(
    playlistId: row['playlist_id'] as String,
    songId: row['song_id'] as String,
    position: (row['position'] as num?)?.toInt() ?? 0,
    addedAt: DateTime.parse(row['added_at'] as String).toLocal(),
  );
}

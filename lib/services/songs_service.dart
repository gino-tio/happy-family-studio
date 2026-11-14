import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/social.dart';
import '../models/song.dart';

class SongsService {
  final _client = Supabase.instance.client;

  /// Tables of this app on the shared DB.
  SupabaseQuerySchema get _db => _client.schema(Env.dbSchema);

  /// Newest first. Note: supabase-dart `.order()` defaults to descending —
  /// pass `ascending` explicitly (tio-help pitfall #8).
  Stream<List<Song>> watchSongs() => _db
      .from('songs')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(Song.fromRow).toList());

  Stream<Song?> watchSong(String id) => _db
      .from('songs')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .map((rows) => rows.isEmpty ? null : Song.fromRow(rows.first));

  /// Kicks off generation. Returns the new row immediately (status
  /// `generating`); the Edge Function finishes it in the background.
  Future<Song> generate(SongDraft draft) async {
    final res = await _client.functions.invoke(
      Env.generateSongFunction,
      body: draft.toJson(),
    );
    final data = res.data;
    if (data is Map && data['song'] is Map) {
      return Song.fromRow(Map<String, dynamic>.from(data['song'] as Map));
    }
    throw Exception('Unexpected response: $data');
  }

  /// Asks AI for Cantonese lyrics. Returns (title, lyrics); throws with the
  /// function's own message (e.g. the daily limit) when it can't.
  Future<({String title, String lyrics})> writeLyrics({
    required String topic,
    required String style,
    required String title,
    required int seconds,
  }) async {
    try {
      final res = await _client.functions.invoke(
        Env.writeLyricsFunction,
        body: {
          'topic': topic,
          'style': style,
          'title': title,
          'seconds': seconds,
        },
      );
      final data = res.data;
      if (data is Map && data['lyrics'] is String) {
        return (
          title: (data['title'] ?? '') as String,
          lyrics: data['lyrics'] as String,
        );
      }
      throw Exception('Unexpected response');
    } on FunctionException catch (e) {
      final d = e.details;
      throw Exception(
        d is Map && d['error'] is String ? d['error'] : 'AI 寫唔到，遲啲再試',
      );
    }
  }

  Future<String> signedAudioUrl(String path) =>
      _client.storage.from(Env.songsBucket).createSignedUrl(path, 60 * 60);

  // Covers -------------------------------------------------------------------

  final _coverUrls = <String, Future<String>>{};

  /// Signed URL of a cover (cached for the session; a new cover has a new path).
  Future<String> coverUrl(String path) => _coverUrls.putIfAbsent(
    path,
    () => _client.storage
        .from(Env.coversBucket)
        .createSignedUrl(path, 60 * 60 * 24),
  );

  /// Asks AI for a new cover. The picture arrives over Realtime in about a minute.
  Future<void> requestNewCover(String songId) async {
    try {
      await _client.functions.invoke(
        Env.songCoverFunction,
        body: {'song_id': songId},
      );
    } on FunctionException catch (e) {
      final d = e.details;
      throw Exception(
        d is Map && d['error'] is String ? d['error'] : '畫唔到封面，遲啲再試',
      );
    }
  }

  // Band, likes, comments, playlists -----------------------------------------

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<List<Member>> members() async {
    final rows = await _db.rpc('members') as List;
    return rows
        .map((r) => Member.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Every like in the band: (song id, user id).
  Stream<List<({String songId, String userId})>> watchLikes() => _db
      .from('song_likes')
      .stream(primaryKey: ['song_id', 'user_id'])
      .map(
        (rows) => [
          for (final r in rows)
            (songId: r['song_id'] as String, userId: r['user_id'] as String),
        ],
      );

  Future<void> setLiked(String songId, bool liked) async {
    if (liked) {
      await _db.from('song_likes').upsert({
        'song_id': songId,
      }, ignoreDuplicates: true);
    } else {
      await _db
          .from('song_likes')
          .delete()
          .eq('song_id', songId)
          .eq('user_id', currentUserId ?? '');
    }
  }

  Stream<List<SongComment>> watchComments(String songId) => _db
      .from('song_comments')
      .stream(primaryKey: ['id'])
      .eq('song_id', songId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(SongComment.fromRow).toList());

  Future<void> addComment(String songId, String body, {String? parentId}) => _db
      .from('song_comments')
      .insert({'song_id': songId, 'body': body.trim(), 'parent_id': ?parentId});

  Future<void> deleteComment(String id) =>
      _db.from('song_comments').delete().eq('id', id);

  Stream<List<Playlist>> watchPlaylists() => _db
      .from('playlists')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: true)
      .map((rows) => rows.map(Playlist.fromRow).toList());

  Stream<List<PlaylistEntry>> watchPlaylistEntries() => _db
      .from('playlist_songs')
      .stream(primaryKey: ['playlist_id', 'song_id'])
      .map((rows) => rows.map(PlaylistEntry.fromRow).toList());

  Future<String> createPlaylist(String name) async {
    final row = await _db
        .from('playlists')
        .insert({'name': name.trim()})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> renamePlaylist(String id, String name) =>
      _db.from('playlists').update({'name': name.trim()}).eq('id', id);

  Future<void> deletePlaylist(String id) =>
      _db.from('playlists').delete().eq('id', id);

  Future<void> addToPlaylist(String playlistId, String songId, int position) =>
      _db.from('playlist_songs').upsert({
        'playlist_id': playlistId,
        'song_id': songId,
        'position': position,
      }, ignoreDuplicates: true);

  Future<void> removeFromPlaylist(String playlistId, String songId) => _db
      .from('playlist_songs')
      .delete()
      .eq('playlist_id', playlistId)
      .eq('song_id', songId);

  Future<void> rename(String id, String title) =>
      _db.from('songs').update({'title': title}).eq('id', id);

  Future<void> delete(String id) => _db.from('songs').delete().eq('id', id);
}

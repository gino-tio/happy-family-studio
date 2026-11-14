import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
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

  Future<void> rename(String id, String title) =>
      _db.from('songs').update({'title': title}).eq('id', id);

  Future<void> delete(String id) => _db.from('songs').delete().eq('id', id);
}

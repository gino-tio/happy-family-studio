import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/song.dart';

class SongsService {
  final _client = Supabase.instance.client;

  /// Newest first. Note: supabase-dart `.order()` defaults to descending —
  /// pass `ascending` explicitly (tio-help pitfall #8).
  Stream<List<Song>> watchSongs() => _client
      .from('songs')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(Song.fromRow).toList());

  Stream<Song?> watchSong(String id) => _client
      .from('songs')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .map((rows) => rows.isEmpty ? null : Song.fromRow(rows.first));

  /// Kicks off generation. Returns the new row immediately (status
  /// `generating`); the Edge Function finishes it in the background.
  Future<Song> generate(SongDraft draft) async {
    final res = await _client.functions.invoke(
      'generate-song',
      body: draft.toJson(),
    );
    final data = res.data;
    if (data is Map && data['song'] is Map) {
      return Song.fromRow(Map<String, dynamic>.from(data['song'] as Map));
    }
    throw Exception('Unexpected response: $data');
  }

  Future<String> signedAudioUrl(String path) =>
      _client.storage.from('songs').createSignedUrl(path, 60 * 60);

  Future<void> rename(String id, String title) =>
      _client.from('songs').update({'title': title}).eq('id', id);

  Future<void> delete(String id) => _client.from('songs').delete().eq('id', id);
}

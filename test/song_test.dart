import 'package:flutter_test/flutter_test.dart';
import 'package:happy_family_studio/models/song.dart';

void main() {
  test('Song.fromRow parses a songs row', () {
    final s = Song.fromRow({
      'id': 'a',
      'created_by': 'u',
      'title': '星期六返嚟',
      'style': 'rock',
      'lyrics': '星期六',
      'instrumental': false,
      'length_ms': 120000,
      'provider': 'elevenlabs',
      'model': 'music_v1',
      'status': 'generating',
      'error': null,
      'audio_path': null,
      'created_at': '2026-10-10T04:00:00Z',
    });
    expect(s.status, SongStatus.generating);
    expect(s.status.isPending, isTrue);
    expect(s.lengthMs, 120000);
  });

  test('unknown status falls back to queued', () {
    expect(SongStatus.parse('weird'), SongStatus.queued);
  });

  test('SongDraft drops lyrics for instrumentals', () {
    final json = const SongDraft(
      title: ' t ',
      style: 'lofi',
      lyrics: 'la la',
      instrumental: true,
    ).toJson();
    expect(json['title'], 't');
    expect(json['lyrics'], '');
    expect(json.containsKey('length_ms'), isFalse);
  });
}

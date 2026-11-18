import 'package:flutter_test/flutter_test.dart';
import 'package:happy_family_studio/models/stems.dart';

void main() {
  test('SongStems.fromRow reads tracks and finds the instrumental', () {
    final s = SongStems.fromRow({
      'id': 'a',
      'song_id': 'b',
      'status': 'done',
      'stems': [
        {'kind': 'vocals', 'path': 'u/stems/b/vocals.mp3'},
        {'kind': 'instrumental', 'path': 'u/stems/b/instrumental.mp3'},
        {'kind': 'bad'},
      ],
    });
    expect(s.isDone, isTrue);
    expect(s.stems.length, 2);
    expect(s.stems.first.label, '人聲');
    expect(s.instrumental?.path, 'u/stems/b/instrumental.mp3');
  });

  test('SongStems.fromRow without tracks is still generating', () {
    final s = SongStems.fromRow({'id': 'a', 'song_id': 'b'});
    expect(s.isDone, isFalse);
    expect(s.instrumental, isNull);
  });
}

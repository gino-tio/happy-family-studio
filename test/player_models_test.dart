import 'package:flutter_test/flutter_test.dart';
import 'package:happy_family_studio/models/social.dart';
import 'package:happy_family_studio/models/song.dart';
import 'package:happy_family_studio/widgets/comments_view.dart';

void main() {
  test('LyricLine.parseList reads timed lyrics and sorts them', () {
    final lines = LyricLine.parseList([
      {'start': 3000, 'end': 4000, 'text': '第二句'},
      {'start': 1000, 'end': 2000, 'text': ' 第一句 '},
      {'start': 'x', 'end': 1, 'text': 'bad'},
      {'start': 5000, 'end': 6000, 'text': '  '},
    ])!;
    expect(lines.map((l) => l.text), ['第一句', '第二句']);
    expect(lines.first.start, const Duration(seconds: 1));
    expect(LyricLine.parseList(null), isNull);
    expect(LyricLine.parseList([]), isNull);
  });

  test('LyricLine.activeIndex is the last line that has started', () {
    final lines = LyricLine.parseList([
      {'start': 1000, 'end': 2000, 'text': 'a'},
      {'start': 3000, 'end': 4000, 'text': 'b'},
      {'start': 5000, 'end': 6000, 'text': 'c'},
    ])!;
    expect(LyricLine.activeIndex(lines, Duration.zero), -1);
    expect(LyricLine.activeIndex(lines, const Duration(milliseconds: 1000)), 0);
    expect(LyricLine.activeIndex(lines, const Duration(milliseconds: 2500)), 0);
    expect(LyricLine.activeIndex(lines, const Duration(seconds: 9)), 2);
  });

  test('Song.fromRow reads cover and timed lyrics', () {
    final s = Song.fromRow({
      'id': 'a',
      'created_by': 'u',
      'title': 't',
      'status': 'done',
      'audio_path': 'u/a.mp3',
      'created_at': '2026-11-14T04:00:00Z',
      'cover_path': 'a/c.jpg',
      'lyrics_timed': [
        {'start': 1, 'end': 2, 'text': '一'},
      ],
    });
    expect(s.coverPath, 'a/c.jpg');
    expect(s.lyricsTimed!.single.text, '一');
    expect(s.isPlayable, isTrue);
  });

  test('threadComments: newest threads first, replies oldest first', () {
    SongComment c(String id, int min, {String? parent}) => SongComment(
      id: id,
      songId: 's',
      userId: 'u',
      parentId: parent,
      body: id,
      createdAt: DateTime(2026, 11, 14, 10, min),
    );
    final t = threadComments([
      c('old', 0),
      c('new', 5),
      c('r2', 7, parent: 'old'),
      c('r1', 6, parent: 'old'),
    ]);
    expect(t.map((x) => x.comment.id), ['new', 'old']);
    expect(t[1].replies.map((r) => r.id), ['r1', 'r2']);
  });

  test('timeAgo', () {
    final now = DateTime(2026, 11, 14, 12);
    expect(timeAgo(now, now: now), '啱啱');
    expect(
      timeAgo(now.subtract(const Duration(minutes: 5)), now: now),
      '5 分鐘前',
    );
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3 個鐘前');
    expect(timeAgo(now.subtract(const Duration(days: 2)), now: now), '2 日前');
  });
}

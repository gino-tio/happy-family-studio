import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../services/player_controller.dart';
import '../theme.dart';

/// Lyrics of a song. With timings (MusicGPT) and the song playing, the sung
/// line lights up and scrolls into view, karaoke style; tapping a line jumps
/// there. Without timings the lyrics show as written, section labels dimmed.
class LyricsView extends StatelessWidget {
  const LyricsView({super.key, required this.song, required this.queue});
  final Song song;
  final List<Song> queue;

  @override
  Widget build(BuildContext context) {
    if (song.instrumental) {
      return const _Empty(text: '純音樂，冇歌詞');
    }
    final timed = song.lyricsTimed;
    if (timed != null) {
      return _TimedLyrics(song: song, lines: timed, queue: queue);
    }
    if (song.lyrics.trim().isEmpty) return const _Empty(text: '未有歌詞');
    final lines = song.lyrics.split('\n');
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, StudioSpacing.md, 0, 120),
      children: [
        for (final l in lines)
          if (RegExp(r'^\s*\[.*\]\s*$').hasMatch(l))
            Padding(
              padding: const EdgeInsets.only(top: StudioSpacing.lg, bottom: 4),
              child: Text(
                l.trim().replaceAll(RegExp(r'[\[\]]'), ''),
                style: const TextStyle(
                  color: StudioColors.textSecondary,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(l, style: const TextStyle(fontSize: 17, height: 1.4)),
            ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      style: const TextStyle(color: StudioColors.textSecondary),
    ),
  );
}

class _TimedLyrics extends StatefulWidget {
  const _TimedLyrics({
    required this.song,
    required this.lines,
    required this.queue,
  });
  final Song song;
  final List<LyricLine> lines;
  final List<Song> queue;

  @override
  State<_TimedLyrics> createState() => _TimedLyricsState();
}

class _TimedLyricsState extends State<_TimedLyrics> {
  late List<GlobalKey> _keys = _makeKeys();
  int _shown = -2;

  List<GlobalKey> _makeKeys() =>
      List.generate(widget.lines.length, (_) => GlobalKey());

  @override
  void didUpdateWidget(_TimedLyrics old) {
    super.didUpdateWidget(old);
    if (old.lines.length != widget.lines.length) _keys = _makeKeys();
  }

  void _follow(int active) {
    if (active == _shown) return;
    _shown = active;
    if (active < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[active].currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _jump(PlayerController p, LyricLine line) async {
    if (!p.isCurrent(widget.song.id)) {
      await p.playOrToggle(widget.song, widget.queue);
    }
    await p.seek(line.start);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final live = p.isCurrent(widget.song.id);
    final active = live ? LyricLine.activeIndex(widget.lines, p.position) : -1;
    if (live) _follow(active);
    // Every line is built (no lazy list), so ensureVisible can reach any of them.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, StudioSpacing.md, 0, 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.lines.length; i++)
            _line(p, i, active, live),
        ],
      ),
    );
  }

  Widget _line(PlayerController p, int i, int active, bool live) {
    final line = widget.lines[i];
    final isActive = i == active;
    final isPast = live && i < active;
    return InkWell(
      key: _keys[i],
      borderRadius: BorderRadius.circular(8),
      onTap: () => _jump(p, line),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: isActive ? 22 : 18,
            height: 1.35,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive
                ? StudioColors.textPrimary
                : isPast
                ? StudioColors.textSecondary.withValues(alpha: 0.55)
                : live
                ? StudioColors.textSecondary
                : StudioColors.textPrimary.withValues(alpha: 0.85),
          ),
          child: Text(line.text),
        ),
      ),
    );
  }
}

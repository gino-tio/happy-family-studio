import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/song.dart';
import '../models/stems.dart';
import '../screens/song_screen.dart';
import '../services/audio/audio_engine.dart';
import '../services/player_controller.dart';
import '../services/songs_service.dart';
import '../theme.dart';

/// 「樂器」tab of a song: 拆樂器 into six tracks (each plays and downloads on
/// its own), then 換歌詞 sings new lyrics over the instrumental track.
class StemsView extends StatefulWidget {
  const StemsView({super.key, required this.song});
  final Song song;

  @override
  State<StemsView> createState() => _StemsViewState();
}

class _StemsViewState extends State<StemsView> {
  late final Stream<SongStems?> _stems = context
      .read<SongsService>()
      .watchStems(widget.song.id);

  /// A separate output for previews, so the band's queue player keeps its song.
  AudioEngine? _preview;
  String? _playingPath;
  bool _starting = false;
  StreamSubscription<bool>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _split() async {
    setState(() => _starting = true);
    try {
      await context.read<SongsService>().splitSong(widget.song.id);
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _togglePlay(Stem stem) async {
    final engine = _preview ??= AudioEngine();
    _sub ??= engine.onPlaying.listen((p) {
      if (!p && mounted) setState(() => _playingPath = null);
    });
    if (_playingPath == stem.path) {
      await engine.pause();
      setState(() => _playingPath = null);
      return;
    }
    final player = context.read<PlayerController>();
    if (player.playing) await player.toggle();
    if (!mounted) return;
    final url = await context.read<SongsService>().stemUrl(stem.path);
    setState(() => _playingPath = stem.path);
    await engine.play(url);
  }

  Future<void> _download(Stem stem) async {
    final ext = stem.path.split('.').last;
    final url = await context.read<SongsService>().stemUrl(
      stem.path,
      downloadAs: '${widget.song.title} - ${stem.label}.$ext',
    );
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _swap(SongStems stems) async {
    final r = await showDialog<({String title, String lyrics})>(
      context: context,
      builder: (_) => _SwapDialog(song: widget.song),
    );
    if (r == null || !mounted) return;
    try {
      final song = await context.read<SongsService>().swapLyrics(
        widget.song.id,
        lyrics: r.lyrics,
        title: r.title,
      );
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => SongScreen(songId: song.id)));
    } catch (e) {
      _toast(e);
    }
  }

  void _toast(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: StudioColors.textSecondary);
    if (!widget.song.isPlayable) {
      return const Center(child: Text('首歌整好之後先可以拆樂器'));
    }
    return StreamBuilder<SongStems?>(
      stream: _stems,
      builder: (context, snap) {
        final stems = snap.data;
        final children = <Widget>[];
        if (stems == null || stems.isFailed) {
          children.addAll([
            if (stems?.isFailed ?? false)
              Text(
                '上次拆唔到：${stems!.error ?? ''}',
                style: const TextStyle(color: StudioColors.error),
              ),
            const Text('將首歌拆開人聲、伴奏、鋼琴、Bass、鼓同結他，每條都可以獨立播放同下載。'),
            const SizedBox(height: StudioSpacing.sm),
            Text('拆完之後可以「換歌詞」：用原曲伴奏唱新詞。', style: muted),
            const SizedBox(height: StudioSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed:
                    _starting || snap.connectionState == ConnectionState.waiting
                    ? null
                    : _split,
                icon: const Icon(Icons.call_split_rounded),
                label: Text(_starting ? '開始緊…' : '拆樂器'),
              ),
            ),
          ]);
        } else if (!stems.isDone) {
          children.addAll([
            const Row(
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: StudioSpacing.sm),
                Expanded(child: Text('拆緊樂器，大約 1 至 3 分鐘…')),
              ],
            ),
          ]);
        } else {
          for (final s in stems.stems) {
            final playing = _playingPath == s.path;
            children.add(
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: IconButton.filledTonal(
                  tooltip: playing ? '暫停' : '播放',
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  onPressed: () => _togglePlay(s),
                ),
                title: Text(s.label),
                trailing: IconButton(
                  tooltip: '下載',
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () => _download(s),
                ),
              ),
            );
          }
          children.addAll([
            const SizedBox(height: StudioSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: stems.instrumental == null
                    ? null
                    : () => _swap(stems),
                icon: const Icon(Icons.lyrics_outlined),
                label: const Text('換歌詞（用呢個伴奏唱新詞）'),
              ),
            ),
          ]);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, StudioSpacing.md, 0, 120),
          children: children,
        );
      },
    );
  }
}

/// New lyrics (and optionally a new title) for 換歌詞, starting from the old ones.
class _SwapDialog extends StatefulWidget {
  const _SwapDialog({required this.song});
  final Song song;

  @override
  State<_SwapDialog> createState() => _SwapDialogState();
}

class _SwapDialogState extends State<_SwapDialog> {
  late final _title = TextEditingController(text: '${widget.song.title}（新詞）');
  late final _lyrics = TextEditingController(text: widget.song.lyrics);

  @override
  void dispose() {
    _title.dispose();
    _lyrics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('換歌詞'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                maxLength: 120,
                decoration: const InputDecoration(labelText: '新歌名'),
              ),
              TextField(
                controller: _lyrics,
                maxLength: 5000,
                minLines: 6,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: '新歌詞（廣東話）',
                  alignLabelWithHint: true,
                ),
              ),
              const Text('用原曲嘅伴奏，MusicGPT 唱新詞，出兩個版本。每人每日 10 次。'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_lyrics.text.trim().isEmpty) return;
            Navigator.pop(context, (
              title: _title.text.trim(),
              lyrics: _lyrics.text.trim(),
            ));
          },
          child: const Text('開始'),
        ),
      ],
    );
  }
}

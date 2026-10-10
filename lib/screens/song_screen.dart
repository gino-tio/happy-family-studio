import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../services/songs_service.dart';
import '../theme.dart';
import 'library_screen.dart';

/// One song: live status while generating, then a player + the prompt and
/// lyrics that produced it.
class SongScreen extends StatelessWidget {
  const SongScreen({super.key, required this.songId});
  final String songId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Song?>(
      stream: context.read<SongsService>().watchSong(songId),
      builder: (context, snap) {
        final song = snap.data;
        return Scaffold(
          appBar: AppBar(title: Text(song?.title ?? '')),
          body: song == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(StudioSpacing.lg),
                  children: [
                    _StatusCard(song: song),
                    const SizedBox(height: StudioSpacing.lg),
                    if (song.style.isNotEmpty) ...[
                      Text('風格', style: Theme.of(context).textTheme.labelLarge),
                      SelectableText(song.style),
                      const SizedBox(height: StudioSpacing.lg),
                    ],
                    if (song.lyrics.isNotEmpty) ...[
                      Text('歌詞', style: Theme.of(context).textTheme.labelLarge),
                      SelectableText(song.lyrics),
                      const SizedBox(height: StudioSpacing.lg),
                    ],
                    Text(
                      '${song.provider} · ${song.model}',
                      style: const TextStyle(color: StudioColors.textSecondary),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (song.status) {
      SongStatus.queued || SongStatus.generating => const ListTile(
        leading: StatusIcon(status: SongStatus.generating),
        title: Text('AI 作緊歌…'),
        subtitle: Text('通常要一至三分鐘，可以離開呢頁，搞掂會自動更新'),
      ),
      SongStatus.failed => ListTile(
        leading: const StatusIcon(status: SongStatus.failed),
        title: const Text('生成失敗'),
        subtitle: Text(song.error ?? ''),
      ),
      SongStatus.done =>
        song.audioPath == null
            ? const ListTile(title: Text('冇音檔'))
            : _Player(path: song.audioPath!),
    };
    return Card(child: child);
  }
}

class _Player extends StatefulWidget {
  const _Player({required this.path});
  final String path;

  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  final _player = AudioPlayer();
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((p) => setState(() => _pos = p));
    _player.onDurationChanged.listen((d) => setState(() => _dur = d));
    _player.onPlayerStateChanged.listen(
      (s) => setState(() => _playing = s == PlayerState.playing),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) return _player.pause();
    if (!_loaded) {
      final url = await context.read<SongsService>().signedAudioUrl(
        widget.path,
      );
      await _player.setSourceUrl(url);
      _loaded = true;
    }
    await _player.resume();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final max = _dur.inMilliseconds.toDouble();
    return Padding(
      padding: const EdgeInsets.all(StudioSpacing.md),
      child: Row(
        children: [
          IconButton.filled(
            iconSize: 32,
            onPressed: _toggle,
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: Slider(
              max: max > 0 ? max : 1,
              value: _pos.inMilliseconds.clamp(0, max > 0 ? max : 1).toDouble(),
              onChanged: max > 0
                  ? (v) => _player.seek(Duration(milliseconds: v.round()))
                  : null,
            ),
          ),
          Text('${_fmt(_pos)} / ${_fmt(_dur)}'),
        ],
      ),
    );
  }
}

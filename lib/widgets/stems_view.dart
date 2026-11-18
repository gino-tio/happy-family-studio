import 'dart:async';

import 'package:flutter/foundation.dart';
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
/// its own), 出譜 per track (opens the sheet page), and 換歌詞, which sings
/// new lyrics over the instrumental track.
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

  late final Stream<Map<String, StemMidi>> _midis = context
      .read<SongsService>()
      .watchMidis(widget.song.id);

  /// Signed URLs fetched ahead, so a tap opens a new tab at once (browsers
  /// block a window opened after waiting on the network).
  final _signed = <String, String>{};
  final _signing = <String>{};
  final _midiAsked = <String>{};

  void _sign(String path, {String? downloadAs}) {
    final key = downloadAs == null ? path : '$path|dl';
    if (_signed.containsKey(key) || !_signing.add(key)) return;
    context
        .read<SongsService>()
        .stemUrl(path, downloadAs: downloadAs)
        .then((u) {
          if (mounted) setState(() => _signed[key] = u);
        })
        .catchError((_) {
          _signing.remove(key);
        });
  }

  String _downloadName(Stem s) =>
      '${widget.song.title} - ${s.label}.${s.path.split('.').last}';

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

  void _open(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// The sheet page lives with the web app; native apps open the live site.
  static Uri get _appBase => Uri.parse(
    kIsWeb ? '${Uri.base.origin}/' : 'https://studio.toolution.net/',
  );

  /// 出譜 for one track: drums open the sheet page at once (it reads the drum
  /// audio); other tracks first need MusicGPT's MIDI.
  Future<void> _sheet(SongStems stems, Stem s, StemMidi? midi) async {
    final drums = stems.stems.where((x) => x.kind == 'drums').firstOrNull;
    final drumsUrl = drums == null ? null : _signed[drums.path];
    if (s.kind == 'drums') {
      if (drumsUrl == null) return;
      _open(
        SongsService.sheetPage(
          appBase: _appBase,
          kind: 'drums',
          title: widget.song.title,
          drumsUrl: drumsUrl,
        ).toString(),
      );
      return;
    }
    if (midi != null && midi.isDone) {
      final midiUrl = _signed[midi.midiPath!];
      if (midiUrl == null) return;
      _open(
        SongsService.sheetPage(
          appBase: _appBase,
          kind: s.kind,
          title: widget.song.title,
          midiUrl: midiUrl,
          drumsUrl: drumsUrl,
        ).toString(),
      );
      return;
    }
    setState(() => _midiAsked.add(s.kind));
    try {
      await context.read<SongsService>().requestMidi(widget.song.id, s.kind);
    } catch (e) {
      _toast(e);
      if (mounted) setState(() => _midiAsked.remove(s.kind));
    }
  }

  Widget _sheetButton(SongStems stems, Stem s, StemMidi? midi) {
    if (s.kind == 'instrumental') return const SizedBox(width: 48);
    final busy =
        midi?.status == 'generating' ||
        (_midiAsked.contains(s.kind) && midi == null);
    if (busy) {
      return const Tooltip(
        message: '轉緊樂譜，大約 1 分鐘',
        child: SizedBox(
          width: 48,
          child: Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    final ready = s.kind == 'drums'
        ? _signed.containsKey(s.path)
        : midi == null || midi.isFailed || _signed.containsKey(midi.midiPath);
    return IconButton(
      tooltip: switch (s.kind) {
        'drums' => '鼓譜',
        'guitar' => '結他譜（tab）',
        'bass' => 'Bass 譜（tab）',
        _ => '樂譜',
      },
      icon: Icon(
        midi?.isFailed ?? false
            ? Icons.refresh_rounded
            : Icons.library_music_outlined,
      ),
      onPressed: ready ? () => _sheet(stems, s, midi) : null,
    );
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
            _sign(s.path);
            _sign(s.path, downloadAs: _downloadName(s));
          }
          return StreamBuilder<Map<String, StemMidi>>(
            stream: _midis,
            builder: (context, msnap) {
              final midis = msnap.data ?? const <String, StemMidi>{};
              for (final m in midis.values) {
                if (m.isDone) _sign(m.midiPath!);
              }
              return _doneList(stems, midis);
            },
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, StudioSpacing.md, 0, 120),
          children: children,
        );
      },
    );
  }

  Widget _doneList(SongStems stems, Map<String, StemMidi> midis) {
    final children = <Widget>[];
    for (final s in stems.stems) {
      final playing = _playingPath == s.path;
      final dl = _signed['${s.path}|dl'];
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
          subtitle: midis[s.kind]?.isFailed ?? false
              ? Text(
                  '出唔到譜：${midis[s.kind]!.error ?? ''}',
                  style: const TextStyle(color: StudioColors.error),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetButton(stems, s, midis[s.kind]),
              IconButton(
                tooltip: '下載',
                icon: const Icon(Icons.download_rounded),
                onPressed: dl == null ? null : () => _open(dl),
              ),
            ],
          ),
        ),
      );
    }
    children.addAll([
      const SizedBox(height: StudioSpacing.md),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: stems.instrumental == null ? null : () => _swap(stems),
          icon: const Icon(Icons.lyrics_outlined),
          label: const Text('換歌詞（用呢個伴奏唱新詞）'),
        ),
      ),
      const SizedBox(height: StudioSpacing.sm),
      Text(
        '♫ 掣出譜：結他同 Bass 出 tab，鋼琴同人聲出五線譜，鼓出鼓譜。'
        'AI 由錄音轉出嚟，大致啱，細節要人手執。每人每日出譜 20 次。',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: StudioColors.textSecondary),
      ),
    ]);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, StudioSpacing.md, 0, 120),
      children: children,
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

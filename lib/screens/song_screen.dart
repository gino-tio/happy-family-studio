import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../services/library_store.dart';
import '../services/songs_service.dart';
import '../theme.dart';
import '../widgets/comments_view.dart';
import '../widgets/cover_art.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/player_widgets.dart';
import '../widgets/song_cards.dart';
import '../widgets/stems_view.dart';

/// One song: big cover, player, like / playlist / cover buttons, and tabs for
/// lyrics (karaoke style when timed), family comments, instruments (拆樂器 /
/// 換歌詞) and details. Wide
/// screens put the cover on the left and the tabs on the right.
class SongScreen extends StatefulWidget {
  const SongScreen({super.key, required this.songId, this.queue = const []});
  final String songId;

  /// The list the song was opened from: what play / next walk through.
  final List<Song> queue;

  @override
  State<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends State<SongScreen> {
  int? _comments;
  bool _coverRequested = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final song = store.song(widget.songId);
    if (song == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: store.songsLoaded
              ? const Text('呢首歌已經刪咗')
              : const CircularProgressIndicator(),
        ),
      );
    }
    final queue = widget.queue.isEmpty ? store.playable : widget.queue;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 860;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [_menu(store, song)],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred cover behind everything, like a stage light.
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Opacity(
                opacity: 0.45,
                child: CoverArt(song: song, radius: 0, showPending: false),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x660E0D12), StudioColors.background],
                  stops: [0, 0.75],
                ),
              ),
            ),
          ),
          SafeArea(
            child: DefaultTabController(
              length: 4,
              child: wide
                  ? _wide(store, song, queue, size)
                  : _narrow(store, song, queue, size),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wide(LibraryStore store, Song song, List<Song> queue, Size size) {
    final coverW = (size.width * 0.36).clamp(300.0, 460.0);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            StudioSpacing.xxl,
            StudioSpacing.sm,
            StudioSpacing.xxl,
            0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: coverW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bigCover(store, song, coverW),
                    const SizedBox(height: StudioSpacing.lg),
                    _status(song),
                  ],
                ),
              ),
              const SizedBox(width: StudioSpacing.xxl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _controls(song, queue),
                    const SizedBox(height: StudioSpacing.sm),
                    _tabs(),
                    Expanded(child: _tabViews(store, song, queue)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _narrow(LibraryStore store, Song song, List<Song> queue, Size size) {
    final coverW = (size.height * 0.3).clamp(160.0, size.width - 64);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: StudioSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CoverArt(song: song, size: coverW),
              const SizedBox(width: StudioSpacing.lg),
              if (coverW < size.width * 0.6)
                Expanded(child: _titleBlock(store, song)),
            ],
          ),
          if (coverW >= size.width * 0.6) ...[
            const SizedBox(height: StudioSpacing.md),
            _titleBlock(store, song),
          ],
          _status(song),
          const SizedBox(height: StudioSpacing.sm),
          _controls(song, queue),
          _tabs(),
          Expanded(child: _tabViews(store, song, queue)),
        ],
      ),
    );
  }

  /// Big cover with the title over its top, as on music sites.
  Widget _bigCover(LibraryStore store, Song song, double w) {
    return SizedBox.square(
      dimension: w,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverArt(song: song, radius: StudioRadius.panel),
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 140,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(StudioRadius.panel),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xAA000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned(
            left: StudioSpacing.lg,
            right: StudioSpacing.lg,
            top: StudioSpacing.lg,
            child: _titleBlock(store, song),
          ),
        ],
      ),
    );
  }

  Widget _titleBlock(LibraryStore store, Song song) {
    final who = store.member(song.createdBy);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          song.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            MemberAvatar(member: who, radius: 10),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${who.name} · ${DateFormat('M月d日').format(song.createdAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: StudioColors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _status(Song song) {
    return switch (song.status) {
      SongStatus.queued || SongStatus.generating => const Card(
        child: ListTile(
          leading: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('AI 作緊歌…'),
          subtitle: Text('通常要一至三分鐘，可以離開呢頁，搞掂會自動更新'),
        ),
      ),
      SongStatus.failed => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: StudioColors.error),
          title: const Text('生成失敗'),
          subtitle: Text(song.error ?? ''),
        ),
      ),
      SongStatus.done => const SizedBox.shrink(),
    };
  }

  Widget _controls(Song song, List<Song> queue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: StudioSpacing.sm,
          runSpacing: StudioSpacing.sm,
          children: [
            PlayerControls(song: song, context_: queue),
            const SizedBox(width: StudioSpacing.sm),
            LikeButton(songId: song.id),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: StudioColors.textPrimary,
                side: const BorderSide(color: StudioColors.divider),
                shape: const StadiumBorder(),
              ),
              onPressed: song.isPlayable
                  ? () => showAddToPlaylist(context, song)
                  : null,
              icon: const Icon(Icons.playlist_add_rounded, size: 20),
              label: const Text('Playlist'),
            ),
          ],
        ),
        if (song.isPlayable) ProgressBar(songId: song.id),
      ],
    );
  }

  Widget _tabs() => TabBar(
    isScrollable: true,
    tabs: [
      const Tab(text: '歌詞'),
      Tab(text: _comments == null || _comments == 0 ? '留言' : '$_comments 留言'),
      const Tab(text: '樂器'),
      const Tab(text: '資料'),
    ],
  );

  Widget _tabViews(LibraryStore store, Song song, List<Song> queue) {
    return TabBarView(
      children: [
        LyricsView(song: song, queue: queue),
        CommentsView(
          songId: song.id,
          onCount: (n) {
            if (n != _comments && mounted) setState(() => _comments = n);
          },
        ),
        StemsView(key: ValueKey(song.id), song: song),
        _details(store, song),
      ],
    );
  }

  Widget _details(LibraryStore store, Song song) {
    final len = song.lengthMs;
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              k,
              style: const TextStyle(color: StudioColors.textSecondary),
            ),
          ),
          Expanded(child: SelectableText(v)),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, StudioSpacing.md, 0, 120),
      children: [
        row('作者', store.member(song.createdBy).name),
        row('日期', DateFormat('yyyy年M月d日 HH:mm').format(song.createdAt)),
        if (len != null) row('長度', formatDuration(Duration(milliseconds: len))),
        row('風格', song.style.isEmpty ? '—' : song.style),
        row(
          '歌手',
          song.provider == 'musicgpt'
              ? 'MusicGPT（廣東話）· ${switch (song.model) {
                  'sing_over_instrumental' => '換歌詞',
                  'remix' => '由上載嘅歌整',
                  _ => song.model,
                }}'
              : '${song.provider} · ${song.model}',
        ),
        row('鍾意', '${store.likeCount(song.id)} 個 ♥'),
        const SizedBox(height: StudioSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _coverRequested ? null : () => _newCover(song),
            icon: const Icon(Icons.palette_outlined),
            label: Text(_coverRequested ? 'AI 畫緊新封面…' : '換封面（AI 畫）'),
          ),
        ),
      ],
    );
  }

  Future<void> _newCover(Song song) async {
    setState(() => _coverRequested = true);
    final before = song.coverPath;
    try {
      await context.read<SongsService>().requestNewCover(song.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI 畫緊，大約一分鐘後自動換上')));
      // Re-enable once the new cover lands (or after 3 minutes).
      final store = context.read<LibraryStore>();
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      void check() {
        final now = store.song(song.id)?.coverPath;
        if (now != before || DateTime.now().isAfter(deadline)) {
          store.removeListener(check);
          if (mounted) setState(() => _coverRequested = false);
        }
      }

      store.addListener(check);
    } catch (e) {
      if (!mounted) return;
      setState(() => _coverRequested = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _menu(LibraryStore store, Song song) {
    final mine = song.createdBy == store.me;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (v) async {
        switch (v) {
          case 'cover':
            await _newCover(song);
          case 'rename':
            final name = await askPlaylistName(
              context,
              initial: song.title,
              title: '改歌名',
            );
            if (name != null && mounted) {
              await context.read<SongsService>().rename(song.id, name);
            }
          case 'delete':
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('刪除「${song.title}」？'),
                content: const Text('歌、留言同心都會一齊刪走，冇得還原。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: StudioColors.error,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('刪除'),
                  ),
                ],
              ),
            );
            if (ok == true && mounted) {
              await context.read<SongsService>().delete(song.id);
              if (mounted) Navigator.of(context).pop();
            }
        }
      },
      itemBuilder: (_) => [
        if (!_coverRequested)
          const PopupMenuItem(value: 'cover', child: Text('換封面（AI 畫）')),
        if (mine) const PopupMenuItem(value: 'rename', child: Text('改歌名')),
        if (mine) const PopupMenuItem(value: 'delete', child: Text('刪除首歌')),
      ],
    );
  }
}

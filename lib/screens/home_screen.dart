import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../services/auth_service.dart';
import '../services/library_store.dart';
import '../services/player_controller.dart';
import '../services/songs_service.dart';
import '../theme.dart';
import '../widgets/song_cards.dart';
import 'beat_screen.dart';
import 'compose_screen.dart';

/// 首頁: rows of big covers (newest, mine, my likes, playlists), then every
/// song as a track list. Everything is live over Realtime.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    context.read<LibraryStore>().start();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final width = MediaQuery.sizeOf(context).width;
    final pad = width >= 720 ? StudioSpacing.xxl : StudioSpacing.lg;
    final cardW = width >= 720 ? 188.0 : 148.0;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: pad,
        title: const Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '開心家庭大樂隊 ',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text: 'Studio',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: StudioColors.neon,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Beat 格仔',
            icon: const Icon(Icons.grid_on_rounded),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BeatScreen())),
          ),
          IconButton(
            tooltip: '登出',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              final store = context.read<LibraryStore>();
              await context.read<PlayerController>().close();
              if (context.mounted) await context.read<AuthService>().signOut();
              store.reset();
            },
          ),
          SizedBox(width: pad - StudioSpacing.sm),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ComposeScreen())),
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text('作新歌'),
      ),
      body: _body(store, pad, cardW),
    );
  }

  Widget _body(LibraryStore store, double pad, double cardW) {
    if (store.error != null && !store.songsLoaded) {
      return Center(child: Text('載入失敗：${store.error}'));
    }
    if (!store.songsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (store.songs.isEmpty) {
      return const Center(child: Text('未有歌 — 撳「作新歌」開始'));
    }
    final latest = store.songs.take(12).toList();
    final mine = store.songsBy(store.me ?? '');
    final liked = store.myLikes;
    final all = store.songs;
    final playable = store.playable;
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        _Hero(pad: pad, songs: playable),
        _Row(
          title: '最新作品',
          pad: pad,
          height: cardW / 0.8 + 64,
          children: [
            for (final s in latest)
              SongCard(song: s, queue: latest, width: cardW),
          ],
        ),
        if (liked.isNotEmpty)
          _Row(
            title: '我鍾意',
            pad: pad,
            height: cardW / 0.8 + 64,
            children: [
              for (final s in liked)
                SongCard(song: s, queue: liked, width: cardW),
            ],
          ),
        _Row(
          title: 'Playlists',
          pad: pad,
          height: cardW + 64,
          trailing: TextButton.icon(
            onPressed: () => _newPlaylist(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新 playlist'),
          ),
          children: [
            for (final pl in store.playlists)
              PlaylistCard(playlist: pl, width: cardW),
            if (store.playlists.isEmpty)
              SizedBox(
                width: cardW,
                child: _NewPlaylistTile(onTap: () => _newPlaylist(context)),
              ),
          ],
        ),
        if (mine.isNotEmpty)
          _Row(
            title: '我嘅歌',
            pad: pad,
            height: cardW / 0.8 + 64,
            children: [
              for (final s in mine)
                SongCard(song: s, queue: mine, width: cardW),
            ],
          ),
        _SectionTitle(title: '全部歌 (${all.length})', pad: pad),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad - 4),
          child: Column(
            children: [
              for (var i = 0; i < all.length; i++)
                SongRow(song: all[i], queue: all, number: i + 1),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _newPlaylist(BuildContext context) async {
    final name = await askPlaylistName(context);
    if (name == null || !context.mounted) return;
    try {
      final id = await context.read<SongsService>().createPlaylist(name);
      if (context.mounted) SongActions.of(context).openPlaylist(id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('開唔到：$e')));
      }
    }
  }
}

/// Top banner: the newest finished song with play-all / shuffle.
class _Hero extends StatelessWidget {
  const _Hero({required this.pad, required this.songs});
  final double pad;
  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox(height: StudioSpacing.md);
    final p = context.read<PlayerController>();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        pad,
        StudioSpacing.sm,
        pad,
        StudioSpacing.md,
      ),
      child: Wrap(
        spacing: StudioSpacing.sm,
        runSpacing: StudioSpacing.sm,
        children: [
          FilledButton.icon(
            onPressed: () {
              if (p.shuffle) p.toggleShuffle();
              p.playQueue(songs);
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text('播晒全部 ${songs.length} 首'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              if (!p.shuffle) p.toggleShuffle();
              p.playQueue(songs);
            },
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text('隨機播'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.pad, this.trailing});
  final String title;
  final double pad;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      pad,
      StudioSpacing.lg,
      pad - 8,
      StudioSpacing.sm,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.pad,
    required this.height,
    required this.children,
    this.trailing,
  });
  final String title;
  final double pad;
  final double height;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle(title: title, pad: pad, trailing: trailing),
      SizedBox(
        height: height,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: pad - 6),
          children: children,
        ),
      ),
    ],
  );
}

class _NewPlaylistTile extends StatelessWidget {
  const _NewPlaylistTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: StudioColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(StudioRadius.cover),
              side: const BorderSide(color: StudioColors.divider),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(StudioRadius.cover),
              child: const Center(child: Icon(Icons.add_rounded, size: 40)),
            ),
          ),
        ),
        const SizedBox(height: StudioSpacing.sm),
        const Text('新 playlist', style: TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

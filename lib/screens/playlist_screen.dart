import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/library_store.dart';
import '../services/player_controller.dart';
import '../services/songs_service.dart';
import '../theme.dart';
import '../widgets/comments_view.dart';
import '../widgets/song_cards.dart';

/// One playlist: collage cover, play all / shuffle, and its songs. Everyone in
/// the band can play it; only its maker renames, deletes or removes songs.
class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final pl = store.playlist(playlistId);
    if (pl == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('呢個 playlist 已經刪咗')),
      );
    }
    final songs = store.playlistSongs(pl.id);
    final playable = songs.where((s) => s.isPlayable).toList();
    final mine = pl.createdBy == store.me;
    final owner = store.member(pl.createdBy);
    final width = MediaQuery.sizeOf(context).width;
    final pad = width >= 720 ? StudioSpacing.xxl : StudioSpacing.lg;
    final coverW = width >= 720 ? 220.0 : 140.0;
    final service = context.read<SongsService>();
    final p = context.read<PlayerController>();
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (mine)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (v) async {
                if (v == 'rename') {
                  final name = await askPlaylistName(
                    context,
                    initial: pl.name,
                    title: '改名',
                  );
                  if (name != null) await service.renamePlaylist(pl.id, name);
                } else if (v == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('刪除「${pl.name}」？'),
                      content: const Text('首歌唔會刪，淨係刪個 playlist。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('刪除'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await service.deletePlaylist(pl.id);
                    if (context.mounted) Navigator.of(context).pop();
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('改名')),
                PopupMenuItem(value: 'delete', child: Text('刪除 playlist')),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 140),
        children: [
          Wrap(
            spacing: StudioSpacing.xl,
            runSpacing: StudioSpacing.lg,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox.square(
                dimension: coverW,
                child: PlaylistCover(songs: songs, id: pl.id),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'PLAYLIST',
                    style: TextStyle(
                      color: StudioColors.textSecondary,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width - pad * 2),
                    child: Text(
                      pl.name,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MemberAvatar(member: owner, radius: 10),
                      const SizedBox(width: 6),
                      Text(
                        '${owner.name} · ${songs.length} 首',
                        style: const TextStyle(
                          color: StudioColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: StudioSpacing.md),
                  Wrap(
                    spacing: StudioSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: playable.isEmpty
                            ? null
                            : () {
                                if (p.shuffle) p.toggleShuffle();
                                p.playQueue(playable);
                              },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('播放'),
                      ),
                      OutlinedButton.icon(
                        onPressed: playable.isEmpty
                            ? null
                            : () {
                                if (!p.shuffle) p.toggleShuffle();
                                p.playQueue(playable);
                              },
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('隨機'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: StudioSpacing.xl),
          if (songs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(StudioSpacing.xl),
              child: Center(
                child: Text(
                  '未有歌。喺首歌度撳「Playlist」加入嚟。',
                  style: TextStyle(color: StudioColors.textSecondary),
                ),
              ),
            ),
          for (var i = 0; i < songs.length; i++)
            SongRow(
              song: songs[i],
              queue: playable,
              number: i + 1,
              trailing: mine
                  ? IconButton(
                      tooltip: '由 playlist 移除',
                      iconSize: 20,
                      color: StudioColors.textSecondary,
                      onPressed: () =>
                          service.removeFromPlaylist(pl.id, songs[i].id),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/social.dart';
import '../models/song.dart';
import '../services/library_store.dart';
import '../services/player_controller.dart';
import '../services/songs_service.dart';
import '../theme.dart';
import 'cover_art.dart';
import 'player_widgets.dart';

/// Opens a song's screen; set by HomeShell so any widget can call it.
typedef OpenSong = void Function(Song song, List<Song> queue);

class SongActions extends InheritedWidget {
  const SongActions({
    super.key,
    required this.openSong,
    required this.openPlaylist,
    required super.child,
  });

  final OpenSong openSong;
  final void Function(String playlistId) openPlaylist;

  static SongActions of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SongActions>()!;

  @override
  bool updateShouldNotify(SongActions old) => false;
}

/// Big cover card for the horizontal rows on the home screen.
class SongCard extends StatelessWidget {
  const SongCard({
    super.key,
    required this.song,
    required this.queue,
    this.width = 168,
  });

  final Song song;
  final List<Song> queue;
  final double width;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final p = context.watch<PlayerController>();
    final isCurrent = p.isCurrent(song.id);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(StudioRadius.card),
        onTap: () {
          if (song.isPlayable && !isCurrent) p.playOrToggle(song, queue);
          SongActions.of(context).openSong(song, queue);
        },
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 0.8,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverArt(song: song),
                    if (isCurrent && p.playing)
                      const Positioned(
                        left: 8,
                        bottom: 8,
                        child: _NowPlayingBadge(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: StudioSpacing.sm),
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isCurrent ? StudioColors.neon : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _subtitle(store, song),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: StudioColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _subtitle(LibraryStore store, Song song) {
  final who = store.member(song.createdBy).name;
  return switch (song.status) {
    SongStatus.queued || SongStatus.generating => '$who · AI 作緊歌…',
    SongStatus.failed => '$who · 生成失敗',
    SongStatus.done => () {
      final n = store.likeCount(song.id);
      return n > 0 ? '$who · ♥ $n' : who;
    }(),
  };
}

class _NowPlayingBadge extends StatelessWidget {
  const _NowPlayingBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(6),
    decoration: const BoxDecoration(
      color: Color(0xAA000000),
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.graphic_eq_rounded, size: 18),
  );
}

/// One row of a track list: number, cover, title, by, likes, length.
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.song,
    required this.queue,
    this.number,
    this.trailing,
  });

  final Song song;
  final List<Song> queue;
  final int? number;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final p = context.watch<PlayerController>();
    final isCurrent = p.isCurrent(song.id);
    final len = song.lengthMs;
    return InkWell(
      borderRadius: BorderRadius.circular(StudioRadius.input),
      onTap: () {
        if (song.isPlayable && !isCurrent) p.playOrToggle(song, queue);
        SongActions.of(context).openSong(song, queue);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            if (number != null)
              SizedBox(
                width: 28,
                child: isCurrent && p.playing
                    ? const Icon(
                        Icons.graphic_eq_rounded,
                        size: 18,
                        color: StudioColors.neon,
                      )
                    : Text(
                        '$number',
                        style: const TextStyle(
                          color: StudioColors.textSecondary,
                        ),
                      ),
              ),
            CoverArt(song: song, size: 52, radius: 8),
            const SizedBox(width: StudioSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? StudioColors.neon : null,
                    ),
                  ),
                  Text(
                    _subtitle(store, song),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: StudioColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (len != null && song.isPlayable)
              Padding(
                padding: const EdgeInsets.only(left: StudioSpacing.sm),
                child: Text(
                  formatDuration(Duration(milliseconds: len)),
                  style: const TextStyle(
                    color: StudioColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// 2x2 collage of the first covers of a playlist (or one cover / a gradient).
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.songs, required this.id});
  final List<Song> songs;
  final String id;

  @override
  Widget build(BuildContext context) {
    final withCover = songs.where((s) => s.coverPath != null).toList();
    if (withCover.length >= 4) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(StudioRadius.cover),
        child: GridView.count(
          crossAxisCount: 2,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            for (final s in withCover.take(4))
              CoverArt(song: s, radius: 0, showPending: false),
          ],
        ),
      );
    }
    if (songs.isNotEmpty) {
      return CoverArt(
        song: withCover.isNotEmpty ? withCover.first : songs.first,
        showPending: false,
      );
    }
    final (a, b) = coverGradient(id);
    return ClipRRect(
      borderRadius: BorderRadius.circular(StudioRadius.cover),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [a, b])),
        child: const Center(
          child: Icon(
            Icons.queue_music_rounded,
            size: 48,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.playlist, this.width = 168});
  final Playlist playlist;
  final double width;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final songs = store.playlistSongs(playlist.id);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(StudioRadius.card),
        onTap: () => SongActions.of(context).openPlaylist(playlist.id),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: PlaylistCover(songs: songs, id: playlist.id),
              ),
              const SizedBox(height: StudioSpacing.sm),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${store.member(playlist.createdBy).name} · ${songs.length} 首',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: StudioColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a playlist name; null when cancelled.
Future<String?> askPlaylistName(
  BuildContext context, {
  String initial = '',
  String title = '新 playlist',
}) {
  final text = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: text,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(hintText: '例如：車上聽'),
        onSubmitted: (v) =>
            Navigator.pop(context, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            text.text.trim().isEmpty ? null : text.text.trim(),
          ),
          child: const Text('好'),
        ),
      ],
    ),
  );
}

/// Bottom sheet: tick my playlists to add / remove [song], or make a new one.
Future<void> showAddToPlaylist(BuildContext context, Song song) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _AddToPlaylistSheet(song: song),
  );
}

class _AddToPlaylistSheet extends StatelessWidget {
  const _AddToPlaylistSheet({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final service = context.read<SongsService>();
    final mine = store.playlists.where((p) => p.createdBy == store.me).toList();
    void fail(Object e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('做唔到：$e')));
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          StudioSpacing.lg,
          0,
          StudioSpacing.lg,
          StudioSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('加入 playlist', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: StudioSpacing.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: StudioColors.surfaceHigh,
                child: Icon(Icons.add_rounded),
              ),
              title: const Text('新 playlist'),
              onTap: () async {
                final name = await askPlaylistName(context);
                if (name == null) return;
                try {
                  final id = await service.createPlaylist(name);
                  await service.addToPlaylist(id, song.id, 1);
                } catch (e) {
                  if (context.mounted) fail(e);
                }
              },
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final pl in mine)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: store.inPlaylist(pl.id, song.id),
                      title: Text(pl.name),
                      subtitle: Text('${store.playlistSongs(pl.id).length} 首'),
                      onChanged: (v) async {
                        try {
                          if (v == true) {
                            await service.addToPlaylist(
                              pl.id,
                              song.id,
                              store.nextPosition(pl.id),
                            );
                          } else {
                            await service.removeFromPlaylist(pl.id, song.id);
                          }
                        } catch (e) {
                          if (context.mounted) fail(e);
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

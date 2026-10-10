import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../services/auth_service.dart';
import '../services/songs_service.dart';
import '../theme.dart';
import 'compose_screen.dart';
import 'song_screen.dart';

/// 歌曲庫 — every song the band has generated, live over Realtime.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final songs = context.read<SongsService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('歌曲庫'),
        actions: [
          IconButton(
            tooltip: '登出',
            icon: const Icon(Icons.logout),
            onPressed: context.read<AuthService>().signOut,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ComposeScreen())),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('作新歌'),
      ),
      body: StreamBuilder<List<Song>>(
        stream: songs.watchSongs(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('載入失敗：${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(child: Text('未有歌 — 撳「作新歌」開始'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              StudioSpacing.lg,
              StudioSpacing.lg,
              StudioSpacing.lg,
              96,
            ),
            itemCount: list.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: StudioSpacing.sm),
            itemBuilder: (context, i) => SongTile(song: list[i]),
          );
        },
      ),
    );
  }
}

class SongTile extends StatelessWidget {
  const SongTile({super.key, required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    final when = DateFormat('M月d日 HH:mm').format(song.createdAt);
    return Card(
      child: ListTile(
        leading: StatusIcon(status: song.status),
        title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          song.style.isEmpty ? when : '$when · ${song.style}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => SongScreen(songId: song.id))),
      ),
    );
  }
}

class StatusIcon extends StatelessWidget {
  const StatusIcon({super.key, required this.status});
  final SongStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      SongStatus.queued || SongStatus.generating => const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      SongStatus.done => const Icon(Icons.music_note, color: StudioColors.neon),
      SongStatus.failed => const Icon(
        Icons.error_outline,
        color: StudioColors.error,
      ),
    };
  }
}
